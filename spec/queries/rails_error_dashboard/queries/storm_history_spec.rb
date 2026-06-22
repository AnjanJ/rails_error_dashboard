# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::StormHistory do
  after { RailsErrorDashboard.reset_configuration! }

  def storm_event(attrs = {})
    RailsErrorDashboard::StormEvent.create!({ started_at: 1.hour.ago }.merge(attrs))
  end

  describe ".call" do
    it "returns active, recent, and recent-first events" do
      active = storm_event(started_at: 30.minutes.ago, ended_at: nil)
      recent = storm_event(started_at: 5.hours.ago, ended_at: 2.hours.ago)

      result = described_class.call

      expect(result[:active]).to eq(active)
      expect(result[:recent]).to eq(recent)
      expect(result[:events]).to eq([ active, recent ])
    end

    it "respects the limit: param" do
      storm_event(started_at: 1.hour.ago, ended_at: 30.minutes.ago)
      storm_event(started_at: 2.hours.ago, ended_at: 90.minutes.ago)
      storm_event(started_at: 3.hours.ago, ended_at: 2.hours.ago)

      result = described_class.call(limit: 2)

      expect(result[:events].size).to eq(2)
    end

    it "returns safe empty defaults when there are no storms" do
      expect(described_class.call).to eq(active: nil, recent: nil, events: [])
    end

    it "rescues query errors and returns the empty hash" do
      allow(RailsErrorDashboard::StormEvent).to receive(:active).and_raise(StandardError, "boom")

      expect(described_class.call).to eq(active: nil, recent: nil, events: [])
    end
  end

  describe ".banner_event" do
    before { RailsErrorDashboard.configuration.enable_storm_protection = true }

    it "returns the active storm when both an active and a recent-ended storm exist" do
      active = storm_event(started_at: 30.minutes.ago, ended_at: nil)
      storm_event(started_at: 5.hours.ago, ended_at: 2.hours.ago)

      expect(described_class.banner_event).to eq(active)
    end

    it "returns the recent-ended storm when there is no active one (within 24h)" do
      recent = storm_event(started_at: 5.hours.ago, ended_at: 2.hours.ago)

      expect(described_class.banner_event).to eq(recent)
    end

    it "returns nil when the only storm ended more than 24h ago" do
      storm_event(started_at: 30.hours.ago, ended_at: 26.hours.ago)

      expect(described_class.banner_event).to be_nil
    end

    it "returns nil when storm protection is disabled, even with an active storm" do
      storm_event(started_at: 30.minutes.ago, ended_at: nil)
      RailsErrorDashboard.configuration.enable_storm_protection = false

      expect(described_class.banner_event).to be_nil
    end

    it "rescues query errors and returns nil" do
      allow(RailsErrorDashboard::StormEvent).to receive(:active).and_raise(StandardError, "boom")

      expect(described_class.banner_event).to be_nil
    end
  end
end
