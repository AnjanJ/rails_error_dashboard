# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Calculate and retrieve baseline statistics for error types
    #
    # Provides methods to get hourly, daily, and weekly baselines for error types.
    # Baselines help establish "normal" error behavior for anomaly detection.
    #
    # @example
    #   baseline = BaselineStats.hourly_baseline("NoMethodError", "iOS")
    #   # => { mean: 5.2, std_dev: 2.1, percentile_95: 9.0, ... }
    class BaselineStats
      def self.hourly_baseline(error_type, platform)
        new(error_type, platform).hourly_baseline
      end

      def self.daily_baseline(error_type, platform)
        new(error_type, platform).daily_baseline
      end

      def self.weekly_baseline(error_type, platform)
        new(error_type, platform).weekly_baseline
      end

      def initialize(error_type, platform)
        @error_type = error_type
        @platform = platform
      end

      # Get the most recent hourly baseline
      # Covers last 4 weeks of data, aggregated by hour of day
      # @return [ErrorBaseline, nil] Most recent hourly baseline or nil
      def hourly_baseline
        return nil unless defined?(ErrorBaseline) && ErrorBaseline.table_exists?

        ErrorBaseline
          .for_error_type(@error_type)
          .for_platform(@platform)
          .hourly
          .recent
          .first
      end

      # Get the most recent daily baseline
      # Covers last 12 weeks of data, aggregated by day of week
      # @return [ErrorBaseline, nil] Most recent daily baseline or nil
      def daily_baseline
        return nil unless defined?(ErrorBaseline) && ErrorBaseline.table_exists?

        ErrorBaseline
          .for_error_type(@error_type)
          .for_platform(@platform)
          .daily
          .recent
          .first
      end

      # Get the most recent weekly baseline
      # Covers last 1 year of data, aggregated by week
      # @return [ErrorBaseline, nil] Most recent weekly baseline or nil
      def weekly_baseline
        return nil unless defined?(ErrorBaseline) && ErrorBaseline.table_exists?

        ErrorBaseline
          .for_error_type(@error_type)
          .for_platform(@platform)
          .weekly
          .recent
          .first
      end

      # Get all baselines for an error type and platform
      # @return [Hash] Hash with :hourly, :daily, :weekly keys
      def all_baselines
        {
          hourly: hourly_baseline,
          daily: daily_baseline,
          weekly: weekly_baseline
        }
      end

      # Check if current count is anomalous based on best available baseline
      # Uses hourly baseline if available, falls back to daily, then weekly
      # @param current_count [Integer] Current error count
      # @param sensitivity [Integer] Standard deviations threshold (default: 2)
      # @return [Hash] { anomaly: true/false, level: Symbol, baseline_type: String }
      # Compare a count against the first available baseline, in matching
      # units: the current HOUR's count against the hourly baseline, TODAY's
      # against the daily, THIS WEEK's against the weekly. A bare positional
      # count is compared against whichever baseline is found (legacy callers).
      #
      # @param current_count [Integer, nil] legacy: one count used for any baseline
      # @param hourly [Integer, nil] events so far this hour
      # @param daily [Integer, nil] events so far today
      # @param weekly [Integer, nil] events so far this week
      def check_anomaly(current_count = nil, sensitivity: 2, hourly: nil, daily: nil, weekly: nil)
        candidates = [
          [ hourly_baseline, hourly || current_count ],
          [ daily_baseline, daily || current_count ],
          [ weekly_baseline, weekly || current_count ]
        ]
        baseline, count = candidates.find { |b, c| b && c }

        if baseline.nil?
          return { anomaly: false, level: nil, baseline_type: nil, message: "No baseline available" }
        end

        level = baseline.anomaly_level(count, sensitivity: sensitivity)

        {
          anomaly: level.present?,
          level: level,
          baseline_type: baseline.baseline_type,
          current_count: count,
          threshold: baseline.threshold(sensitivity: sensitivity),
          std_devs_above: baseline.std_devs_above_mean(count)
        }
      end

      # Events so far in the current hour / day / week, counted in the same
      # units the baselines were built from (Services::BaselineCalculator).
      # @return [Hash] { hourly: Integer, daily: Integer, weekly: Integer }
      def current_counts
        relation = Services::BaselineCalculator.counting_relation(@error_type, @platform)
        column = Services::BaselineCalculator.time_column
        now = Time.current
        {
          hourly: relation.where("#{column} >= ?", now.beginning_of_hour).count,
          daily: relation.where("#{column} >= ?", now.beginning_of_day).count,
          weekly: relation.where("#{column} >= ?", now.beginning_of_week).count
        }
      end

      # The anomaly check for right now: current counts against their baselines.
      def check_current_anomaly(sensitivity: 2)
        check_anomaly(sensitivity: sensitivity, **current_counts)
      end
    end
  end
end
