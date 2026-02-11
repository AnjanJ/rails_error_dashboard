# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm service for detecting occurrence patterns in errors
    #
    # All methods accept data as input and return analysis results — no database access.
    # Callers (Queries, Models) are responsible for fetching data and passing it in.
    #
    # Provides two main pattern detection capabilities:
    # 1. Cyclical patterns - Daily/weekly rhythms (e.g., business hours pattern)
    # 2. Burst detection - Many errors in short time period
    #
    # @example Cyclical pattern
    #   timestamps = ErrorLog.where(...).pluck(:occurred_at)
    #   pattern = PatternDetector.analyze_cyclical_pattern(
    #     timestamps: timestamps,
    #     days: 30
    #   )
    #
    # @example Burst detection
    #   timestamps = ErrorLog.where(...).pluck(:occurred_at)
    #   bursts = PatternDetector.detect_bursts(timestamps: timestamps)
    class PatternDetector
      # Analyze cyclical patterns from an array of timestamps
      #
      # Detects:
      # - Business hours pattern (9am-5pm peak)
      # - Night pattern (midnight-6am peak)
      # - Weekend pattern (Sat-Sun peak)
      # - Uniform pattern (no clear pattern)
      #
      # @param timestamps [Array<Time>] Array of error occurrence timestamps
      # @param days [Integer] Number of days being analyzed (for metadata)
      # @return [Hash] Pattern analysis with type, peaks, distribution, and strength
      def self.analyze_cyclical_pattern(timestamps:, days: 30, **_opts)
        return empty_pattern if timestamps.empty?

        # Group by hour of day (0-23)
        hourly_distribution = Hash.new(0)
        weekday_distribution = Hash.new(0)

        timestamps.each do |timestamp|
          hour = timestamp.hour
          wday = timestamp.wday # 0 = Sunday, 6 = Saturday
          hourly_distribution[hour] += 1
          weekday_distribution[wday] += 1
        end

        # Calculate pattern type and peaks
        pattern_type = determine_pattern_type(hourly_distribution, weekday_distribution)
        peak_hours = find_peak_hours(hourly_distribution)
        pattern_strength = calculate_pattern_strength(hourly_distribution)

        {
          pattern_type: pattern_type,
          peak_hours: peak_hours,
          hourly_distribution: hourly_distribution,
          weekday_distribution: weekday_distribution,
          pattern_strength: pattern_strength,
          total_errors: timestamps.size,
          analysis_days: days
        }
      end

      # Detect error bursts from an array of timestamps
      #
      # A burst is defined as a sequence where inter-arrival time < 1 minute
      # Burst intensity:
      # - :high - 20+ errors in burst
      # - :medium - 10-19 errors
      # - :low - 5-9 errors
      #
      # @param timestamps [Array<Time>] Sorted array of error occurrence timestamps
      # @return [Array<Hash>] Array of burst metadata
      def self.detect_bursts(timestamps:, **_opts)
        sorted_timestamps = timestamps.sort
        return [] if sorted_timestamps.size < 5

        # Detect bursts: sequences where inter-arrival < 60 seconds
        bursts = []
        current_burst = nil

        sorted_timestamps.each_with_index do |timestamp, i|
          next if i.zero?

          inter_arrival = timestamp - sorted_timestamps[i - 1]

          if inter_arrival <= 60 # 60 seconds threshold
            # Start new burst or continue existing
            if current_burst.nil?
              current_burst = {
                start_time: sorted_timestamps[i - 1],
                timestamps: [ sorted_timestamps[i - 1], timestamp ]
              }
            else
              current_burst[:timestamps] << timestamp
            end
          else
            # End current burst if it exists and has enough errors
            if current_burst && current_burst[:timestamps].size >= 5
              bursts << finalize_burst(current_burst)
            end
            current_burst = nil
          end
        end

        # Don't forget the last burst
        if current_burst && current_burst[:timestamps].size >= 5
          bursts << finalize_burst(current_burst)
        end

        bursts
      end

      # Determine the pattern type based on hour and weekday distributions
      # @param hourly_dist [Hash] Hour (0-23) => count
      # @param weekday_dist [Hash] Weekday (0-6) => count
      # @return [Symbol] Pattern type (:business_hours, :night, :weekend, :uniform, :none)
      def self.determine_pattern_type(hourly_dist, weekday_dist)
        return :none if hourly_dist.empty?

        # Calculate average errors per hour
        avg_per_hour = hourly_dist.values.sum.to_f / 24

        # Find peak hours (>2x average)
        peak_hours = hourly_dist.select { |_, count| count > avg_per_hour * 2 }.keys.sort

        # Business hours pattern: peaks between 9am-5pm
        business_hours = (9..17).to_a
        business_peaks = peak_hours & business_hours
        if business_peaks.size >= 3
          return :business_hours
        end

        # Night pattern: peaks between midnight-6am
        night_hours = (0..6).to_a
        night_peaks = peak_hours & night_hours
        if night_peaks.size >= 2
          return :night
        end

        # Weekend pattern: most errors on Sat/Sun
        if weekday_dist.any?
          weekend_count = (weekday_dist[0] || 0) + (weekday_dist[6] || 0) # Sun + Sat
          total_count = weekday_dist.values.sum
          if weekend_count > total_count * 0.5
            return :weekend
          end
        end

        # No clear pattern
        :uniform
      end

      # Find peak hours (hours with >2x average)
      # @param hourly_dist [Hash] Hour (0-23) => count
      # @return [Array<Integer>] Sorted peak hour numbers
      def self.find_peak_hours(hourly_dist)
        return [] if hourly_dist.empty?

        avg = hourly_dist.values.sum.to_f / 24
        hourly_dist.select { |_, count| count > avg * 2 }.keys.sort
      end

      # Calculate pattern strength (0.0-1.0)
      # Measures how concentrated the errors are in peak hours
      # @param hourly_dist [Hash] Hour (0-23) => count
      # @return [Float] Pattern strength from 0.0 (uniform) to 1.0 (concentrated)
      def self.calculate_pattern_strength(hourly_dist)
        return 0.0 if hourly_dist.empty?

        total = hourly_dist.values.sum
        return 0.0 if total.zero?

        # Calculate coefficient of variation (std dev / mean)
        # Higher variation = stronger pattern
        values = (0..23).map { |h| hourly_dist[h] || 0 }
        mean = total.to_f / 24
        variance = values.sum { |v| (v - mean)**2 } / 24
        std_dev = Math.sqrt(variance)

        # Normalize to 0-1 scale (coefficient of variation)
        cv = mean > 0 ? std_dev / mean : 0
        [ cv.round(2), 1.0 ].min
      end

      # Classify burst intensity based on error count
      # @param count [Integer] Number of errors in burst
      # @return [Symbol] Intensity (:high, :medium, :low)
      def self.classify_burst_intensity(count)
        if count >= 20
          :high
        elsif count >= 10
          :medium
        else
          :low
        end
      end

      # Finalize burst metadata from raw tracking data
      # @param burst_data [Hash] Raw burst data with :start_time and :timestamps
      # @return [Hash] Finalized burst with start_time, end_time, duration, count, intensity
      def self.finalize_burst(burst_data)
        start_time = burst_data[:start_time]
        end_time = burst_data[:timestamps].last
        duration = end_time - start_time
        count = burst_data[:timestamps].size

        {
          start_time: start_time,
          end_time: end_time,
          duration_seconds: duration.round(1),
          error_count: count,
          burst_intensity: classify_burst_intensity(count)
        }
      end

      # Empty pattern result
      # @return [Hash] Default empty pattern hash
      def self.empty_pattern
        {
          pattern_type: :none,
          peak_hours: [],
          hourly_distribution: {},
          weekday_distribution: {},
          pattern_strength: 0.0,
          total_errors: 0,
          analysis_days: 0
        }
      end
    end
  end
end
