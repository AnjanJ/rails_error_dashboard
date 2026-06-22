# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::StormEvent do
  describe "#active?" do
    it "is true when ended_at is nil" do
      event = described_class.create!(started_at: 1.hour.ago, ended_at: nil)
      expect(event).to be_active
    end

    it "is false when ended_at is set" do
      event = described_class.create!(started_at: 2.hours.ago, ended_at: 1.hour.ago)
      expect(event).not_to be_active
    end
  end

  describe "#duration_seconds" do
    it "is nil while the storm is active (no ended_at)" do
      event = described_class.create!(started_at: 1.hour.ago, ended_at: nil)
      expect(event.duration_seconds).to be_nil
    end

    it "returns the rounded seconds between started_at and ended_at" do
      event = described_class.create!(started_at: 2.hours.ago, ended_at: 1.hour.ago)
      expect(event.duration_seconds).to be_within(1).of(3600)
    end
  end

  describe "#top_fingerprints_list" do
    it "returns [] when top_fingerprints is nil" do
      event = described_class.create!(started_at: 1.hour.ago, top_fingerprints: nil)
      expect(event.top_fingerprints_list).to eq([])
    end

    it "returns [] when top_fingerprints is blank" do
      event = described_class.create!(started_at: 1.hour.ago, top_fingerprints: "")
      expect(event.top_fingerprints_list).to eq([])
    end

    it "parses a valid JSON array into an array of hashes" do
      payload = [
        { "class" => "Boom", "message" => "kaboom", "count" => 12 },
        { "class" => "Bang", "message" => "kapow", "count" => 7 }
      ]
      event = described_class.create!(started_at: 1.hour.ago, top_fingerprints: payload.to_json)

      expect(event.top_fingerprints_list).to eq(payload)
    end

    it "returns [] on corrupt JSON" do
      event = described_class.create!(started_at: 1.hour.ago, top_fingerprints: "{not json")
      expect(event.top_fingerprints_list).to eq([])
    end

    it "returns [] when the JSON parses to a non-array value" do
      event = described_class.create!(started_at: 1.hour.ago, top_fingerprints: "{}")
      expect(event.top_fingerprints_list).to eq([])
    end
  end

  describe "scopes" do
    describe ".active" do
      it "returns only rows with a nil ended_at" do
        open_storm = described_class.create!(started_at: 1.hour.ago, ended_at: nil)
        described_class.create!(started_at: 3.hours.ago, ended_at: 2.hours.ago)

        expect(described_class.active.to_a).to eq([ open_storm ])
      end

      it "returns an empty relation when every storm has ended" do
        described_class.create!(started_at: 3.hours.ago, ended_at: 2.hours.ago)

        expect(described_class.active).to be_empty
      end
    end

    describe ".recent_first" do
      it "orders by started_at descending" do
        oldest = described_class.create!(started_at: 3.hours.ago, ended_at: 2.hours.ago)
        middle = described_class.create!(started_at: 2.hours.ago, ended_at: 1.hour.ago)
        newest = described_class.create!(started_at: 1.hour.ago, ended_at: nil)

        expect(described_class.recent_first.to_a).to eq([ newest, middle, oldest ])
      end
    end

    describe ".ended_within" do
      it "returns rows that ended within the window and excludes older ones" do
        within = described_class.create!(started_at: 5.hours.ago, ended_at: 2.hours.ago)
        described_class.create!(started_at: 30.hours.ago, ended_at: 26.hours.ago)

        expect(described_class.ended_within(24.hours).to_a).to eq([ within ])
      end

      it "excludes active (not-yet-ended) storms" do
        described_class.create!(started_at: 1.hour.ago, ended_at: nil)

        expect(described_class.ended_within(24.hours)).to be_empty
      end

      it "returns an empty relation when nothing ended in the window" do
        described_class.create!(started_at: 30.hours.ago, ended_at: 26.hours.ago)

        expect(described_class.ended_within(24.hours)).to be_empty
      end
    end
  end
end
