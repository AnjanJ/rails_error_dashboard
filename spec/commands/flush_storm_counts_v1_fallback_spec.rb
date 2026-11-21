# frozen_string_literal: true

require "rails_helper"

# The storm gate, count buffer and flush carry v1 beside v2.
# See .shipkit/specs/hardening-1-0-rc2 (REQ-5, REQ-6, and the decisions "Rows
# grouped under v1 keep their occurrences" and "One identity function, and the
# storm gate's hot path").
RSpec.describe RailsErrorDashboard::Commands::FlushStormCounts, "v1 fallback" do
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

  # Entries exactly as the gate buffers them and StormFlushJob receives them.
  def counted_entries(times)
    times.times { gate.admit!(boom, context) }
    gate.count_buffer.snapshot![:entries]
  end

  def seed_group(error_hash, **status_attributes)
    logs.create!(
      application_id: application.id,
      error_type: "ArgumentError",
      message: "widget 42 failed",
      error_hash: error_hash,
      environment: Rails.env.to_s,
      occurred_at: 1.hour.ago,
      first_seen_at: 1.hour.ago,
      last_seen_at: 1.hour.ago,
      occurrence_count: 3,
      resolved: false,
      status: "new",
      **status_attributes
    )
  end

  {
    "open" => {},
    "resolved" => { resolved: true, status: "resolved", resolved_at: 2.hours.ago },
    "wont_fix" => { status: "wont_fix" }
  }.each do |label, status_attributes|
    it "counts a flushed entry on a v1-only #{label} group and moves it to v2 (hardening-1-0-rc2/REQ-5)" do
      group = seed_group(v1_hash, **status_attributes)

      expect { described_class.call(entries: counted_entries(5)) }.not_to change(logs, :count)

      group.reload
      expect(group.occurrence_count).to eq(8)
      expect(group.error_hash).to eq(v2_hash)
    end
  end

  it "buffers v2 as the identity, with v1 beside it" do
    entry = counted_entries(1).sole

    expect(entry["opaque_identity"]).to eq(identities[:v2])
    expect(entry["opaque_identity_v1"]).to eq(identities[:v1])
  end

  # rc.1 buffered one identity, v1, as opaque_identity, and nothing else.
  it "counts an rc.1-shaped entry on its v1 group and leaves the hash as v1 (hardening-1-0-rc2/REQ-6)" do
    group = seed_group(v1_hash)
    entry = counted_entries(5).sole.except("opaque_identity_v1")
    entry["opaque_identity"] = identities[:v1]

    expect { described_class.call(entries: [ entry ]) }.not_to change(logs, :count)

    group.reload
    expect(group.occurrence_count).to eq(8)
    expect(group.error_hash).to eq(v1_hash)
  end

  it "prefers a v2 group to a more recently seen v1 group (hardening-1-0-rc2/REQ-5)" do
    v1_group = seed_group(v1_hash, last_seen_at: 1.minute.ago)
    v2_group = seed_group(v2_hash)

    described_class.call(entries: counted_entries(5))

    expect(v2_group.reload.occurrence_count).to eq(8)
    expect(v1_group.reload.occurrence_count).to eq(3)
    expect(v1_group.error_hash).to eq(v1_hash)
  end

  it "keeps v1 and still counts when the move hits RecordNotUnique (hardening-1-0-rc2/REQ-5)" do
    # MySQL has no partial indexes, so the group-identity index isn't built
    # there and the move can't collide.
    unless RailsErrorDashboard::ErrorLog.connection.index_name_exists?(
      RailsErrorDashboard::ErrorLog.table_name, "index_error_logs_on_group_identity"
    )
      skip "no group identity index on this adapter, so the move cannot collide"
    end
    group = seed_group(v1_hash)
    # An open v2 row the lookups don't match (seen over a day ago) but the
    # group-identity index does: same application, environment and window.
    stale = seed_group(v2_hash, occurred_at: 30.hours.ago, first_seen_at: 30.hours.ago, last_seen_at: 30.hours.ago)
    stale.update_columns(group_window: group.group_window)

    result = described_class.call(entries: counted_entries(5))

    expect(result[:success]).to be true
    expect(group.reload.occurrence_count).to eq(8)
    expect(group.error_hash).to eq(v1_hash)
    expect(stale.reload.occurrence_count).to eq(3)
  end

  it "gives a group first seen in a storm the v2 hash" do
    described_class.call(entries: counted_entries(5))

    expect(logs.sole.error_hash).to eq(v2_hash)
    expect(logs.sole.occurrence_count).to eq(5)
  end

  it "keeps v1 on an entry put back after a failed handoff (hardening-1-0-rc2/REQ-5)" do
    group = seed_group(v1_hash)
    buffer = gate.count_buffer
    buffer.restore(counted_entries(5))

    described_class.call(entries: buffer.snapshot![:entries])

    expect(group.reload.occurrence_count).to eq(8)
    expect(group.error_hash).to eq(v2_hash)
  end

  it "buffers no v1 for a custom fingerprint (hardening-1-0-rc2/REQ-7)" do
    RailsErrorDashboard.configuration.custom_fingerprint = ->(exception, _context) { "custom:#{exception.class.name}" }

    entry = counted_entries(1).sole

    expect(entry["custom_hash"]).to eq(generator.call(boom))
    expect(entry["opaque_identity_v1"]).to be_nil
  end

  # The gate keys events on their first kept frame, not on v2 (design.md, the
  # gate amendment of 2026-11-21). The key must never put two v2 groups in
  # one entry.
  def raised_at(line, label)
    error = ArgumentError.new("widget 42 failed")
    error.set_backtrace([
      "#{Rails.root}/app/services/widget_service.rb:#{line}:in '#{label}'",
      "#{Rails.root}/app/controllers/widgets_controller.rb:5:in 'show'"
    ])
    error
  end

  def v2_hash_of(error)
    generator.complete(generator.identities(error, context)[:v2], application.id)
  end

  it "flushes two methods of one file onto their own v2 groups (hardening-1-0-rc2/REQ-5)" do
    explode = raised_at(12, "explode")
    implode = raised_at(20, "implode")
    5.times { gate.admit!(explode, context) }
    3.times { gate.admit!(implode, context) }
    entries = gate.count_buffer.snapshot![:entries]

    described_class.call(entries: entries)

    expect(entries.size).to eq(2)
    expect(logs.find_by!(error_hash: v2_hash_of(explode)).occurrence_count).to eq(5)
    expect(logs.find_by!(error_hash: v2_hash_of(implode)).occurrence_count).to eq(3)
  end

  it "flushes one method raising at two lines onto one v2 group, with the exact total (hardening-1-0-rc2/REQ-5)" do
    first = raised_at(12, "explode")
    second = raised_at(14, "explode")
    5.times { gate.admit!(first, context) }
    3.times { gate.admit!(second, context) }
    entries = gate.count_buffer.snapshot![:entries]

    described_class.call(entries: entries)

    expect(entries.size).to eq(2)
    expect(v2_hash_of(first)).to eq(v2_hash_of(second))
    expect(logs.sole.error_hash).to eq(v2_hash_of(first))
    expect(logs.sole.occurrence_count).to eq(8)
  end

  it "flushes two methods raising through one library frame onto their own v2 groups (hardening-1-0-rc2/REQ-2, hardening-1-0-rc2/REQ-5)" do
    library_frame = "#{RbConfig::CONFIG["rubylibdir"]}/shellwords.rb:120:in 'shellsplit'"
    explode, implode = raised_at(12, "explode"), raised_at(20, "implode")
    [ explode, implode ].each { |error| error.set_backtrace([ library_frame, *error.backtrace ]) }
    5.times { gate.admit!(explode, context) }
    3.times { gate.admit!(implode, context) }
    entries = gate.count_buffer.snapshot![:entries]

    described_class.call(entries: entries)

    expect(entries.size).to eq(2)
    expect(logs.find_by!(error_hash: v2_hash_of(explode)).occurrence_count).to eq(5)
    expect(logs.find_by!(error_hash: v2_hash_of(implode)).occurrence_count).to eq(3)
  end

  it "flushes two misspelled names onto their own v2 groups (hardening-1-0-rc2/REQ-4, hardening-1-0-rc2/REQ-5)" do
    nme, emial = [ :nme, :emial ].map do |name|
      NoMethodError.new("undefined method '#{name}' for nil", name).tap { |error| error.set_backtrace(boom.backtrace) }
    end
    4.times { gate.admit!(nme, context) }
    2.times { gate.admit!(emial, context) }
    entries = gate.count_buffer.snapshot![:entries]

    described_class.call(entries: entries)

    expect(entries.size).to eq(2)
    expect(logs.find_by!(error_hash: v2_hash_of(nme)).occurrence_count).to eq(4)
    expect(logs.find_by!(error_hash: v2_hash_of(emial)).occurrence_count).to eq(2)
  end

  it "computes v2 once per new buffer entry, not per hit" do
    allow(generator).to receive(:v2_identity).and_call_original

    counted_entries(50)

    expect(generator).to have_received(:v2_identity).once
  end

  it "computes v1 once per new buffer entry, not per hit" do
    allow(generator).to receive(:opaque_identity).and_call_original

    counted_entries(50)

    expect(generator).to have_received(:opaque_identity).once
  end
end
