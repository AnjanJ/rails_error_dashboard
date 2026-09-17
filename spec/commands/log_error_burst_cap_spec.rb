# frozen_string_literal: true

require "rails_helper"

# One bad deploy can produce hundreds of DISTINCT new errors. Each is a first
# occurrence, so the per-error cooldown never applies and every one notified.
RSpec.describe "LogError first-occurrence burst cap", type: :job do
  include ActiveJob::TestHelper

  let(:config) { RailsErrorDashboard.configuration }
  let(:throttler) { RailsErrorDashboard::Services::NotificationThrottler }
  let(:dispatcher) { RailsErrorDashboard::Services::ErrorNotificationDispatcher }
  let(:summary_job) { RailsErrorDashboard::NotificationBurstSummaryJob }
  let(:dispatched) { [] }

  before do
    config.async_logging = false
    config.notification_burst_limit = 3
    config.notification_burst_window_seconds = 60
    config.enable_slack_notifications = true
    config.slack_webhook_url = "https://hooks.slack.com/services/TEST/BURST/CAP"
    throttler.clear!
    allow(dispatcher).to receive(:call) { |error| dispatched << error.message }
  end

  after do
    throttler.clear!
    RailsErrorDashboard.reset_configuration!
  end

  # A distinct class per error: distinct fingerprints, so each is a first occurrence.
  def new_error(index)
    klass = Class.new(StandardError)
    stub_const("BurstError#{index}", klass)
    error = klass.new("burst #{index}")
    error.set_backtrace([ "#{Rails.root}/app/models/burst_#{index}.rb:#{index + 1}:in 'explode'" ])
    error
  end

  def capture(index)
    RailsErrorDashboard::Commands::LogError.call(new_error(index), {})
  end

  it "notifies for the first N new errors, sends ONE summary, and stores every error" do
    expect { 5.times { |i| capture(i) } }
      .to have_enqueued_job(summary_job).exactly(:once)
      .with(limit: 3, window_seconds: 60, locale: anything)

    expect(dispatched).to eq([ "burst 0", "burst 1", "burst 2" ])
    expect(RailsErrorDashboard::ErrorLog.where("message LIKE 'burst %'").count).to eq(5)
  end

  it "notifies again in the next window" do
    now = 1000.0
    allow(throttler).to receive(:monotonic_now) { now }
    5.times { |i| capture(i) }
    now += 60

    capture(5)

    expect(dispatched.last).to eq("burst 5")
  end

  it "does not stamp the cooldown of an error whose notification was suppressed" do
    5.times { |i| capture(i) }

    suppressed = RailsErrorDashboard::ErrorLog.find_by!(message: "burst 4")
    expect(suppressed.last_notified_at).to be_nil
  end

  it "does not count reopened or threshold notifications against the cap" do
    config.notification_cooldown_minutes = 0
    config.notification_threshold_alerts = [ 2 ]
    first = capture(0) # burst count 1

    3.times { RailsErrorDashboard::Commands::LogError.call(new_error(0), {}) } # threshold at 2
    first.reload.update!(resolved: true, status: "resolved", resolved_at: Time.current)
    RailsErrorDashboard::Commands::LogError.call(new_error(0), {}) # reopened

    capture(1)
    capture(2)

    expect(dispatched.count("burst 1") + dispatched.count("burst 2")).to eq(2)
    expect(summary_job).not_to have_been_enqueued
  end

  it "does nothing at all when no notification channel is enabled" do
    config.enable_slack_notifications = false

    8.times { |i| capture(i) }

    expect(summary_job).not_to have_been_enqueued
    expect(throttler.burst_decision).to eq(:notify) # no slot was consumed
  end

  it "is off when the limit is 0" do
    config.notification_burst_limit = 0

    8.times { |i| capture(i) }

    expect(dispatched.size).to eq(8)
    expect(summary_job).not_to have_been_enqueued
  end

  # Fail-open: the error that would have carried the summary notifies
  # normally instead, and nothing reaches the capture path.
  it "never raises into the capture path when the summary cannot be enqueued" do
    allow(summary_job).to receive(:perform_later).and_raise(RuntimeError, "queue down")

    expect { 5.times { |i| capture(i) } }.not_to raise_error
    expect(RailsErrorDashboard::ErrorLog.where("message LIKE 'burst %'").count).to eq(5)
    expect(dispatched).to eq([ "burst 0", "burst 1", "burst 2", "burst 3" ])
  end
end
