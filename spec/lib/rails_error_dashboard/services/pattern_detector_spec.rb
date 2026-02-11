# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::PatternDetector do
  describe ".analyze_cyclical_pattern" do
    it "returns empty pattern when no timestamps" do
      result = described_class.analyze_cyclical_pattern(timestamps: [], days: 30)

      expect(result[:pattern_type]).to eq(:none)
      expect(result[:peak_hours]).to eq([])
      expect(result[:total_errors]).to eq(0)
      expect(result[:pattern_strength]).to eq(0.0)
    end

    it "detects business hours pattern (9am-5pm)" do
      freeze_time do
        timestamps = []
        # Create timestamps during business hours (9am-5pm)
        30.times do
          hour = [ 9, 10, 11, 14, 15, 16 ].sample
          timestamps << Time.current.change(hour: hour)
        end
        # Create few timestamps outside business hours
        5.times do
          hour = [ 0, 1, 2, 22, 23 ].sample
          timestamps << Time.current.change(hour: hour)
        end

        result = described_class.analyze_cyclical_pattern(timestamps: timestamps, days: 30)

        expect(result[:pattern_type]).to eq(:business_hours)
        expect(result[:peak_hours]).to be_present
        expect(result[:pattern_strength]).to be > 0.3
        expect(result[:total_errors]).to eq(35)
      end
    end

    it "detects night pattern (midnight-6am)" do
      freeze_time do
        timestamps = []
        # Create timestamps during night hours
        25.times do
          hour = [ 0, 1, 2, 3, 4, 5 ].sample
          timestamps << Time.current.change(hour: hour)
        end
        # Create few timestamps during day
        5.times do
          hour = [ 12, 13, 14 ].sample
          timestamps << Time.current.change(hour: hour)
        end

        result = described_class.analyze_cyclical_pattern(timestamps: timestamps, days: 30)

        expect(result[:pattern_type]).to eq(:night)
        expect(result[:peak_hours] & (0..6).to_a).to be_present
        expect(result[:total_errors]).to eq(30)
      end
    end

    it "detects weekend pattern" do
      freeze_time do
        timestamps = []
        # Create timestamps on weekends (Saturday=6, Sunday=0)
        20.times do
          days_offset = rand(0..29)
          time = days_offset.days.ago
          # Find next Saturday or Sunday
          until time.wday.in?([ 0, 6 ])
            time += 1.day
          end
          timestamps << time
        end
        # Create few timestamps on weekdays
        5.times do
          days_offset = rand(0..29)
          time = days_offset.days.ago
          until time.wday.in?([ 1, 2, 3, 4, 5 ])
            time += 1.day
          end
          timestamps << time
        end

        result = described_class.analyze_cyclical_pattern(timestamps: timestamps, days: 30)

        expect(result[:pattern_type]).to eq(:weekend)
        expect(result[:total_errors]).to eq(25)
        weekend_count = (result[:weekday_distribution][0] || 0) + (result[:weekday_distribution][6] || 0)
        total_count = result[:weekday_distribution].values.sum
        expect(weekend_count.to_f / total_count).to be > 0.5
      end
    end

    it "detects uniform pattern when errors are evenly distributed" do
      # Travel to a Wednesday to avoid weekend pattern detection
      travel_to(Time.zone.local(2025, 1, 8, 12, 0, 0)) do
        timestamps = (0..23).map { |hour| Time.current.change(hour: hour) }

        result = described_class.analyze_cyclical_pattern(timestamps: timestamps, days: 30)

        expect(result[:pattern_type]).to eq(:uniform)
        expect(result[:pattern_strength]).to be < 0.3
        expect(result[:total_errors]).to eq(24)
      end
    end

    it "calculates pattern strength correctly" do
      freeze_time do
        # Strong pattern: all errors at hour 10
        strong_timestamps = Array.new(10) { Time.current.change(hour: 10) }

        strong_result = described_class.analyze_cyclical_pattern(
          timestamps: strong_timestamps, days: 30
        )

        # Weak pattern: errors evenly distributed
        weak_timestamps = (0..23).map { |hour| Time.current.change(hour: hour) }

        weak_result = described_class.analyze_cyclical_pattern(
          timestamps: weak_timestamps, days: 30
        )

        expect(strong_result[:pattern_strength]).to be > weak_result[:pattern_strength]
      end
    end

    it "includes hourly distribution" do
      freeze_time do
        timestamps = []
        5.times { timestamps << Time.current.change(hour: 10) }
        3.times { timestamps << Time.current.change(hour: 15) }

        result = described_class.analyze_cyclical_pattern(timestamps: timestamps, days: 30)

        expect(result[:hourly_distribution][10]).to eq(5)
        expect(result[:hourly_distribution][15]).to eq(3)
        expect(result[:hourly_distribution][0] || 0).to eq(0)
      end
    end

    it "includes weekday distribution" do
      freeze_time do
        # Find a Monday within the last 30 days
        monday = Time.current
        monday -= 1.day until monday.wday == 1

        # Find a Friday within the last 30 days
        friday = Time.current
        friday -= 1.day until friday.wday == 5

        timestamps = [ monday, monday + 1.hour, friday ]

        result = described_class.analyze_cyclical_pattern(timestamps: timestamps, days: 30)

        expect(result[:weekday_distribution][1]).to eq(2) # Monday
        expect(result[:weekday_distribution][5]).to eq(1) # Friday
      end
    end
  end

  describe ".detect_bursts" do
    it "returns empty array when no timestamps" do
      result = described_class.detect_bursts(timestamps: [])
      expect(result).to eq([])
    end

    it "returns empty array with fewer than 5 timestamps" do
      timestamps = 3.times.map { |i| i.seconds.ago }
      result = described_class.detect_bursts(timestamps: timestamps)
      expect(result).to eq([])
    end

    it "detects a burst when errors occur rapidly" do
      freeze_time do
        base_time = 2.days.ago
        timestamps = 10.times.map { |i| base_time + i.seconds }

        result = described_class.detect_bursts(timestamps: timestamps)

        expect(result.count).to eq(1)
        burst = result.first
        expect(burst[:error_count]).to eq(10)
        expect(burst[:duration_seconds]).to be < 60
        expect(burst[:burst_intensity]).to eq(:medium)
      end
    end

    it "detects multiple bursts" do
      freeze_time do
        # First burst: 6 timestamps
        burst1 = 6.times.map { |i| 3.days.ago + i.seconds }
        # Second burst: 8 timestamps (after a 2-hour gap)
        burst2 = 8.times.map { |i| 3.days.ago + 2.hours + i.seconds }

        result = described_class.detect_bursts(timestamps: burst1 + burst2)

        expect(result.count).to eq(2)
        expect(result.map { |b| b[:error_count] }).to match_array([ 6, 8 ])
      end
    end

    it "does not detect burst when errors are too far apart" do
      freeze_time do
        timestamps = 10.times.map { |i| 2.days.ago + (i * 2).minutes }

        result = described_class.detect_bursts(timestamps: timestamps)

        expect(result).to eq([])
      end
    end

    it "classifies burst intensity correctly" do
      freeze_time do
        base_time = 2.days.ago

        high_timestamps = 25.times.map { |i| base_time + i.seconds }
        medium_timestamps = 15.times.map { |i| base_time + i.seconds }
        low_timestamps = 7.times.map { |i| base_time + i.seconds }

        high_result = described_class.detect_bursts(timestamps: high_timestamps)
        medium_result = described_class.detect_bursts(timestamps: medium_timestamps)
        low_result = described_class.detect_bursts(timestamps: low_timestamps)

        expect(high_result.first[:burst_intensity]).to eq(:high)
        expect(medium_result.first[:burst_intensity]).to eq(:medium)
        expect(low_result.first[:burst_intensity]).to eq(:low)
      end
    end

    it "includes start_time, end_time, and duration" do
      freeze_time do
        base_time = 2.days.ago
        timestamps = 10.times.map { |i| base_time + (i * 5).seconds }

        result = described_class.detect_bursts(timestamps: timestamps)

        expect(result.count).to eq(1)
        burst = result.first
        expect(burst[:start_time]).to eq(base_time)
        expect(burst[:end_time]).to eq(base_time + 45.seconds)
        expect(burst[:duration_seconds]).to eq(45.0)
      end
    end

    it "requires at least 5 timestamps in a burst" do
      freeze_time do
        timestamps = 4.times.map { |i| 2.days.ago + i.seconds }

        result = described_class.detect_bursts(timestamps: timestamps)

        expect(result).to eq([])
      end
    end
  end

  describe ".determine_pattern_type" do
    it "returns :none for empty distribution" do
      expect(described_class.determine_pattern_type({}, {})).to eq(:none)
    end

    it "returns :business_hours when peaks in 9-17 range" do
      hourly = Hash.new(1)
      [ 9, 10, 11, 14, 15, 16 ].each { |h| hourly[h] = 20 }
      expect(described_class.determine_pattern_type(hourly, {})).to eq(:business_hours)
    end

    it "returns :night when peaks in 0-6 range" do
      hourly = Hash.new(1)
      [ 0, 1, 2, 3, 4 ].each { |h| hourly[h] = 20 }
      expect(described_class.determine_pattern_type(hourly, {})).to eq(:night)
    end

    it "returns :weekend when >50% on Sat/Sun" do
      hourly = { 12 => 10 }
      weekday = { 0 => 30, 6 => 30, 1 => 5, 2 => 5, 3 => 5, 4 => 5, 5 => 5 }
      expect(described_class.determine_pattern_type(hourly, weekday)).to eq(:weekend)
    end
  end

  describe ".calculate_pattern_strength" do
    it "returns 0.0 for empty distribution" do
      expect(described_class.calculate_pattern_strength({})).to eq(0.0)
    end

    it "returns higher strength for concentrated distribution" do
      concentrated = { 10 => 100 }
      spread = (0..23).each_with_object({}) { |h, d| d[h] = 4 }

      expect(described_class.calculate_pattern_strength(concentrated)).to be > described_class.calculate_pattern_strength(spread)
    end
  end

  describe ".classify_burst_intensity" do
    it "returns :high for 20+ errors" do
      expect(described_class.classify_burst_intensity(25)).to eq(:high)
    end

    it "returns :medium for 10-19 errors" do
      expect(described_class.classify_burst_intensity(15)).to eq(:medium)
    end

    it "returns :low for 5-9 errors" do
      expect(described_class.classify_burst_intensity(7)).to eq(:low)
    end
  end
end
