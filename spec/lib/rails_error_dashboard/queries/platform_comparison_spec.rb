# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::PlatformComparison do
  describe "#error_rate_by_platform" do
    it "returns error counts grouped by platform" do
      create(:error_log, platform: "ios", occurred_at: 2.days.ago)
      create(:error_log, platform: "ios", occurred_at: 1.day.ago)
      create(:error_log, platform: "android", occurred_at: 1.day.ago)
      create(:error_log, platform: "api", occurred_at: 1.day.ago)
      create(:error_log, platform: "unknown", occurred_at: 10.days.ago) # Outside range

      comparison = described_class.new(days: 7)
      result = comparison.error_rate_by_platform

      expect(result["ios"]).to eq(2)
      expect(result["android"]).to eq(1)
      expect(result["api"]).to eq(1)
      expect(result["unknown"]).to be_nil
    end

    it "returns empty hash when no errors" do
      comparison = described_class.new(days: 7)
      result = comparison.error_rate_by_platform

      expect(result).to eq({})
    end
  end

  describe "#severity_distribution_by_platform" do
    it "returns severity breakdown for each platform" do
      create(:error_log, platform: "ios", error_type: "SecurityError", occurred_at: 1.day.ago)
      create(:error_log, platform: "ios", error_type: "NoMethodError", occurred_at: 1.day.ago)
      create(:error_log, platform: "ios", error_type: "ArgumentError", occurred_at: 1.day.ago)
      create(:error_log, platform: "android", error_type: "Timeout::Error", occurred_at: 1.day.ago)

      comparison = described_class.new(days: 7)
      result = comparison.severity_distribution_by_platform

      expect(result["ios"][:critical]).to eq(1)
      expect(result["ios"][:high]).to eq(2)
      expect(result["android"][:medium]).to eq(1)
    end
  end

  describe "#resolution_time_by_platform" do
    it "calculates average resolution time in hours" do
      freeze_time do
        # iOS error resolved in 2 hours
        create(:error_log,
          platform: "ios",
          occurred_at: 3.hours.ago,
          resolved_at: 1.hour.ago)

        # Another iOS error resolved in 4 hours
        create(:error_log,
          platform: "ios",
          occurred_at: 5.hours.ago,
          resolved_at: 1.hour.ago)

        # Android error resolved in 6 hours
        create(:error_log,
          platform: "android",
          occurred_at: 7.hours.ago,
          resolved_at: 1.hour.ago)

        comparison = described_class.new(days: 7)
        result = comparison.resolution_time_by_platform

        expect(result["ios"]).to eq(3.0) # Average of 2 and 4
        expect(result["android"]).to eq(6.0)
      end
    end

    it "returns nil for platforms with no resolved errors" do
      create(:error_log, platform: "ios", occurred_at: 1.day.ago, resolved_at: nil)

      comparison = described_class.new(days: 7)
      result = comparison.resolution_time_by_platform

      expect(result["ios"]).to be_nil
    end
  end

  describe "#top_errors_by_platform" do
    it "returns top 10 errors per platform sorted by occurrence count" do
      # Create 15 errors for iOS with different occurrence counts
      15.times do |i|
        create(:error_log,
          platform: "ios",
          error_type: "Error#{i}",
          occurrence_count: i + 1,
          occurred_at: 1.day.ago)
      end

      comparison = described_class.new(days: 7)
      result = comparison.top_errors_by_platform

      expect(result["ios"].count).to eq(10)
      expect(result["ios"].first[:occurrence_count]).to eq(15)
      expect(result["ios"].last[:occurrence_count]).to eq(6)
    end

    it "includes error details" do
      create(:error_log,
        platform: "android",
        error_type: "NoMethodError",
        message: "Test error message",
        occurrence_count: 5,
        occurred_at: 1.day.ago)

      comparison = described_class.new(days: 7)
      result = comparison.top_errors_by_platform

      error = result["android"].first
      expect(error[:error_type]).to eq("NoMethodError")
      expect(error[:message]).to include("Test error")
      expect(error[:severity]).to eq(:high)
      expect(error[:occurrence_count]).to eq(5)
    end
  end

  describe "#platform_stability_scores" do
    it "calculates stability scores (0-100)" do
      # iOS: 10 errors, resolved in 2 hours (should be high stability)
      freeze_time do
        10.times do
          create(:error_log,
            platform: "ios",
            occurred_at: 3.hours.ago,
            resolved_at: 1.hour.ago)
        end

        # Android: 50 errors, resolved in 10 hours (should be lower stability)
        50.times do
          create(:error_log,
            platform: "android",
            occurred_at: 11.hours.ago,
            resolved_at: 1.hour.ago)
        end

        comparison = described_class.new(days: 7)
        result = comparison.platform_stability_scores

        expect(result["ios"]).to be > result["android"]
        expect(result["ios"]).to be_between(0, 100)
        expect(result["android"]).to be_between(0, 100)
      end
    end

    it "handles platforms with no errors" do
      comparison = described_class.new(days: 7)
      result = comparison.platform_stability_scores

      expect(result).to eq({})
    end

    # audit-fixes-0-16-0/REQ-4: the error term was 1 - count/max, so the
    # busiest platform scored 0 on it and a lone platform was always Critical.
    it "does not rate a lone platform" do
      3.times { create(:error_log, platform: "ios", occurred_at: 1.day.ago) }

      expect(described_class.new(days: 7).platform_stability_scores).to eq({})
    end

    # The platform list is every platform ever seen; the minimum counts the
    # ones with errors in the window, or an old Android error lets this week's
    # iOS-only errors be rated Critical on volume alone.
    it "does not rate a platform that is the only one with errors in the window" do
      3.times { create(:error_log, platform: "ios", occurred_at: 1.day.ago) }
      create(:error_log, platform: "android", occurred_at: 60.days.ago)

      expect(described_class.new(days: 7).platform_stability_scores).to eq({})
    end

    # The platform list was every platform ever seen, so one with no errors in
    # the window scored 100 and got a Healthy card.
    it "audit-fixes-0-16-1/REQ-8 scores no platform without errors in the window" do
      2.times { create(:error_log, platform: "iOS", occurred_at: 1.day.ago) }
      2.times { create(:error_log, platform: "Android", occurred_at: 1.day.ago) }
      create(:error_log, platform: "Web", occurred_at: 60.days.ago)

      comparison = described_class.new(days: 7)

      expect(comparison.platform_stability_scores.keys).to contain_exactly("iOS", "Android")
      expect(comparison.platform_health_summary.keys).to contain_exactly("iOS", "Android")
    end

    it "gives two equally busy platforms equal, non-zero scores" do
      3.times { create(:error_log, platform: "ios", occurred_at: 1.day.ago) }
      3.times { create(:error_log, platform: "android", occurred_at: 1.day.ago) }

      scores = described_class.new(days: 7).platform_stability_scores

      expect(scores["ios"]).to eq(scores["android"])
      expect(scores["ios"]).to be > 0

      # Equal volume, no resolutions, no growth: neither is Critical on volume alone
      statuses = described_class.new(days: 7).platform_health_summary.transform_values { _1[:health_status] }
      expect(statuses.values).to all(satisfy { |status| status != :critical })
    end
  end

  # audit-fixes-0-16-1: each platform is scored against an even split of the
  # window's errors. Every error happens in the first half of the window, so
  # velocity stays at or below 10 and the score alone decides Healthy.
  describe "#platform_stability_scores against an even split" do
    around { |example| freeze_time { example.run } }

    # Resolved resolved_after after it happened, or never when nil. By default
    # at once, so every platform resolves as fast as the fastest and gets full
    # resolution credit: the volume term alone sets the score.
    def errors_on(platform, count, resolved_after: 0.seconds)
      count.times do
        occurred_at = 5.days.ago
        create(:error_log, platform: platform, occurred_at: occurred_at,
                           resolved_at: resolved_after && occurred_at + resolved_after)
      end
    end

    def comparison
      described_class.new(days: 7)
    end

    [ %w[iOS Android], %w[iOS Android Web] ].each do |platforms|
      it "audit-fixes-0-16-1/REQ-1 rates equal platforms Healthy with equal scores (#{platforms.size} platforms)" do
        platforms.each { |platform| errors_on(platform, 4) }

        summary = comparison.platform_health_summary

        expect(summary.transform_values { _1[:stability_score] }).to eq(platforms.index_with { 100.0 })
        expect(summary.transform_values { _1[:health_status] }).to eq(platforms.index_with { :healthy })
      end
    end

    # Full resolution credit everywhere, so 100 is full volume credit
    it "audit-fixes-0-16-1/REQ-2 gives full volume credit at or below an even split" do
      errors_on("iOS", 5)
      errors_on("Android", 3)
      errors_on("Web", 2)

      scores = comparison.platform_stability_scores

      expect(scores).to include("Android" => 100.0, "Web" => 100.0)
      expect(scores["iOS"]).to eq(82.5)
    end

    {
      "60/40" => [ { "iOS" => 6, "Android" => 4 }, { "iOS" => 86.0, "Android" => 100.0 } ],
      "90/10" => [ { "iOS" => 9, "Android" => 1 }, { "iOS" => 44.0, "Android" => 100.0 } ],
      "80/10/10" => [ { "iOS" => 8, "Android" => 1, "Web" => 1 }, { "iOS" => 51.0, "Android" => 100.0, "Web" => 100.0 } ]
    }.each do |split, (counts, expected)|
      it "audit-fixes-0-16-1/REQ-3 gives a larger share less credit (#{split})" do
        counts.each { |platform, count| errors_on(platform, count) }

        expect(comparison.platform_stability_scores).to eq(expected)
      end
    end

    it "audit-fixes-0-16-1/REQ-3 rates the busier side of a 60/40 split Healthy" do
      errors_on("iOS", 6)
      errors_on("Android", 4)

      expect(comparison.platform_health_summary["iOS"][:health_status]).to eq(:healthy)
    end
  end

  describe "#cross_platform_errors" do
    it "finds errors occurring on multiple platforms" do
      # Same error type on iOS and Android
      create(:error_log,
        error_type: "NetworkError",
        platform: "ios",
        occurrence_count: 10,
        occurred_at: 1.day.ago)

      create(:error_log,
        error_type: "NetworkError",
        platform: "android",
        occurrence_count: 15,
        occurred_at: 1.day.ago)

      # Platform-specific error (should not appear)
      create(:error_log,
        error_type: "IOSSpecific",
        platform: "ios",
        occurrence_count: 5,
        occurred_at: 1.day.ago)

      comparison = described_class.new(days: 7)
      result = comparison.cross_platform_errors

      expect(result.count).to eq(1)
      expect(result.first[:error_type]).to eq("NetworkError")
      expect(result.first[:platforms]).to match_array([ "ios", "android" ])
      expect(result.first[:total_occurrences]).to eq(25)
      expect(result.first[:platform_breakdown]["ios"]).to eq(10)
      expect(result.first[:platform_breakdown]["android"]).to eq(15)
    end

    it "sorts by total occurrences" do
      # Error A on 2 platforms with 50 total occurrences
      create(:error_log, error_type: "ErrorA", platform: "ios", occurrence_count: 30, occurred_at: 1.day.ago)
      create(:error_log, error_type: "ErrorA", platform: "android", occurrence_count: 20, occurred_at: 1.day.ago)

      # Error B on 2 platforms with 10 total occurrences
      create(:error_log, error_type: "ErrorB", platform: "ios", occurrence_count: 5, occurred_at: 1.day.ago)
      create(:error_log, error_type: "ErrorB", platform: "api", occurrence_count: 5, occurred_at: 1.day.ago)

      comparison = described_class.new(days: 7)
      result = comparison.cross_platform_errors

      expect(result.first[:error_type]).to eq("ErrorA")
      expect(result.last[:error_type]).to eq("ErrorB")
    end

    it "returns empty array when no cross-platform errors" do
      create(:error_log, error_type: "IOSOnly", platform: "ios", occurred_at: 1.day.ago)
      create(:error_log, error_type: "AndroidOnly", platform: "android", occurred_at: 1.day.ago)

      comparison = described_class.new(days: 7)
      result = comparison.cross_platform_errors

      expect(result).to eq([])
    end
  end

  describe "#daily_trend_by_platform" do
    it "returns daily error counts for each platform" do
      freeze_time do
        # iOS errors on different days
        create(:error_log, platform: "ios", occurred_at: 5.days.ago)
        create(:error_log, platform: "ios", occurred_at: 5.days.ago)
        create(:error_log, platform: "ios", occurred_at: 3.days.ago)

        # Android errors
        create(:error_log, platform: "android", occurred_at: 5.days.ago)

        comparison = described_class.new(days: 7)
        result = comparison.daily_trend_by_platform

        ios_trend = result["ios"]
        expect(ios_trend[5.days.ago.to_date]).to eq(2)
        expect(ios_trend[3.days.ago.to_date]).to eq(1)

        android_trend = result["android"]
        expect(android_trend[5.days.ago.to_date]).to eq(1)
      end
    end
  end

  describe "#platform_health_summary" do
    it "provides comprehensive health metrics per platform" do
      freeze_time do
        # Create iOS errors: 10 total, 2 critical, 3 unresolved, 7 resolved
        2.times do
          create(:error_log,
            platform: "ios",
            error_type: "SecurityError",
            occurred_at: 2.days.ago,
            resolved_at: nil)
        end

        1.times do
          create(:error_log,
            platform: "ios",
            error_type: "NoMethodError",
            occurred_at: 2.days.ago,
            resolved_at: nil)
        end

        7.times do
          create(:error_log,
            platform: "ios",
            error_type: "Timeout::Error",
            occurred_at: 2.days.ago,
            resolved_at: 1.day.ago)
        end

        comparison = described_class.new(days: 7)
        result = comparison.platform_health_summary

        ios_health = result["ios"]
        expect(ios_health[:total_errors]).to eq(10)
        expect(ios_health[:critical_errors]).to eq(2)
        expect(ios_health[:unresolved_errors]).to eq(3)
        expect(ios_health[:resolution_rate]).to eq(70.0)
        expect(ios_health[:error_velocity]).to be_present
        # audit-fixes-0-16-0/REQ-4: a rating compares platforms, so a lone
        # platform is not rated. It was always Critical before.
        expect(ios_health[:stability_score]).to be_nil
        expect(ios_health[:health_status]).to eq(:not_rated)
      end
    end

    it "calculates error velocity (increasing/decreasing)" do
      freeze_time do
        # First half: 10 errors
        10.times do
          create(:error_log, platform: "ios", occurred_at: 6.days.ago)
        end

        # Second half: 20 errors (100% increase)
        20.times do
          create(:error_log, platform: "ios", occurred_at: 2.days.ago)
        end

        comparison = described_class.new(days: 7)
        result = comparison.platform_health_summary

        expect(result["ios"][:error_velocity]).to eq(100.0)
      end
    end

    it "determines health status correctly" do
      # High stability (80+) + low velocity (<=10%) = healthy
      comparison = described_class.new(days: 7)
      status = comparison.send(:determine_health_status, 85, 5)
      expect(status).to eq(:healthy)

      # Medium stability (60-79) + medium velocity (11-50%) = warning
      status = comparison.send(:determine_health_status, 70, 30)
      expect(status).to eq(:warning)

      # Low stability (<60) or high velocity (>50%) = critical
      status = comparison.send(:determine_health_status, 50, 60)
      expect(status).to eq(:critical)
    end
  end

  describe "custom time periods" do
    it "respects custom days parameter" do
      create(:error_log, platform: "ios", occurred_at: 5.days.ago)
      create(:error_log, platform: "ios", occurred_at: 10.days.ago)

      # 7-day window should include first error
      comparison_7 = described_class.new(days: 7)
      expect(comparison_7.error_rate_by_platform["ios"]).to eq(1)

      # 14-day window should include both errors
      comparison_14 = described_class.new(days: 14)
      expect(comparison_14.error_rate_by_platform["ios"]).to eq(2)
    end
  end
end
