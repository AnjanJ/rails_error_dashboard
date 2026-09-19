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
end
