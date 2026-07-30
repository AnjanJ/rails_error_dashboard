# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::RackAttackSummary do
  def create_event(rule:, match_type: "throttle", discriminator: "1.2.3.4",
                   path: "/login", http_method: "POST", count: 1,
                   period_hour: 1.day.ago.beginning_of_hour, application_id: nil,
                   last_seen_at: nil)
    RailsErrorDashboard::RackAttackEvent.create!(
      rule: rule,
      match_type: match_type,
      discriminator: discriminator,
      path: path,
      http_method: http_method,
      event_count: count,
      period_hour: period_hour,
      last_seen_at: last_seen_at || period_hour,
      application_id: application_id
    )
  end

  describe ".call" do
    it "returns empty events when no events exist" do
      result = described_class.call(30)
      expect(result[:events]).to eq([])
    end

    it "returns aggregated events for a single rule" do
      create_event(rule: "logins/ip", count: 3)

      events = described_class.call(30)[:events]

      expect(events.size).to eq(1)
      expect(events.first[:rule]).to eq("logins/ip")
      expect(events.first[:match_type]).to eq("throttle")
      expect(events.first[:count]).to eq(3)
    end

    it "groups events by rule name" do
      create_event(rule: "logins/ip", count: 2)
      create_event(rule: "api/ip", count: 5, path: "/api")

      events = described_class.call(30)[:events]

      expect(events.map { |e| e[:rule] }).to contain_exactly("logins/ip", "api/ip")
    end

    it "sums counts across multiple hourly buckets for the same rule" do
      create_event(rule: "logins/ip", count: 4, period_hour: 2.days.ago.beginning_of_hour)
      create_event(rule: "logins/ip", count: 6, period_hour: 1.day.ago.beginning_of_hour)

      events = described_class.call(30)[:events]

      expect(events.size).to eq(1)
      expect(events.first[:count]).to eq(10)
    end

    it "sorts by count descending" do
      create_event(rule: "low", count: 1)
      create_event(rule: "high", count: 99)
      create_event(rule: "mid", count: 20)

      events = described_class.call(30)[:events]

      expect(events.map { |e| e[:rule] }).to eq([ "high", "mid", "low" ])
    end

    it "respects the time range" do
      create_event(rule: "recent", count: 1, period_hour: 2.days.ago.beginning_of_hour)
      create_event(rule: "ancient", count: 1, period_hour: 60.days.ago.beginning_of_hour)

      events = described_class.call(30)[:events]

      expect(events.map { |e| e[:rule] }).to eq([ "recent" ])
    end

    it "filters by application_id" do
      app = RailsErrorDashboard::Application.create!(name: "app-one")
      create_event(rule: "scoped", count: 1, application_id: app.id)
      create_event(rule: "other", count: 1, application_id: nil)

      events = described_class.call(30, application_id: app.id)[:events]

      expect(events.map { |e| e[:rule] }).to eq([ "scoped" ])
    end

    it "counts unique discriminators as unique IPs" do
      create_event(rule: "logins/ip", discriminator: "1.1.1.1", count: 1)
      create_event(rule: "logins/ip", discriminator: "2.2.2.2", count: 1)
      create_event(rule: "logins/ip", discriminator: "1.1.1.1", count: 1,
                   period_hour: 2.days.ago.beginning_of_hour)

      events = described_class.call(30)[:events]

      expect(events.first[:unique_ips]).to eq(2)
    end

    it "reports top_path as the most frequent path, not the first seen" do
      create_event(rule: "api/ip", path: "/rare", count: 1, discriminator: "1.1.1.1")
      create_event(rule: "api/ip", path: "/hot", count: 50, discriminator: "2.2.2.2")

      events = described_class.call(30)[:events]

      expect(events.first[:top_path]).to eq("/hot")
    end

    it "prefers the most severe match type when a rule spans several" do
      create_event(rule: "mixed", match_type: "track", count: 1, discriminator: "1.1.1.1")
      create_event(rule: "mixed", match_type: "blocklist", count: 1, discriminator: "2.2.2.2")

      events = described_class.call(30)[:events]

      expect(events.first[:match_type]).to eq("blocklist")
    end

    it "tracks last_seen as the most recent timestamp" do
      older = 5.days.ago.beginning_of_hour
      newer = 1.day.ago.beginning_of_hour
      create_event(rule: "logins/ip", period_hour: older, last_seen_at: older, discriminator: "1.1.1.1")
      create_event(rule: "logins/ip", period_hour: newer, last_seen_at: newer, discriminator: "2.2.2.2")

      events = described_class.call(30)[:events]

      expect(events.first[:last_seen]).to be_within(1.second).of(newer)
    end

    it "handles a blank discriminator without counting it as an IP" do
      create_event(rule: "anon", discriminator: nil, count: 1)

      events = described_class.call(30)[:events]

      expect(events.first[:unique_ips]).to eq(0)
    end

    it "handles a blank path without raising" do
      create_event(rule: "nopath", path: nil, count: 1)

      events = described_class.call(30)[:events]

      expect(events.first[:top_path]).to be_nil
    end

    it "handles a large number of events without error" do
      60.times do |i|
        create_event(rule: "rule-#{i % 5}", discriminator: "10.0.0.#{i}", count: i + 1)
      end

      events = described_class.call(30)[:events]

      expect(events.size).to eq(5)
      expect(events.sum { |e| e[:count] }).to eq((1..60).sum)
    end

    it "returns an empty array when the query raises" do
      allow(RailsErrorDashboard::RackAttackEvent).to receive(:where).and_raise(StandardError, "boom")

      expect(described_class.call(30)[:events]).to eq([])
    end
  end
end
