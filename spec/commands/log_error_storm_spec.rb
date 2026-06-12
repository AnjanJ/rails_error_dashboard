# frozen_string_literal: true

require "rails_helper"

RSpec.describe "LogError storm protection integration", type: :job do
  include ActiveJob::TestHelper

  let(:gate) { RailsErrorDashboard::Services::StormProtection::Gate }

  before do
    RailsErrorDashboard.configuration.enable_storm_protection = true
  end

  after { RailsErrorDashboard.reset_configuration! }

  def boom(message = "storm test boom", klass: StandardError)
    error = klass.new(message)
    error.set_backtrace([ "#{Rails.root}/app/models/widget.rb:10:in 'explode'" ])
    error
  end

  describe "gate placement" do
    it "captures normally while the breaker is closed" do
      expect {
        RailsErrorDashboard::Commands::LogError.call(boom, { controller_name: "widgets" })
      }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
    end

    it "ignored exceptions never reach the gate (no storm counting)" do
      RailsErrorDashboard.configuration.ignored_exceptions = [ "ArgumentError" ]
      expect(gate).not_to receive(:admit!)

      result = RailsErrorDashboard::Commands::LogError.call(boom(klass: ArgumentError), {})
      expect(result).to be_nil
    end

    it "does not double-roll the sampling dice (pre-filter flag honored)" do
      RailsErrorDashboard.configuration.sampling_rate = 0.5
      # Filter passes at self.call; inner #call must not re-sample
      allow(RailsErrorDashboard::Services::ExceptionFilter).to receive(:should_log?).once.and_return(true)

      RailsErrorDashboard::Commands::LogError.call(boom, {})
      expect(RailsErrorDashboard::Services::ExceptionFilter).to have_received(:should_log?).once
    end
  end

  describe "count-only mode (breaker open)" do
    before { allow(gate).to receive(:admit!).and_return(:count_only) }

    it "stores nothing synchronously" do
      expect {
        RailsErrorDashboard::Commands::LogError.call(boom, {})
      }.not_to change(RailsErrorDashboard::ErrorLog, :count)
    end

    it "enqueues NO async job — the whole point of gating before the branch" do
      RailsErrorDashboard.configuration.async_logging = true

      expect {
        RailsErrorDashboard::Commands::LogError.call(boom, {})
      }.not_to have_enqueued_job(RailsErrorDashboard::AsyncErrorLoggingJob)
    end
  end

  describe ":lite capture (shedding)" do
    before { allow(gate).to receive(:admit!).and_return(:lite) }

    it "creates the ErrorLog and occurrence row but sheds context payloads" do
      RailsErrorDashboard.configuration.enable_breadcrumbs = true
      RailsErrorDashboard::Services::BreadcrumbCollector.add(:custom, "test crumb")

      expect {
        RailsErrorDashboard::Commands::LogError.call(boom, { controller_name: "widgets" })
      }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
        .and change(RailsErrorDashboard::ErrorOccurrence, :count).by(1)

      error = RailsErrorDashboard::ErrorLog.order(:id).last
      expect(error.breadcrumbs).to be_blank
      expect(error.system_health).to be_blank
    end

    it "skips pre-enqueue context harvest on the async path" do
      RailsErrorDashboard.configuration.async_logging = true
      RailsErrorDashboard.configuration.enable_breadcrumbs = true
      expect(RailsErrorDashboard::Services::BreadcrumbCollector).not_to receive(:harvest)

      RailsErrorDashboard::Commands::LogError.call(boom, {})
    end
  end

  describe "real breaker end-to-end" do
    it "flips to count-only under a flood and stores a bounded number of rows" do
      RailsErrorDashboard.configuration.storm_open_threshold_per_second = 2 # fast-trip at 20

      stored_before = RailsErrorDashboard::ErrorLog.count
      100.times { |i| RailsErrorDashboard::Commands::LogError.call(boom("flood #{i}"), {}) }

      stored = RailsErrorDashboard::ErrorLog.count - stored_before
      expect(stored).to be < 25 # fast-trip kicked in around event 20
      expect(gate.state).to eq(:open)
      expect(gate.count_buffer.any?).to be true
    end

    it "preserves exact counts: stored + counted == fired" do
      RailsErrorDashboard.configuration.storm_open_threshold_per_second = 2

      occurrences_before = RailsErrorDashboard::ErrorOccurrence.count
      100.times { RailsErrorDashboard::Commands::LogError.call(boom("same storm error"), { controller_name: "w" }) }

      stored_occurrences = RailsErrorDashboard::ErrorOccurrence.count - occurrences_before
      stored_increments = RailsErrorDashboard::ErrorLog.where("message LIKE ?", "same storm error%").sum(:occurrence_count)
      snapshot = gate.count_buffer.snapshot!
      counted = snapshot[:entries].sum { |e| e["count"] } + snapshot[:overflow]

      expect(stored_increments + counted).to eq(100)
      expect(stored_occurrences + counted).to eq(100)
    end
  end

  describe "notification suppression" do
    it "suppresses per-error notifications while the breaker is not closed" do
      RailsErrorDashboard.configuration.enable_slack_notifications = true
      RailsErrorDashboard.configuration.slack_webhook_url = "https://hooks.slack.com/test"
      allow(gate).to receive(:notifications_suppressed?).and_return(true)

      expect {
        RailsErrorDashboard::Commands::LogError.call(boom("critical storm", klass: SecurityError), {})
      }.not_to have_enqueued_job(RailsErrorDashboard::SlackErrorNotificationJob)
    end

    it "enqueues one storm notification when a storm begins" do
      RailsErrorDashboard.configuration.storm_open_threshold_per_second = 2

      expect {
        50.times { |i| RailsErrorDashboard::Commands::LogError.call(boom("n#{i}"), {}) }
      }.to have_enqueued_job(RailsErrorDashboard::StormNotificationJob).exactly(:once)
    end
  end

  describe "fail-open safety" do
    it "still captures when the gate itself breaks" do
      allow(gate).to receive(:admit!).and_raise(RuntimeError, "gate exploded")

      expect {
        RailsErrorDashboard::Commands::LogError.call(boom, {})
      }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
    end

    it "never raises out of the capture path" do
      allow(RailsErrorDashboard::Services::ExceptionFilter).to receive(:should_log?).and_raise(RuntimeError)

      expect {
        RailsErrorDashboard::Commands::LogError.call(boom, {})
      }.not_to raise_error
    end
  end

  describe "thread safety smoke" do
    it "handles concurrent captures without raising" do
      RailsErrorDashboard.configuration.storm_open_threshold_per_second = 2

      threads = Array.new(4) do |t|
        Thread.new do
          25.times { |i| RailsErrorDashboard::Commands::LogError.call(boom("t#{t}-#{i}"), {}) }
        end
      end
      expect { threads.each(&:join) }.not_to raise_error
    end
  end
end
