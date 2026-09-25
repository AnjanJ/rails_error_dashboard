# frozen_string_literal: true

require "rails_helper"

# REQ-F6/F7 said EVERY event-volume figure in the gem counts events by their
# own timestamp. Overview and Analytics were migrated; three readers were not,
# and still selected GROUPS by first-seen and then summed or counted them:
# Platform Comparison (also the Overview's platform health card), User Impact
# and the digest email.
#
# The fixture is the one that exposed the others: groups born in August,
# resolved, then REOPENED in September. Each reopen is an event inside every
# window below, but a group first seen in August is outside all of them -- so a
# first-seen reader reports nothing while the Overview counts the events.
RSpec.describe "Remaining readers count events, not first-seen groups" do
  before do
    RailsErrorDashboard.reset_configuration!
    Rails.cache.clear
  end

  after { RailsErrorDashboard.reset_configuration! }

  let(:now) { Time.zone.parse("2026-09-19 12:00:00") }

  # Captured in August, resolved, recaptured in September. The recapture must
  # REOPEN the August group rather than open a second one inside the window,
  # or the defect hides behind a group that happens to be born in the window.
  def reopen_in_september(message, file:, platform:, user_id:, at:)
    exception = lambda do
      NoMethodError.new(message).tap { |e| e.set_backtrace([ "#{Rails.root}/app/models/#{file}.rb:1:in 'save'" ]) }
    end

    group = nil
    travel_to(Time.zone.parse("2026-08-01 10:00:00")) do
      group = RailsErrorDashboard::Commands::LogError.call(exception.call, user_id: user_id)
      group.update!(resolved: true, status: "resolved", resolved_at: Time.current)
    end

    travel_to(Time.zone.parse(at)) do
      reopened = RailsErrorDashboard::Commands::LogError.call(exception.call, user_id: user_id)
      # Fixture guard: if this stops reopening, every example below would
      # silently stop testing what it claims to.
      expect(reopened.id).to eq(group.id)
    end

    # Platform lives on the GROUP; set it after both captures so neither
    # capture path's own detection decides it.
    group.update_columns(platform: platform)
    group.reload
  end

  let!(:ios_group) do
    reopen_in_september("ios boom", file: "order", platform: "iOS", user_id: 20, at: "2026-09-19 09:00:00")
  end

  let!(:android_group) do
    reopen_in_september("android boom", file: "cart", platform: "Android", user_id: 21, at: "2026-09-19 09:30:00")
  end

  # travel_to inside each example, not an `around` -- nesting it around the
  # fixture's own travel_to raises "confusing time stubbing".
  def at_noon
    travel_to(now) do
      Rails.cache.clear
      yield
    end
  end

  describe RailsErrorDashboard::Queries::PlatformComparison do
    def comparison
      described_class.new(days: 7)
    end

    it "counts each platform's reopened event in its error rate" do
      at_noon do
        expect(comparison.error_rate_by_platform).to eq("iOS" => 1, "Android" => 1)
      end
    end

    it "places the event on the day it happened in the daily trend" do
      at_noon do
        trend = comparison.daily_trend_by_platform
        expect(trend["iOS"][Date.new(2026, 9, 19)]).to eq(1)
        expect(trend["iOS"].values.sum).to eq(1)
      end
    end

    # Severity is an EXHAUSTIVE breakdown of the same events: every event has
    # exactly one severity, so the parts must equal the whole, not merely fit
    # under it.
    it "breaks each platform's events down by severity without losing any" do
      at_noon do
        c = comparison
        rates = c.error_rate_by_platform
        c.severity_distribution_by_platform.each do |platform, severities|
          expect(severities.values.sum).to eq(rates[platform] || 0), "#{platform}: #{severities.inspect}"
        end
        expect(c.severity_distribution_by_platform["iOS"][:high]).to eq(1)
      end
    end

    it "finds the error type that recurred on both platforms" do
      at_noon do
        cross = comparison.cross_platform_errors
        expect(cross.size).to eq(1)
        expect(cross.first).to include(
          error_type: "NoMethodError",
          platforms: [ "Android", "iOS" ],
          total_occurrences: 2,
          platform_breakdown: { "iOS" => 1, "Android" => 1 }
        )
      end
    end

    it "ranks the reopened group among the platform's top errors, by events in the window" do
      at_noon do
        top = comparison.top_errors_by_platform["iOS"]
        expect(top.map { |e| e[:id] }).to eq([ ios_group.id ])
        # Lifetime count is 2 (August + September); one of them is in the window.
        expect(ios_group.occurrence_count).to eq(2)
        expect(top.first[:occurrence_count]).to eq(1)
      end
    end

    it "reports the reopened event in the platform health summary" do
      at_noon do
        health = comparison.platform_health_summary["iOS"]
        expect(health[:total_errors]).to eq(1)
        # Unresolved stays a GROUP figure selected by first-seen (REQ-F7): the
        # August group is not born in this window.
        expect(health[:unresolved_errors]).to eq(0)
      end
    end

    it "agrees with the Analytics page on the total for the same window" do
      at_noon do
        analytics_total = RailsErrorDashboard::Queries::AnalyticsStats.call(7).dig(:error_stats, :total)
        expect(comparison.error_rate_by_platform.values.sum).to eq(analytics_total)
        expect(analytics_total).to eq(2)
      end
    end
  end

  describe RailsErrorDashboard::Queries::UserImpactSummary do
    it "counts the error's events in the window, not the lifetime of groups born in it" do
      at_noon do
        entry = described_class.call(30)[:entries].find { |e| e[:error_type] == "NoMethodError" }
        expect(entry[:unique_users]).to eq(2)
        expect(entry[:total_occurrences]).to eq(2)
      end
    end

    it "links the row to the most recently seen group, with its real last-seen time" do
      at_noon do
        entry = described_class.call(30)[:entries].find { |e| e[:error_type] == "NoMethodError" }
        expect(entry[:id]).to eq(android_group.id)
        expect(entry[:message]).to include("android boom")
        expect(entry[:severity]).to eq(:high)
        expect(entry[:last_seen]).to eq(Time.zone.parse("2026-09-19 09:30:00"))
      end
    end
  end

  describe RailsErrorDashboard::Services::DigestBuilder do
    def digest
      described_class.call(period: :daily)
    end

    it "counts the day's events" do
      at_noon { expect(digest[:stats][:total_occurrences]).to eq(2) }
    end

    it "keeps 'new errors' a group figure: a reopened August group is not new" do
      at_noon { expect(digest[:stats][:new_errors]).to eq(0) }
    end

    it "lists the unresolved error that is firing today among the top errors" do
      at_noon do
        top = digest[:top_errors]
        expect(top.map { |e| e[:error_type] }).to eq([ "NoMethodError" ])
        expect(top.first[:count]).to eq(2)
        expect(top.first[:id]).to eq(android_group.id)
      end
    end

    it "compares the day's events with the previous day's" do
      at_noon do
        expect(digest[:comparison]).to include(current_count: 2, previous_count: 0, error_delta: 2)
      end
    end
  end
end
