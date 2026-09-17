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

      # Pairs considered by .current_anomalies, busiest first. A bound, so the
      # check costs the same whether 5 or 50,000 error types are stored.
      MAX_ANOMALY_PAIRS = 500
      BASELINE_PRECEDENCE = %w[hourly daily weekly].freeze

      # Every (error_type, platform) pair that is anomalous RIGHT NOW, for all
      # pairs at once. Same rule as #check_current_anomaly -- the first baseline
      # available among hourly / daily / weekly, compared against this hour /
      # today / this week -- but in a fixed number of queries instead of about six
      # per pair. DashboardStats calls this from the live stats broadcast, which
      # runs inside the host app's capture path.
      #
      # Only pairs with an event this week are looked at: a pair with none has a
      # count of zero, which no baseline can call anomalous.
      #
      # @return [Array<Hash>] error_type, platform, count, level, std_devs_above,
      #   baseline_type. Empty on any failure -- never raises.
      def self.current_anomalies(sensitivity: 2, application_id: nil)
        return [] unless defined?(ErrorBaseline) && ErrorBaseline.table_exists?

        counts = current_counts_by_pair(application_id: application_id)
        return [] if counts.empty?

        baselines = latest_baselines_for(counts.keys)

        counts.filter_map do |(error_type, platform), windows|
          kind = BASELINE_PRECEDENCE.find { |type| baselines[[ error_type, platform, type ]] }
          next unless kind

          baseline = baselines[[ error_type, platform, kind ]]
          # A flat history has no spread to measure against; dividing by it
          # makes any count above the mean infinitely anomalous.
          next if baseline.std_dev.nil? || baseline.std_dev.zero?

          count = windows.fetch(kind.to_sym)
          level = baseline.anomaly_level(count, sensitivity: sensitivity)
          next unless level

          {
            error_type: error_type,
            platform: platform,
            count: count,
            level: level,
            std_devs_above: baseline.std_devs_above_mean(count),
            baseline_type: kind
          }
        end
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] current_anomalies failed: #{e.class}: #{e.message}")
        []
      end

      # { [error_type, platform] => { hourly:, daily:, weekly: } } in ONE grouped
      # query, counted in the units the baselines were built from (occurrence
      # rows when that table exists). The week is the widest window, so it is
      # the WHERE; the day and the hour are conditional sums inside it.
      def self.current_counts_by_pair(application_id: nil)
        logs = ErrorLog.table_name
        column = Services::BaselineCalculator.time_column
        now = Time.current

        relation = if defined?(ErrorOccurrence) && ErrorOccurrence.table_exists?
          ErrorOccurrence.joins(:error_log)
        else
          ErrorLog.all
        end
        relation = relation.where(logs => { application_id: application_id }) if application_id.present?

        since = ->(time) { ErrorLog.sanitize_sql_array([ "SUM(CASE WHEN #{column} >= ? THEN 1 ELSE 0 END)", time ]) }

        rows = relation
                 .where("#{column} >= ?", now.beginning_of_week)
                 .group("#{logs}.error_type", "#{logs}.platform")
                 .order(Arel.sql("COUNT(*) DESC"))
                 .limit(MAX_ANOMALY_PAIRS)
                 .pluck(Arel.sql("#{logs}.error_type"), Arel.sql("#{logs}.platform"), Arel.sql("COUNT(*)"),
                        Arel.sql(since.call(now.beginning_of_day)), Arel.sql(since.call(now.beginning_of_hour)))

        rows.to_h do |error_type, platform, weekly, daily, hourly|
          [ [ error_type, platform ], { weekly: weekly.to_i, daily: daily.to_i, hourly: hourly.to_i } ]
        end
      end

      # { [error_type, platform, baseline_type] => ErrorBaseline }, the most recent
      # row of each, in ONE query. Baseline rows accumulate (one per calculation
      # period), so "latest" is resolved in SQL with a join on MAX(period_start)
      # rather than by loading the history. The join form is portable to every
      # adapter; a row-value IN is not.
      def self.latest_baselines_for(pairs)
        table = ErrorBaseline.table_name
        types = pairs.map(&:first).compact.uniq
        return {} if types.empty?

        latest = ErrorBaseline.where(error_type: types, baseline_type: BASELINE_PRECEDENCE)
                              .group(:error_type, :platform, :baseline_type)
                              .select(:error_type, :platform, :baseline_type, "MAX(period_start) AS latest_period_start")

        ErrorBaseline
          .joins("INNER JOIN (#{latest.to_sql}) latest_baselines ON " \
                 "latest_baselines.error_type = #{table}.error_type AND " \
                 "latest_baselines.platform = #{table}.platform AND " \
                 "latest_baselines.baseline_type = #{table}.baseline_type AND " \
                 "latest_baselines.latest_period_start = #{table}.period_start")
          .index_by { |baseline| [ baseline.error_type, baseline.platform, baseline.baseline_type ] }
      end
      private_class_method :current_counts_by_pair, :latest_baselines_for

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
      def current_counts(application_id: nil)
        relation = Services::BaselineCalculator.counting_relation(@error_type, @platform, application_id: application_id)
        column = Services::BaselineCalculator.time_column
        now = Time.current
        {
          hourly: relation.where("#{column} >= ?", now.beginning_of_hour).count,
          daily: relation.where("#{column} >= ?", now.beginning_of_day).count,
          weekly: relation.where("#{column} >= ?", now.beginning_of_week).count
        }
      end

      # The anomaly check for right now: current counts against their baselines.
      # @param application_id [Integer, nil] scope the current counts to one application
      def check_current_anomaly(sensitivity: 2, application_id: nil)
        check_anomaly(sensitivity: sensitivity, **current_counts(application_id: application_id))
      end
    end
  end
end
