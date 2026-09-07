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

      # The events a baseline is built from: occurrences of this error type on
      # this platform (one row per captured event) when the occurrences table
      # exists, else the group rows themselves. Public so the anomaly check
      # counts the current period in exactly the same units.
      #
      # @param application_id [Integer, nil] restrict to one application's
      #   events (the baselines themselves have no application dimension;
      #   the current-period observation must still be scoped, or one app's
      #   spike shows up as an anomaly on another app's dashboard)
      def self.counting_relation(error_type, platform, application_id: nil)
        conditions = { error_type: error_type, platform: platform }
        conditions[:application_id] = application_id if application_id.present?

        if defined?(ErrorOccurrence) && ErrorOccurrence.table_exists?
          ErrorOccurrence.joins(:error_log).where(ErrorLog.table_name => conditions)
        else
          ErrorLog.where(conditions)
        end
      end

      # The timestamp column of #counting_relation, qualified for the join.
      def self.time_column
        if defined?(ErrorOccurrence) && ErrorOccurrence.table_exists?
          "#{ErrorOccurrence.table_name}.occurred_at"
        else
          "occurred_at"
        end
      end

      # Calculate hourly baseline (last 4 weeks, one sample per calendar hour)
      def calculate_hourly_baseline(error_type, platform)
        calculate_baseline(error_type, platform, "hourly", :hour,
                           HOURLY_LOOKBACK.ago.beginning_of_hour, Time.current.beginning_of_hour)
      end

      # Calculate daily baseline (last 12 weeks, one sample per calendar day)
      def calculate_daily_baseline(error_type, platform)
        calculate_baseline(error_type, platform, "daily", :day,
                           DAILY_LOOKBACK.ago.beginning_of_day, Time.current.beginning_of_day)
      end

      # Calculate weekly baseline (last 1 year, one sample per calendar week)
      def calculate_weekly_baseline(error_type, platform)
        calculate_baseline(error_type, platform, "weekly", :week,
                           WEEKLY_LOOKBACK.ago.beginning_of_week, Time.current.beginning_of_week)
      end

      # One sample per DATED bucket across the whole lookback, zero buckets
      # included, so the statistics describe "how many events in an hour /
      # day / week" — the unit the anomaly check compares against.
      #
      # The previous implementation grouped four weeks by hour-of-day, which
      # summed 28 days into at most 24 totals (seven noon failures on seven
      # days: mean 7, sample size 1), dropped quiet periods, and embedded a
      # SQLite-only date function so it could not run on PostgreSQL or MySQL
      # at all. Groupdate does the bucketing per adapter.
      def calculate_baseline(error_type, platform, baseline_type, period, period_start, period_end)
        return nil if period_end <= period_start

        counts = bucket_counts(error_type, platform, period, period_start, period_end)
        return nil if counts.sum.zero?

        stats = calculate_statistics(counts)

        baseline = Commands::UpsertBaseline.call(
          error_type: error_type, platform: platform, baseline_type: baseline_type,
          period_start: period_start, period_end: period_end,
          stats: stats, count: counts.sum, sample_size: counts.size
        )

        @calculated_count += 1
        baseline
      end

      # @return [Array<Integer>] one count per bucket in [period_start, period_end)
      #
      # Week boundaries and time zone are passed explicitly so the buckets
      # line up with the Rails `beginning_of_week` / `Time.current` calls the
      # period bounds and the anomaly check use. Groupdate's own default week
      # starts on Sunday; Rails' starts on Monday, and with the two disagreeing
      # a Sunday event and a Monday event landed in one bucket instead of two.
      def bucket_counts(error_type, platform, period, period_start, period_end)
        options = { range: period_start...period_end, time_zone: Time.zone }
        options[:week_start] = Date.beginning_of_week if period == :week # groupdate rejects it for other periods

        self.class.counting_relation(error_type, platform)
            .group_by_period(period, self.class.time_column, **options)
            .count
            .values
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

        # Remove outliers (a storm hour must not become the baseline) — but
        # never the whole signal: for a rare error most zero-filled buckets
        # are 0, the few 1s sit many sigmas out, and trimming them would
        # leave a baseline that says the error never happens.
        clean_counts = remove_outliers(counts)
        clean_counts = counts if clean_counts.empty? || (clean_counts.sum.zero? && counts.sum.positive?)

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
