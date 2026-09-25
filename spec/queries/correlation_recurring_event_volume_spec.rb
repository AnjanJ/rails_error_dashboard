# frozen_string_literal: true

require "rails_helper"

# The last two readers that selected GROUPS by first-seen and then summed or
# counted them (REQ-F6/F7; design.md F26): the Analytics page's High Frequency
# Errors and the Correlation page's period comparison and platform breakdown.
#
# Every fixture group here is first seen BEFORE its window and has occurrence
# rows INSIDE it -- a chronic error still firing. A first-seen reader cannot
# see it at all; an event reader counts exactly the rows in the window.
RSpec.describe "Correlation and recurring-issue figures count events, not first-seen groups" do
  let(:now) { Time.zone.parse("2026-09-19 12:00:00") }

  around { |example| travel_to(now) { example.run } }

  before do
    RailsErrorDashboard.reset_configuration!
    Rails.cache.clear
  end

  after { RailsErrorDashboard.reset_configuration! }

  # A group born long before the window, with events at the given times.
  def chronic_group(error_type:, born:, event_times:, platform: nil)
    group = create(:error_log,
                   error_type: error_type,
                   platform: platform,
                   occurred_at: born,
                   first_seen_at: born,
                   last_seen_at: event_times.max,
                   occurrence_count: event_times.size + 20)
    event_times.each { |at| create(:error_occurrence, error_log: group, occurred_at: at) }
    group
  end

  describe RailsErrorDashboard::Queries::RecurringIssues do
    let!(:hot) do
      chronic_group(error_type: "NoMethodError", born: Time.zone.parse("2026-08-01 10:00:00"),
                    event_times: Array.new(12) { |i| Time.zone.parse("2026-09-18 10:00:00") + (i * 2).hours })
    end

    let!(:cool) do
      chronic_group(error_type: "TypeError", born: Time.zone.parse("2026-08-01 10:00:00"),
                    event_times: Array.new(5) { |i| Time.zone.parse("2026-09-18 10:00:00") + i.hours })
    end

    def high_frequency
      described_class.call(30)[:high_frequency_errors]
    end

    it "lists a group that fired more than 10 times in the window, however old it is" do
      entry = high_frequency.find { |e| e[:error_type] == "NoMethodError" }
      expect(entry).to be_present
      expect(entry[:total_occurrences]).to eq(12)
    end

    it "keeps the group's real first and last sightings, and calls it active" do
      entry = high_frequency.find { |e| e[:error_type] == "NoMethodError" }
      expect(entry[:first_seen]).to eq(Time.zone.parse("2026-08-01 10:00:00"))
      expect(entry[:last_seen]).to eq(hot.last_seen_at)
      expect(entry[:still_active]).to be(true)
    end

    # The threshold is per group and counts THIS window: 5 events is not high
    # frequency, whatever the group's lifetime count (25 here).
    it "leaves out a group with only a handful of events in the window" do
      expect(high_frequency.map { |e| e[:error_type] }).not_to include("TypeError")
    end
  end

  describe RailsErrorDashboard::Queries::ErrorCorrelation do
    describe "#period_comparison" do
      before do
        chronic_group(error_type: "NoMethodError", born: 40.days.ago,
                      event_times: [ 20.days.ago, 20.days.ago + 1.hour,
                                     5.days.ago, 5.days.ago + 1.hour, 5.days.ago + 2.hours ])
      end

      it "counts each half's events where they happened" do
        result = described_class.new(days: 30).period_comparison
        expect(result[:previous_period][:count]).to eq(2)
        expect(result[:current_period][:count]).to eq(3)
        expect(result[:change]).to eq(1)
        expect(result[:change_percentage]).to eq(50.0)
      end
    end

    describe "#platform_specific_errors" do
      let(:born) { Time.zone.parse("2026-08-01 10:00:00") }
      let(:today) { Time.zone.parse("2026-09-19 09:00:00") }

      before do
        chronic_group(error_type: "NetworkError", platform: "iOS", born: born, event_times: Array.new(3) { |i| today + i.minutes })
        chronic_group(error_type: "NetworkError", platform: "Android", born: born, event_times: Array.new(2) { |i| today + i.minutes })
        chronic_group(error_type: "IOSOnlyError", platform: "iOS", born: born, event_times: Array.new(4) { |i| today + i.minutes })
      end

      it "ranks each platform's error types by their events in the window" do
        ios = described_class.new(days: 30).platform_specific_errors["iOS"]
        expect(ios.map { |e| [ e[:error_type], e[:count] ] }).to eq([ [ "IOSOnlyError", 4 ], [ "NetworkError", 3 ] ])
      end

      it "tells a platform-specific type from one that also fired elsewhere" do
        result = described_class.new(days: 30).platform_specific_errors
        network = result["iOS"].find { |e| e[:error_type] == "NetworkError" }
        ios_only = result["iOS"].find { |e| e[:error_type] == "IOSOnlyError" }

        expect(network).to include(platform_specific: false, also_on: [ "Android" ])
        expect(ios_only).to include(platform_specific: true, also_on: [])
        expect(result["Android"].map { |e| [ e[:error_type], e[:count] ] }).to eq([ [ "NetworkError", 2 ] ])
      end
    end
  end
end
