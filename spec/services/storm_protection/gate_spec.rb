# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::StormProtection::Gate do
  let(:gate) { described_class }

  before { RailsErrorDashboard.configuration.enable_storm_protection = true }
  after { RailsErrorDashboard.reset_configuration! }

  def boom(message = "gate boom")
    error = StandardError.new(message)
    error.set_backtrace([ "#{Rails.root}/app/models/widget.rb:10:in 'explode'" ])
    error
  end

  describe ".admit!" do
    it "returns :full when storm protection is disabled" do
      RailsErrorDashboard.configuration.enable_storm_protection = false
      expect(gate.admit!(boom)).to eq(:full)
    end

    it "returns :full in calm weather" do
      expect(gate.admit!(boom)).to eq(:full)
    end

    it "returns :count_only when the breaker is open and records the count" do
      allow(gate.breaker).to receive(:record!).and_return(:open)

      expect(gate.admit!(boom)).to eq(:count_only)
      expect(gate.count_buffer.any?).to be true
    end

    it "caps :shedding decisions at :lite (never :full)" do
      allow(gate.breaker).to receive(:record!).and_return(:shedding)

      expect(gate.admit!(boom)).to eq(:lite)
    end

    it "admits a 1-in-10 probe as :lite in half_open" do
      allow(gate.breaker).to receive(:record!).and_return(:half_open)

      decisions = Array.new(20) { gate.admit!(boom) }
      expect(decisions.count(:lite)).to eq(2)
      expect(decisions.count(:count_only)).to eq(18)
    end

    it "fails OPEN — internal errors yield :full, never raise" do
      allow(gate.breaker).to receive(:record!).and_raise(RuntimeError, "broken")

      expect(gate.admit!(boom)).to eq(:full)
    end

    it "uses the custom fingerprint hash as the gate key when configured" do
      RailsErrorDashboard.configuration.custom_fingerprint = ->(_e, _c) { "stable-key" }
      allow(gate.breaker).to receive(:record!).and_return(:open)

      gate.admit!(boom("message one"))
      gate.admit!(boom("message two")) # different messages, same custom key

      snapshot = gate.count_buffer.snapshot!
      expect(snapshot[:entries].size).to eq(1)
      expect(snapshot[:entries].first["count"]).to eq(2)
    end
  end

  describe ".notifications_suppressed?" do
    it "is false when closed" do
      expect(gate.notifications_suppressed?).to be false
    end

    it "is true while shedding or open" do
      allow(gate.breaker).to receive(:state).and_return(:shedding)
      expect(gate.notifications_suppressed?).to be true
    end

    it "is false when storm protection is disabled" do
      RailsErrorDashboard.configuration.enable_storm_protection = false
      expect(gate.notifications_suppressed?).to be false
    end
  end

  describe ".issue_creation_allowed?" do
    it "allows up to the cap within the window" do
      RailsErrorDashboard.configuration.auto_issue_rate_limit_count = 3

      expect(Array.new(3) { gate.issue_creation_allowed? }).to all(be true)
      expect(gate.issue_creation_allowed?).to be false
    end

    it "always allows when storm protection is disabled" do
      RailsErrorDashboard.configuration.enable_storm_protection = false
      RailsErrorDashboard.configuration.auto_issue_rate_limit_count = 0

      expect(gate.issue_creation_allowed?).to be true
    end
  end

  describe "storm notification" do
    it "enqueues exactly one notification per episode" do
      allow(gate.breaker).to receive(:record!).and_return(:open)
      allow(gate.breaker).to receive(:episode_snapshot).and_return(
        { started_at: Time.current, ended_at: nil, peak_rate_per_minute: 600, reached_open: true }
      )

      expect {
        5.times { gate.admit!(boom) }
      }.to have_enqueued_job(RailsErrorDashboard::StormNotificationJob).exactly(:once)
    end

    it "respects storm_notification = false" do
      RailsErrorDashboard.configuration.storm_notification = false
      allow(gate.breaker).to receive(:record!).and_return(:open)
      allow(gate.breaker).to receive(:episode_snapshot).and_return(
        { started_at: Time.current, ended_at: nil, peak_rate_per_minute: 600, reached_open: true }
      )

      expect {
        gate.admit!(boom)
      }.not_to have_enqueued_job(RailsErrorDashboard::StormNotificationJob)
    end
  end

  describe "flush wiring" do
    it "enqueues a flush snapshot once the interval elapses" do
      RailsErrorDashboard.configuration.storm_flush_interval_seconds = 0
      allow(gate.breaker).to receive(:record!).and_return(:open)
      allow(gate.breaker).to receive(:episode_snapshot).and_return(nil)

      gate.admit!(boom) # records count
      expect {
        gate.admit!(boom) # interval (0s) elapsed → flush
      }.to have_enqueued_job(RailsErrorDashboard::StormFlushJob)
    end

    it "does not flush before the interval" do
      RailsErrorDashboard.configuration.storm_flush_interval_seconds = 3600
      allow(gate.breaker).to receive(:record!).and_return(:open)

      expect {
        5.times { gate.admit!(boom) }
      }.not_to have_enqueued_job(RailsErrorDashboard::StormFlushJob)
    end
  end
end
