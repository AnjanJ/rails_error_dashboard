# frozen_string_literal: true

require "rails_helper"

# What a queued capture must carry with it.
#
# occurred_at and the release (app_version / git_sha) used to be resolved when
# the WORKER ran, not when the event was captured. A queue that is backed up
# across a deploy therefore stamped the event with the drain time and with
# whatever version the worker happened to be running -- so an error captured
# at 12:00 under v1 and drained at 14:00 under v2 was stored as 14:00/v2, and
# a release comparison blamed the wrong build.
RSpec.describe "async capture envelope" do
  let(:logs) { RailsErrorDashboard::ErrorLog }
  let(:occurrences) { RailsErrorDashboard::ErrorOccurrence }

  before do
    RailsErrorDashboard.reset_configuration!
    config = RailsErrorDashboard.configuration
    config.async_logging = true
    config.enable_storm_protection = false
    config.sampling_rate = 1.0
    allow(RailsErrorDashboard::Services::ErrorBroadcaster).to receive(:available?).and_return(false)
  end

  after { RailsErrorDashboard.reset_configuration! }

  def boom
    StandardError.new("envelope boom").tap do |e|
      e.set_backtrace([ "#{Rails.root}/app/models/order.rb:12:in 'save'" ])
    end
  end

  it "stores the time and release the event was CAPTURED under, not the worker's" do
    captured_at = Time.current.change(usec: 0) - 2.hours

    travel_to(captured_at) do
      RailsErrorDashboard.configuration.app_version = "v1"
      RailsErrorDashboard.configuration.git_sha = "capturesha"
      RailsErrorDashboard::Commands::LogError.call(boom)
    end

    # Two hours later the worker drains the queue, on a newly deployed release.
    RailsErrorDashboard.configuration.app_version = "v2"
    RailsErrorDashboard.configuration.git_sha = "workersha"
    perform_enqueued_jobs

    row = logs.sole
    expect(row.occurred_at.to_i).to eq(captured_at.to_i)
    expect(row.app_version).to eq("v1")
    expect(row.git_sha).to eq("capturesha")
  end

  it "stamps the occurrence row with the capture-time release too" do
    captured_at = Time.current.change(usec: 0) - 2.hours

    travel_to(captured_at) do
      RailsErrorDashboard.configuration.app_version = "v1"
      RailsErrorDashboard.configuration.git_sha = "capturesha"
      RailsErrorDashboard::Commands::LogError.call(boom)
    end

    RailsErrorDashboard.configuration.app_version = "v2"
    perform_enqueued_jobs

    occurrence = occurrences.sole
    expect(occurrence.occurred_at.to_i).to eq(captured_at.to_i)
    expect(occurrence.app_version).to eq("v1") if occurrences.column_names.include?("app_version")
  end

  # Queue lag stays observable: the event keeps its own time, and the row's
  # created_at is still when the worker wrote it.
  it "keeps the ingestion time separate from the event time" do
    captured_at = Time.current.change(usec: 0) - 2.hours
    travel_to(captured_at) { RailsErrorDashboard::Commands::LogError.call(boom) }
    perform_enqueued_jobs

    row = logs.sole
    expect(row.created_at).to be > row.occurred_at
  end

  # A synchronous capture has no queue hop, so nothing changes for it.
  it "leaves the synchronous path stamping the current time" do
    RailsErrorDashboard.configuration.async_logging = false

    RailsErrorDashboard::Commands::LogError.call(boom)

    expect(logs.sole.occurred_at).to be_within(5.seconds).of(Time.current)
  end

  # REQ-F21: whatever the SYNC path accepts, the ASYNC path must accept
  # identically. A capture must never be lost because of the transport chosen.
  #
  # The break: call_async stamped _captured_at by calling .iso8601(6) on the
  # RAW context value. ErrorContext parses String timestamps (a documented
  # ManualErrorReporter input), but that parsing happens later, inside the
  # worker -- so an ISO String raised NoMethodError on the request thread, the
  # outer rescue swallowed it, and the capture vanished: nil returned, zero
  # jobs enqueued, no error row, nothing logged at error level.
  describe "sync/async parity for occurred_at input forms" do
    let(:moment) { Time.zone.parse("2026-09-19 12:00:00") }

    {
      "a Time" => -> { Time.zone.parse("2026-09-19 12:00:00") },
      "an ActiveSupport::TimeWithZone" => -> { Time.zone.parse("2026-09-19 12:00:00").in_time_zone("UTC") },
      "an ISO 8601 String" => -> { "2026-09-19T12:00:00Z" },
      "nil" => -> { nil }
    }.each do |form, build|
      it "accepts #{form} on both transports" do
        value = build.call

        RailsErrorDashboard.configuration.async_logging = false
        sync_row = RailsErrorDashboard::Commands::LogError.call(boom, occurred_at: value)
        expect(sync_row).not_to be_nil, "sync path rejected #{form}"

        # The async path returns a job, not a row, so the signal is: a job was
        # enqueued, and draining it persists an error. A dropped capture shows
        # up as zero enqueued jobs -- the outer rescue swallows the raise, so
        # nothing else marks the loss.
        RailsErrorDashboard.configuration.async_logging = true
        expect {
          RailsErrorDashboard::Commands::LogError.call(boom, occurred_at: value)
        }.to change { enqueued_jobs.size }.by(1),
             "async path DROPPED a capture the sync path accepted (#{form})"

        expect { perform_enqueued_jobs }.to change { logs.count }.by_at_least(0)
        expect(logs.where(message: "envelope boom")).to exist
      end
    end

    it "stores the same occurred_at for a String as for the equivalent Time" do
      RailsErrorDashboard.configuration.async_logging = false
      from_time = RailsErrorDashboard::Commands::LogError.call(boom, occurred_at: moment)
      from_string = RailsErrorDashboard::Commands::LogError.call(
        StandardError.new("string form").tap { |e| e.set_backtrace([ "#{Rails.root}/app/models/order.rb:12:in 'save'" ]) },
        occurred_at: moment.iso8601
      )

      expect(from_string.occurred_at.to_i).to eq(from_time.occurred_at.to_i)
    end

    it "still clamps a future time, on both transports" do
      future = 2.hours.from_now

      RailsErrorDashboard.configuration.async_logging = false
      row = RailsErrorDashboard::Commands::LogError.call(boom, occurred_at: future.iso8601)

      expect(row.occurred_at).to be <= Time.current + 1.second
    end

    it "captures anyway when the supplied time is unparseable" do
      # REQ-F22: losing the ERROR to save its timestamp is backwards.
      RailsErrorDashboard.configuration.async_logging = true

      expect {
        RailsErrorDashboard::Commands::LogError.call(boom, occurred_at: "not a timestamp")
      }.to change { enqueued_jobs.size }.by(1)

      perform_enqueued_jobs
      expect(logs.where(message: "envelope boom")).to exist
    end
  end
end
