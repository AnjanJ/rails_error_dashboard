# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::PatternDetector do
  describe ".analyze_cyclical_pattern" do
    it "returns empty pattern when no errors exist" do
      result = described_class.analyze_cyclical_pattern(
        error_type: "NoMethodError",
        platform: "ios",
        days: 30
      )

      expect(result[:pattern_type]).to eq(:none)
      expect(result[:peak_hours]).to eq([])
      expect(result[:total_errors]).to eq(0)
      expect(result[:pattern_strength]).to eq(0.0)
    end

    it "detects business hours pattern (9am-5pm)" do
      freeze_time do
        # Create errors during business hours (9am-5pm)
        30.times do
          hour = [ 9, 10, 11, 14, 15, 16 ].sample
          create(:error_log,
            error_type: "BusinessError",
            platform: "ios",
            occurred_at: Time.current.change(hour: hour))
        end

        # Create few errors outside business hours
        5.times do
          hour = [ 0, 1, 2, 22, 23 ].sample
          create(:error_log,
            error_type: "BusinessError",
            platform: "ios",
            occurred_at: Time.current.change(hour: hour))
        end

        result = described_class.analyze_cyclical_pattern(
          error_type: "BusinessError",
          platform: "ios",
          days: 30
        )

        expect(result[:pattern_type]).to eq(:business_hours)
        expect(result[:peak_hours]).to be_present
        expect(result[:pattern_strength]).to be > 0.3
        expect(result[:total_errors]).to eq(35)
      end
    end

    it "detects night pattern (midnight-6am)" do
      freeze_time do
        # Create errors during night hours
        25.times do
          hour = [ 0, 1, 2, 3, 4, 5 ].sample
          create(:error_log,
            error_type: "NightError",
            platform: "api",
            occurred_at: Time.current.change(hour: hour))
        end

        # Create few errors during day
        5.times do
          hour = [ 12, 13, 14 ].sample
          create(:error_log,
            error_type: "NightError",
            platform: "api",
            occurred_at: Time.current.change(hour: hour))
        end

        result = described_class.analyze_cyclical_pattern(
          error_type: "NightError",
          platform: "api",
          days: 30
        )

        expect(result[:pattern_type]).to eq(:night)
        expect(result[:peak_hours] & (0..6).to_a).to be_present
        expect(result[:total_errors]).to eq(30)
      end
    end

    it "detects weekend pattern" do
      freeze_time do
        # Create errors on weekends (Saturday=6, Sunday=0)
        20.times do
          days_offset = rand(0..29)
          time = days_offset.days.ago
          # Find next Saturday or Sunday
          until time.wday.in?([ 0, 6 ])
            time += 1.day
          end

          create(:error_log,
            error_type: "WeekendError",
            platform: "ios",
            occurred_at: time)
        end

        # Create few errors on weekdays
        5.times do
          days_offset = rand(0..29)
          time = days_offset.days.ago
          # Find next weekday
          until time.wday.in?([ 1, 2, 3, 4, 5 ])
            time += 1.day
          end

          create(:error_log,
            error_type: "WeekendError",
            platform: "ios",
            occurred_at: time)
        end

        result = described_class.analyze_cyclical_pattern(
          error_type: "WeekendError",
          platform: "ios",
          days: 30
        )

        expect(result[:pattern_type]).to eq(:weekend)
        expect(result[:total_errors]).to eq(25)
        weekend_count = (result[:weekday_distribution][0] || 0) + (result[:weekday_distribution][6] || 0)
        total_count = result[:weekday_distribution].values.sum
        expect(weekend_count.to_f / total_count).to be > 0.5
      end
    end

    it "detects uniform pattern when errors are evenly distributed" do
      # Travel to a Wednesday (middle of the week) to avoid weekend pattern detection
      travel_to(Time.zone.local(2025, 1, 8, 12, 0, 0)) do  # Wednesday, January 8, 2025
        # Create errors evenly across all hours
        24.times do |hour|
          create(:error_log,
            error_type: "UniformError",
            platform: "api",
            occurred_at: Time.current.change(hour: hour))
        end

        result = described_class.analyze_cyclical_pattern(
          error_type: "UniformError",
          platform: "api",
          days: 30
        )

        expect(result[:pattern_type]).to eq(:uniform)
        expect(result[:pattern_strength]).to be < 0.3
        expect(result[:total_errors]).to eq(24)
      end
    end

    it "calculates pattern strength correctly" do
      freeze_time do
        # Strong pattern: all errors at hour 10
        10.times do
          create(:error_log,
            error_type: "StrongPattern",
            platform: "ios",
            occurred_at: Time.current.change(hour: 10))
        end

        strong_result = described_class.analyze_cyclical_pattern(
          error_type: "StrongPattern",
          platform: "ios",
          days: 30
        )

        # Weak pattern: errors evenly distributed
        24.times do |hour|
          create(:error_log,
            error_type: "WeakPattern",
            platform: "ios",
            occurred_at: Time.current.change(hour: hour))
        end

        weak_result = described_class.analyze_cyclical_pattern(
          error_type: "WeakPattern",
          platform: "ios",
          days: 30
        )

        expect(strong_result[:pattern_strength]).to be > weak_result[:pattern_strength]
      end
    end

    it "includes hourly distribution" do
      freeze_time do
        5.times { create(:error_log, error_type: "Test", platform: "ios", occurred_at: Time.current.change(hour: 10)) }
        3.times { create(:error_log, error_type: "Test", platform: "ios", occurred_at: Time.current.change(hour: 15)) }

        result = described_class.analyze_cyclical_pattern(
          error_type: "Test",
          platform: "ios",
          days: 30
        )

        expect(result[:hourly_distribution][10]).to eq(5)
        expect(result[:hourly_distribution][15]).to eq(3)
        expect(result[:hourly_distribution][0] || 0).to eq(0)
      end
    end

    it "respects days parameter" do
      # Create error 10 days ago
      create(:error_log,
        error_type: "OldError",
        platform: "ios",
        occurred_at: 10.days.ago)

      # Analyze last 7 days (should not include 10-day-old error)
      result_7 = described_class.analyze_cyclical_pattern(
        error_type: "OldError",
        platform: "ios",
        days: 7
      )

      # Analyze last 14 days (should include it)
      result_14 = described_class.analyze_cyclical_pattern(
        error_type: "OldError",
        platform: "ios",
        days: 14
      )

      expect(result_7[:total_errors]).to eq(0)
      expect(result_14[:total_errors]).to eq(1)
    end

    it "includes weekday distribution" do
      freeze_time do
        # Find a Monday within the last 30 days
        monday = Time.current
        until monday.wday == 1
          monday -= 1.day
        end

        # Find a Friday within the last 30 days
        friday = Time.current
        until friday.wday == 5
          friday -= 1.day
        end

        # Create errors on Monday
        create(:error_log, error_type: "Test", platform: "ios", occurred_at: monday)
        create(:error_log, error_type: "Test", platform: "ios", occurred_at: monday + 1.hour)
        # Create error on Friday
        create(:error_log, error_type: "Test", platform: "ios", occurred_at: friday)

        result = described_class.analyze_cyclical_pattern(
          error_type: "Test",
          platform: "ios",
          days: 30
        )

        expect(result[:weekday_distribution][1]).to eq(2) # Monday
        expect(result[:weekday_distribution][5]).to eq(1) # Friday
      end
    end
  end

  describe ".detect_bursts" do
    it "returns empty array when no errors exist" do
      result = described_class.detect_bursts(
        error_type: "NoMethodError",
        platform: "ios",
        days: 7
      )

      expect(result).to eq([])
    end

    it "returns empty array with fewer than 5 errors" do
      3.times do
        create(:error_log, error_type: "FewErrors", platform: "ios")
      end

      result = described_class.detect_bursts(
        error_type: "FewErrors",
        platform: "ios",
        days: 7
      )

      expect(result).to eq([])
    end

    it "detects a burst when errors occur rapidly" do
      freeze_time do
        base_time = 2.days.ago

        # Create a burst: 10 errors within 5 minutes
        10.times do |i|
          create(:error_log,
            error_type: "BurstError",
            platform: "ios",
            occurred_at: base_time + i.seconds,
            occurrence_count: 1)
        end

        result = described_class.detect_bursts(
          error_type: "BurstError",
          platform: "ios",
          days: 7
        )

        expect(result.count).to eq(1)
        burst = result.first
        expect(burst[:error_count]).to eq(10)
        expect(burst[:duration_seconds]).to be < 60
        expect(burst[:burst_intensity]).to eq(:medium)
      end
    end

    it "detects multiple bursts" do
      freeze_time do
        # First burst: 6 errors
        6.times do |i|
          create(:error_log,
            error_type: "MultiBurst",
            platform: "ios",
            occurred_at: 3.days.ago + i.seconds,
            occurrence_count: 1)
        end

        # Gap of 2 hours
        # Second burst: 8 errors
        8.times do |i|
          create(:error_log,
            error_type: "MultiBurst",
            platform: "ios",
            occurred_at: 3.days.ago + 2.hours + i.seconds,
            occurrence_count: 1)
        end

        result = described_class.detect_bursts(
          error_type: "MultiBurst",
          platform: "ios",
          days: 7
        )

        expect(result.count).to eq(2)
        expect(result.map { |b| b[:error_count] }).to match_array([ 6, 8 ])
      end
    end

    it "does not detect burst when errors are too far apart" do
      freeze_time do
        # Create 10 errors but spaced 2 minutes apart (beyond 60s threshold)
        10.times do |i|
          create(:error_log,
            error_type: "SpacedError",
            platform: "ios",
            occurred_at: 2.days.ago + (i * 2).minutes,
            occurrence_count: 1)
        end

        result = described_class.detect_bursts(
          error_type: "SpacedError",
          platform: "ios",
          days: 7
        )

        expect(result).to eq([])
      end
    end

    it "classifies burst intensity correctly" do
      freeze_time do
        base_time = 2.days.ago

        # High intensity: 25 errors
        25.times do |i|
          create(:error_log,
            error_type: "HighBurst",
            platform: "ios",
            occurred_at: base_time + i.seconds,
            occurrence_count: 1)
        end

        # Medium intensity: 15 errors
        15.times do |i|
          create(:error_log,
            error_type: "MediumBurst",
            platform: "ios",
            occurred_at: base_time + i.seconds,
            occurrence_count: 1)
        end

        # Low intensity: 7 errors
        7.times do |i|
          create(:error_log,
            error_type: "LowBurst",
            platform: "ios",
            occurred_at: base_time + i.seconds,
            occurrence_count: 1)
        end

        high_result = described_class.detect_bursts(error_type: "HighBurst", platform: "ios", days: 7)
        medium_result = described_class.detect_bursts(error_type: "MediumBurst", platform: "ios", days: 7)
        low_result = described_class.detect_bursts(error_type: "LowBurst", platform: "ios", days: 7)

        expect(high_result.first[:burst_intensity]).to eq(:high)
        expect(medium_result.first[:burst_intensity]).to eq(:medium)
        expect(low_result.first[:burst_intensity]).to eq(:low)
      end
    end

    it "includes start_time, end_time, and duration" do
      freeze_time do
        base_time = 2.days.ago

        # Create burst
        10.times do |i|
          create(:error_log,
            error_type: "TimedBurst",
            platform: "ios",
            occurred_at: base_time + (i * 5).seconds, # 5 seconds apart
            occurrence_count: 1)
        end

        result = described_class.detect_bursts(
          error_type: "TimedBurst",
          platform: "ios",
          days: 7
        )

        expect(result.count).to eq(1)
        burst = result.first
        expect(burst[:start_time]).to eq(base_time)
        expect(burst[:end_time]).to eq(base_time + 45.seconds)
        expect(burst[:duration_seconds]).to eq(45.0)
      end
    end

    it "respects days parameter" do
      # Create burst 10 days ago
      10.times do |i|
        create(:error_log,
          error_type: "OldBurst",
          platform: "ios",
          occurred_at: 10.days.ago + i.seconds,
          occurrence_count: 1)
      end

      # Analyze last 7 days (should not find burst)
      result_7 = described_class.detect_bursts(
        error_type: "OldBurst",
        platform: "ios",
        days: 7
      )

      # Analyze last 14 days (should find burst)
      result_14 = described_class.detect_bursts(
        error_type: "OldBurst",
        platform: "ios",
        days: 14
      )

      expect(result_7).to eq([])
      expect(result_14.count).to eq(1)
    end

    it "requires at least 5 errors in a burst" do
      freeze_time do
        base_time = 2.days.ago

        # Create sequence of only 4 errors within threshold
        4.times do |i|
          create(:error_log,
            error_type: "SmallBurst",
            platform: "ios",
            occurred_at: base_time + i.seconds,
            occurrence_count: 1)
        end

        result = described_class.detect_bursts(
          error_type: "SmallBurst",
          platform: "ios",
          days: 7
        )

        expect(result).to eq([])
      end
    end
  end
end
