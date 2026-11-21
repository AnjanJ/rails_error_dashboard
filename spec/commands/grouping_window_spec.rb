# frozen_string_literal: true

require "rails_helper"

# An open group is matched by its LAST occurrence: a capture counts on it while
# it was last seen less than 24 hours ago, however long ago it was first seen,
# and starts a new group once it has been quiet for 24 hours. A legacy row with
# a NULL last_seen_at falls back to occurred_at. The same rule holds at all
# three lookups: FindOrIncrementError's find_unresolved, its duplicate-create
# retry, and FlushStormCounts#unresolved_target.
#
# See .shipkit/specs/hardening-1-0-rc2 (REQ-9, REQ-10, REQ-11, and the decision
# "Match an open group by its last occurrence").
RSpec.describe "Grouping window" do
  let(:gate) { RailsErrorDashboard::Services::StormProtection::Gate }
  let(:generator) { RailsErrorDashboard::Services::ErrorHashGenerator }
  let(:logs) { RailsErrorDashboard::ErrorLog }
  let(:context) { { controller_name: "widgets", action_name: "show" } }
  let(:application) do
    RailsErrorDashboard::Application.find_or_create_by_name(RailsErrorDashboard.resolved_application_name)
  end
  let(:identities) { generator.identities(boom, context) }
  let(:v2_hash) { generator.complete(identities[:v2], application.id) }
  let(:v1_hash) { generator.complete(identities[:v1], application.id) }
  let(:environment) { Rails.env.to_s }

  # Frozen, so "exactly 24 hours ago" means the same instant to the seed and to
  # the lookup. Relative to now: the UTC day boundary moves with it.
  around { |example| travel_to(Time.current) { example.run } }

  before do
    RailsErrorDashboard.reset_configuration!
    RailsErrorDashboard.configuration.enable_storm_protection = true
    gate.reset!
    allow(gate.breaker).to receive(:record!).and_return(:open)
    allow(gate.breaker).to receive(:episode_snapshot).and_return(nil)
    allow(gate).to receive(:maybe_flush!)
  end

  after do
    gate.reset!
    RailsErrorDashboard.reset_configuration!
  end

  def boom
    error = ArgumentError.new("widget 42 failed")
    error.set_backtrace([
      "#{Rails.root}/app/services/widget_service.rb:12:in 'explode'",
      "#{Rails.root}/app/controllers/widgets_controller.rb:5:in 'show'"
    ])
    error
  end

  # The attributes LogError hands FindOrIncrementError for this capture.
  def capture_attributes
    {
      application_id: application.id,
      error_type: "ArgumentError",
      message: "widget N failed",
      backtrace: "app/services/widget_service.rb:12:in 'explode'",
      controller_name: "widgets",
      action_name: "show",
      occurred_at: Time.current,
      environment: environment,
      error_hash: v2_hash,
      _error_hash_v1: v1_hash
    }
  end

  # An open group first seen `first` hours ago and last seen `last` hours ago.
  # A nil `last` is a legacy row from before last_seen_at was written.
  def seed_group(error_hash, first:, last:)
    row = logs.create!(
      application_id: application.id,
      error_type: "ArgumentError",
      message: "widget N failed",
      error_hash: error_hash,
      environment: environment,
      occurred_at: first.hours.ago,
      first_seen_at: first.hours.ago,
      last_seen_at: (last || first).hours.ago,
      occurrence_count: 3,
      resolved: false,
      status: "new"
    )
    row.update_columns(last_seen_at: nil) if last.nil?
    row
  end

  # Path 1: FindOrIncrementError's first lookup.
  def capture_by_lookup
    RailsErrorDashboard::Commands::FindOrIncrementError.call(v2_hash, capture_attributes)
  end

  # Path 2: the duplicate-create retry. The first lookup misses and the INSERT
  # loses a race, so the group must be found by the retry's own lookup.
  def capture_by_retry
    command = RailsErrorDashboard::Commands::FindOrIncrementError.new(v2_hash, capture_attributes)
    first_pass = true
    allow(command).to receive(:find_unresolved).and_wrap_original do |original|
      next original.call unless first_pass

      first_pass = false
      nil
    end
    allow(logs).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)
    command.call
  end

  # Path 3: the storm flush, with the entry exactly as the gate buffers it.
  def capture_by_flush
    gate.admit!(boom, context)
    RailsErrorDashboard::Commands::FlushStormCounts.call(entries: gate.count_buffer.snapshot![:entries])
  end

  window_cases = {
    "first seen 30 h ago and last seen 1 h ago" => { first: 30, last: 1, counted: true, req: "REQ-9" },
    "first seen 30 h ago and last seen 25 h ago" => { first: 30, last: 25, counted: false, req: "REQ-10" },
    "first seen 30 h ago and last seen exactly 24 h ago" => { first: 30, last: 24, counted: false, req: "REQ-10" },
    "a NULL last_seen_at and first seen 1 h ago" => { first: 1, last: nil, counted: true, req: "REQ-9" },
    "a NULL last_seen_at and first seen 25 h ago" => { first: 25, last: nil, counted: false, req: "REQ-10" }
  }

  { "v2" => :v2_hash, "v1" => :v1_hash }.each do |hash_label, hash_name|
    window_cases.each do |label, window|
      outcome = window[:counted] ? "counts on the group" : "starts a new group"

      it "lookup: an open #{hash_label} group #{label} #{outcome} (hardening-1-0-rc2/#{window[:req]})" do
        group = seed_group(public_send(hash_name), first: window[:first], last: window[:last])

        result = capture_by_lookup

        if window[:counted]
          expect(result.id).to eq(group.id)
          expect(group.reload.occurrence_count).to eq(4)
          expect(group.error_hash).to eq(v2_hash)
          expect(logs.count).to eq(1)
        else
          expect(result.id).not_to eq(group.id)
          expect(group.reload.occurrence_count).to eq(3)
          expect(group.error_hash).to eq(public_send(hash_name))
          expect(result.reload.error_hash).to eq(v2_hash)
          expect(logs.count).to eq(2)
        end
      end

      # A stale group is the only candidate here. With a race winner beside
      # it, the retry would pick the winner (most recently seen first) whether
      # or not the window excluded the stale group, so the case would prove
      # nothing. Alone, a stale group the retry wrongly matched would be
      # counted; correctly excluded, nothing in the window holds the identity
      # the INSERT collided on, and the retry re-raises it.
      retry_outcome = window[:counted] ? "counts on the group" : "is not counted on the group"

      it "duplicate-create retry: an open #{hash_label} group #{label} #{retry_outcome} (hardening-1-0-rc2/#{window[:req]}, hardening-1-0-rc2/REQ-11)" do
        group = seed_group(public_send(hash_name), first: window[:first], last: window[:last])

        if window[:counted]
          result = capture_by_retry

          expect(result.id).to eq(group.id)
          expect(group.reload.occurrence_count).to eq(4)
          expect(group.error_hash).to eq(v2_hash)
          expect(logs.count).to eq(1)
        else
          expect { capture_by_retry }.to raise_error(ActiveRecord::RecordNotUnique)

          expect(group.reload.occurrence_count).to eq(3)
          expect(group.error_hash).to eq(public_send(hash_name))
        end
      end

      it "storm flush: an open #{hash_label} group #{label} #{outcome} (hardening-1-0-rc2/#{window[:req]}, hardening-1-0-rc2/REQ-11)" do
        group = seed_group(public_send(hash_name), first: window[:first], last: window[:last])

        result = capture_by_flush

        expect(result[:success]).to be true
        if window[:counted]
          expect(group.reload.occurrence_count).to eq(4)
          expect(group.error_hash).to eq(v2_hash)
          expect(logs.count).to eq(1)
        else
          expect(group.reload.occurrence_count).to eq(3)
          expect(group.error_hash).to eq(public_send(hash_name))
          expect(logs.where.not(id: group.id).sole).to have_attributes(error_hash: v2_hash, occurrence_count: 1)
        end
      end
    end
  end
end
