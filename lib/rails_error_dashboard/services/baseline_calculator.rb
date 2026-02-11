# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Calculates baseline statistics for error types
    #
    # This service analyzes historical error data to calculate statistical baselines
    # for different time periods (hourly, daily, weekly). These baselines enable
    # anomaly detection by establishing "normal" error behavior.
    #
    # Statistical methods used:
    # - Mean and Standard Deviation
    # - 95th and 99th Percentiles
    # - Outlier removal (> 3 std devs)
    #
    # @example
    #   BaselineCalculator.calculate_all_baselines
    #   # Calculates baselines for all error types and platforms
    class BaselineCalculator
      # Lookback periods for baseline calculation
      HOURLY_LOOKBACK = 4.weeks
      DAILY_LOOKBACK = 12.weeks
      WEEKLY_LOOKBACK = 1.year

      # Outlier threshold (standard deviations)
      OUTLIER_THRESHOLD = 3

      def self.calculate_all_baselines
        new.calculate_all_baselines
      end

      def self.calculate_for_error_type(error_type, platform)
        new.calculate_for_error_type(error_type, platform)
      end

      def initialize
        @calculated_count = 0
      end

      # Calculate baselines for all error types and platforms
      # @return [Hash] Summary of calculated baselines
      def calculate_all_baselines
        return { calculated: 0, message: "ErrorBaseline table not available" } unless can_calculate?

        # Get all unique combinations of error_type and platform
        combinations = ErrorLog.distinct.pluck(:error_type, :platform).compact

        combinations.each do |(error_type, platform)|
          calculate_for_error_type(error_type, platform)
        end

        { calculated: @calculated_count }
      end

      # Calculate baselines for a specific error type and platform
      # @param error_type [String] The error type
      # @param platform [String] The platform
      # @return [Hash] Summary with hourly, daily, weekly baseline info
      def calculate_for_error_type(error_type, platform)
        return {} unless can_calculate?

        {
          hourly: calculate_hourly_baseline(error_type, platform),
          daily: calculate_daily_baseline(error_type, platform),
          weekly: calculate_weekly_baseline(error_type, platform)
        }
      end

      private

      def can_calculate?
        defined?(ErrorBaseline) && ErrorBaseline.table_exists?
      end

      # Calculate hourly baseline (last 4 weeks, by hour of day)
      def calculate_hourly_baseline(error_type, platform)
        period_start = HOURLY_LOOKBACK.ago.beginning_of_hour
        period_end = Time.current.beginning_of_hour

        # Get error counts grouped by hour
        hourly_counts = ErrorLog
          .where(error_type: error_type, platform: platform)
          .where("occurred_at >= ?", period_start)
          .group("strftime('%H', occurred_at)")
          .count

        return nil if hourly_counts.empty?

        # Calculate statistics
        counts = hourly_counts.values
        stats = calculate_statistics(counts)

        # Create or update baseline
        baseline = ErrorBaseline.find_or_initialize_by(
          error_type: error_type,
          platform: platform,
          baseline_type: "hourly",
          period_start: period_start
        )

        baseline.update!(
          period_end: period_end,
          count: counts.sum,
          mean: stats[:mean],
          std_dev: stats[:std_dev],
          percentile_95: stats[:percentile_95],
          percentile_99: stats[:percentile_99],
          sample_size: counts.size
        )

        @calculated_count += 1
        baseline
      end

      # Calculate daily baseline (last 12 weeks, by day of week)
      def calculate_daily_baseline(error_type, platform)
        period_start = DAILY_LOOKBACK.ago.beginning_of_day
        period_end = Time.current.beginning_of_day

        # Get error counts grouped by day
        daily_counts = ErrorLog
          .where(error_type: error_type, platform: platform)
          .where("occurred_at >= ?", period_start)
          .group("DATE(occurred_at)")
          .count

        return nil if daily_counts.empty?

        # Calculate statistics
        counts = daily_counts.values
        stats = calculate_statistics(counts)

        # Create or update baseline
        baseline = ErrorBaseline.find_or_initialize_by(
          error_type: error_type,
          platform: platform,
          baseline_type: "daily",
          period_start: period_start
        )

        baseline.update!(
          period_end: period_end,
          count: counts.sum,
          mean: stats[:mean],
          std_dev: stats[:std_dev],
          percentile_95: stats[:percentile_95],
          percentile_99: stats[:percentile_99],
          sample_size: counts.size
        )

        @calculated_count += 1
        baseline
      end

      # Calculate weekly baseline (last 1 year, by week)
      def calculate_weekly_baseline(error_type, platform)
        period_start = WEEKLY_LOOKBACK.ago.beginning_of_week
        period_end = Time.current.beginning_of_week

        # Get error counts grouped by week
        weekly_counts = ErrorLog
          .where(error_type: error_type, platform: platform)
          .where("occurred_at >= ?", period_start)
          .group("strftime('%Y-%W', occurred_at)")
          .count

        return nil if weekly_counts.empty?

        # Calculate statistics
        counts = weekly_counts.values
        stats = calculate_statistics(counts)

        # Create or update baseline
        baseline = ErrorBaseline.find_or_initialize_by(
          error_type: error_type,
          platform: platform,
          baseline_type: "weekly",
          period_start: period_start
        )

        baseline.update!(
          period_end: period_end,
          count: counts.sum,
          mean: stats[:mean],
          std_dev: stats[:std_dev],
          percentile_95: stats[:percentile_95],
          percentile_99: stats[:percentile_99],
          sample_size: counts.size
        )

        @calculated_count += 1
        baseline
      end

      # === Pure algorithm methods (no database access) ===
      # These can be called directly as class methods for testability

      # Calculate statistical metrics from an array of counts
      # Removes outliers (> 3 std devs from mean)
      # @param counts [Array<Integer>] Array of error counts
      # @return [Hash] Statistics hash with :mean, :std_dev, :percentile_95, :percentile_99
      def calculate_statistics(counts)
        self.class.calculate_statistics(counts)
      end

      # Class-level pure algorithm: calculate statistics from counts
      def self.calculate_statistics(counts)
        return default_stats if counts.empty?

        # Remove outliers
        clean_counts = remove_outliers(counts)
        return default_stats if clean_counts.empty?

        mean = clean_counts.sum.to_f / clean_counts.size
        variance = clean_counts.map { |c| (c - mean)**2 }.sum / clean_counts.size
        std_dev = Math.sqrt(variance)

        sorted = clean_counts.sort
        percentile_95 = percentile(sorted, 95)
        percentile_99 = percentile(sorted, 99)

        {
          mean: mean.round(2),
          std_dev: std_dev.round(2),
          percentile_95: percentile_95.round(2),
          percentile_99: percentile_99.round(2)
        }
      end

      # Remove outliers from counts (values > 3 std devs from mean)
      # @param counts [Array<Integer>] Raw counts
      # @return [Array<Integer>] Counts with outliers removed
      def self.remove_outliers(counts)
        return counts if counts.size < 3

        mean = counts.sum.to_f / counts.size
        variance = counts.map { |c| (c - mean)**2 }.sum / counts.size
        std_dev = Math.sqrt(variance)

        # Remove values more than OUTLIER_THRESHOLD std devs from mean
        counts.select { |c| (c - mean).abs <= (OUTLIER_THRESHOLD * std_dev) }
      end

      # Calculate percentile value using linear interpolation
      # @param sorted_array [Array] Sorted array of numbers
      # @param pct [Integer] Percentile to calculate (0-100)
      # @return [Float] Percentile value
      def self.percentile(sorted_array, pct)
        return 0 if sorted_array.empty?
        return sorted_array.first if sorted_array.size == 1

        rank = (pct / 100.0) * (sorted_array.size - 1)
        lower_index = rank.floor
        upper_index = rank.ceil

        if lower_index == upper_index
          sorted_array[lower_index].to_f
        else
          # Linear interpolation
          lower_value = sorted_array[lower_index]
          upper_value = sorted_array[upper_index]
          fraction = rank - lower_index
          lower_value + (upper_value - lower_value) * fraction
        end
      end

      # Default statistics for empty datasets
      # @return [Hash] Zero-valued statistics hash
      def self.default_stats
        {
          mean: 0.0,
          std_dev: 0.0,
          percentile_95: 0.0,
          percentile_99: 0.0
        }
      end
    end
  end
end
