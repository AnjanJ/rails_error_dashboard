# frozen_string_literal: true

require "rails_helper"

# Groups created before the v2 recipe keep their occurrences.
# See .shipkit/specs/hardening-1-0-rc2 (REQ-5, REQ-6, and the decision "Rows
# grouped under v1 keep their occurrences").
#
# Every group a host has at upgrade time carries a v1 hash. A capture now
# carries both identities: it matches a v1-only group, counts on it and moves
# it to v2, on the sync path and through the queue. A job queued by rc.1
# carries v1 alone and lands where it was headed.
RSpec.describe "capture identity v2 and the v1 fallback" do
  let(:generator) { RailsErrorDashboard::Services::ErrorHashGenerator }
  let(:logs) { RailsErrorDashboard::ErrorLog }
  let(:application) do
    RailsErrorDashboard::Application.find_or_create_by_name(RailsErrorDashboard.resolved_application_name)
  end
  let(:identities) { generator.identities(boom) }
  let(:v2_hash) { generator.complete(identities[:v2], application.id) }
  let(:v1_hash) { generator.complete(identities[:v1], application.id) }

  before do
    RailsErrorDashboard.reset_configuration!
    config = RailsErrorDashboard.configuration
    config.sampling_rate = 1.0
    config.enable_storm_protection = false
    RailsErrorDashboard::Services::StormProtection::Gate.reset!
    allow(RailsErrorDashboard::Services::ErrorBroadcaster).to receive(:available?).and_return(false)
  end

  after do
    RailsErrorDashboard.reset_configuration!
    RailsErrorDashboard::Services::StormProtection::Gate.reset!
  end

  def boom
    error = ArgumentError.new("widget 42 failed")
    error.set_backtrace([
      "#{Rails.root}/app/services/widget_service.rb:12:in 'explode'",
      "#{Rails.root}/app/controllers/widgets_controller.rb:5:in 'show'"
    ])
    error
  end

  open_group = { resolved: false, status: "new" }
  statuses = {
    "open" => open_group,
    "resolved" => { resolved: true, status: "resolved", resolved_at: 2.hours.ago },
    "wont_fix" => { resolved: false, status: "wont_fix" }
  }

  def seed_group(error_hash, status_attributes)
    logs.create!(
      application_id: application.id,
      error_type: "ArgumentError",
      message: "widget 42 failed",
      backtrace: boom.backtrace.join("\n"),
      error_hash: error_hash,
      occurred_at: 1.hour.ago,
      first_seen_at: 1.hour.ago,
      last_seen_at: 1.hour.ago,
      occurrence_count: 3,
      **status_attributes
    )
  end

  def capture_sync
    RailsErrorDashboard.configuration.async_logging = false
    RailsErrorDashboard::Commands::LogError.call(boom)
  end

  def capture_async
    RailsErrorDashboard.configuration.async_logging = true
    RailsErrorDashboard::Commands::LogError.call(boom)
    perform_enqueued_jobs(only: RailsErrorDashboard::AsyncErrorLoggingJob)
  end

  it "seeds a group whose v1 hash differs from its v2 hash" do
    expect(v1_hash).to match(/\A[0-9a-f]{16}\z/)
    expect(v2_hash).to match(/\A[0-9a-f]{16}\z/)
    expect(v1_hash).not_to eq(v2_hash)
  end

  statuses.each do |label, status_attributes|
    [ :sync, :async ].each do |path|
      it "counts a #{path} capture on a v1-only #{label} group and moves it to v2 (hardening-1-0-rc2/REQ-5)" do
        group = seed_group(v1_hash, status_attributes)

        expect { send(:"capture_#{path}") }.not_to change(logs, :count)

        group.reload
        expect(group.occurrence_count).to eq(4)
        expect(group.error_hash).to eq(v2_hash)
      end
    end
  end

  it "carries v2, v1 and the version on the queue" do
    RailsErrorDashboard.configuration.async_logging = true
    RailsErrorDashboard::Commands::LogError.call(boom)

    job = enqueued_jobs.find { |queued| queued[:job] == RailsErrorDashboard::AsyncErrorLoggingJob }
    context = ActiveJob::Arguments.deserialize(job[:args])[1]

    expect(context[:_identity]).to eq(identities[:v2])
    expect(context[:_identity_v1]).to eq(identities[:v1])
    expect(context[:_identity_version]).to eq(2)
  end

  # rc.1 queued one identity, v1, as _identity, and no version.
  it "counts a job queued by rc.1 on its v1 group and leaves the hash as v1 (hardening-1-0-rc2/REQ-6)" do
    group = seed_group(v1_hash, open_group)
    RailsErrorDashboard.configuration.async_logging = true
    RailsErrorDashboard::Commands::LogError.call(boom)
    job = enqueued_jobs.find { |queued| queued[:job] == RailsErrorDashboard::AsyncErrorLoggingJob }
    args = ActiveJob::Arguments.deserialize(job[:args])
    args[1].delete(:_identity_v1)
    args[1].delete(:_identity_version)
    args[1][:_identity] = identities[:v1]
    clear_enqueued_jobs

    expect { RailsErrorDashboard::AsyncErrorLoggingJob.perform_now(*args) }.not_to change(logs, :count)

    group.reload
    expect(group.occurrence_count).to eq(4)
    expect(group.error_hash).to eq(v1_hash)
  end

  it "prefers a v2 group to a more recently seen v1 group (hardening-1-0-rc2/REQ-5)" do
    v1_group = seed_group(v1_hash, open_group.merge(last_seen_at: 1.minute.ago))
    v2_group = seed_group(v2_hash, open_group)

    capture_sync

    expect(v2_group.reload.occurrence_count).to eq(4)
    expect(v1_group.reload.occurrence_count).to eq(3)
    expect(v1_group.error_hash).to eq(v1_hash)
  end

  it "gives a new group the v2 hash" do
    capture_sync

    expect(logs.sole.error_hash).to eq(v2_hash)
  end

  describe "custom_fingerprint (hardening-1-0-rc2/REQ-7)" do
    it "stores rc.1's value on sync and async, with no v1 on the queue" do
      RailsErrorDashboard.configuration.custom_fingerprint = ->(exception, _context) { "custom:#{exception.class.name}" }
      custom_hash = generator.call(boom)

      capture_sync
      RailsErrorDashboard.configuration.async_logging = true
      RailsErrorDashboard::Commands::LogError.call(boom)
      job = enqueued_jobs.find { |queued| queued[:job] == RailsErrorDashboard::AsyncErrorLoggingJob }
      expect(ActiveJob::Arguments.deserialize(job[:args])[1]).not_to have_key(:_identity_v1)
      perform_enqueued_jobs(only: RailsErrorDashboard::AsyncErrorLoggingJob)

      expect(logs.sole.error_hash).to eq(custom_hash)
      expect(logs.sole.occurrence_count).to eq(2)
    end
  end
end
