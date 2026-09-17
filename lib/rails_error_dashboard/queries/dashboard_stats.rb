# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Fetch dashboard statistics
    # This is a read operation that aggregates error data for the dashboard
    class DashboardStats
      def initialize(application_id: nil)
        @application_id = application_id
      end

      def self.call(application_id: nil)
        new(application_id: application_id).call
      end

      def call
        # Cache dashboard stats for 1 minute to reduce database load
        # Dashboard is viewed frequently, so short cache prevents stale data
        begin
          Rails.cache.fetch(cache_key, expires_in: 1.minute) do
            {
              # EVENTS, not groups. An ErrorLog row is a group whose
              # occurrence_count says how many times it happened, so counting
              # rows reported five users hitting one error as "1 error today".
              # Summing is also exact during a storm: counted-only events never
              # create occurrence rows, but they DO raise occurrence_count.
              total_today: event_count_since(Time.current.beginning_of_day),
              total_week: event_count_since(7.days.ago),
              total_month: event_count_since(30.days.ago),
              unresolved: base_scope.unresolved.count,
              resolved: base_scope.resolved.count,
              reopened: reopened_count,
              by_platform: base_scope.group(:platform).count,
              top_errors: top_errors,
              #  Trend visualizations
              errors_trend_7d: errors_trend_7d,
              errors_by_severity_7d: errors_by_severity_7d,
              spike_detected: spike_detected?,
              spike_info: spike_info,
              # New metrics for Overview dashboard
              error_rate: error_rate,
              affected_users_today: affected_users_today,
              affected_users_yesterday: affected_users_yesterday,
              affected_users_change: affected_users_change,
              trend_percentage: trend_percentage,
              trend_direction: trend_direction,
              top_errors_by_impact: top_errors_by_impact,
              average_resolution_time: average_resolution_time,
              # Affected-user figures come from occurrence rows, which storm
              # count-only events never create. When that happened in the
              # window, the dimension is incomplete and the page says so
              # rather than presenting an undercount as fact.
              affected_users_incomplete: affected_users_incomplete?,
              data_unavailable: false
            }
          end
        rescue => e
          # If Rails.cache or any stats query fails, return empty stats hash
          # This prevents broadcast failures in API-only mode or when cache is unavailable
          RailsErrorDashboard::Logger.error("[RailsErrorDashboard] DashboardStats failed: #{e.class} - #{e.message}")
          RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] Backtrace: #{e.backtrace&.first(3)&.join("\n")}")

          # Return minimal stats hash to prevent nil errors in views
          # Zero errors and "we could not read the data" are different states.
          # Reporting healthy-looking zeros made a failed dashboard query
          # indistinguishable from a quiet day; data_unavailable lets the page
          # say which it is.
          {
            data_unavailable: true,
            affected_users_incomplete: false,
            total_today: 0,
            total_week: 0,
            total_month: 0,
            unresolved: 0,
            resolved: 0,
            reopened: 0,
            by_platform: {},
            top_errors: {},
            errors_trend_7d: {},
            errors_by_severity_7d: { critical: 0, high: 0, medium: 0, low: 0 },
            spike_detected: false,
            spike_info: nil,
            error_rate: 0.0,
            affected_users_today: 0,
            affected_users_yesterday: 0,
            affected_users_change: 0,
            trend_percentage: 0.0,
            trend_direction: :stable,
            top_errors_by_impact: [],
            average_resolution_time: nil
          }
        end
      end

      def cache_key
        # The cache GENERATION, not maximum(:updated_at): the timestamp cost a
        # query per key build and changed on every capture, so the cache never
        # hit while errors were arriving. Freshness after a capture is the
        # 1-minute TTL; user actions bump the generation (AnalyticsCacheManager).
        [
          "dashboard_stats",
          @application_id || "all",
          Services::AnalyticsCacheManager.generation,
          Time.current.hour
        ].join("/")
      end

      private

      def base_scope
        scope = ErrorLog.all
        scope = scope.where(application_id: @application_id) if @application_id.present?
        scope
      end

      # Total EVENTS in a window: the sum of every matching group's
      # occurrence_count. platform_comparison.rb counts the same way.
      def event_count_since(since)
        base_scope.where("occurred_at >= ?", since).sum(:occurrence_count)
      end

      def event_count_between(from, to)
        base_scope.where("occurred_at >= ? AND occurred_at < ?", from, to).sum(:occurrence_count)
      end

      # Occurrence rows carry the user of EACH event. The group's user_id is
      # mutable -- refreshed by the latest occurrence -- so counting it
      # distinct over groups can only ever yield zero or one per group.
      def occurrence_scope
        occurrences = ErrorOccurrence.table_name
        scope = ErrorOccurrence.joins(:error_log)
        scope = scope.where(ErrorLog.table_name => { application_id: @application_id }) if @application_id.present?
        scope
      end

      def occurrences_available?
        defined?(ErrorOccurrence) && ErrorOccurrence.table_exists?
      rescue StandardError
        false
      end

      # True when the window contains more events than recorded occurrences --
      # i.e. storm shedding dropped per-event rows, so any occurrence-derived
      # dimension (affected users) is a floor, not a total.
      def affected_users_incomplete?
        return false unless occurrences_available?

        recorded = occurrence_scope
                     .where("#{ErrorOccurrence.table_name}.occurred_at >= ?", Time.current.beginning_of_day)
                     .count
        recorded < event_count_since(Time.current.beginning_of_day)
      rescue StandardError
        false
      end

      def reopened_count
        return 0 unless ErrorLog.column_names.include?("reopened_at")

        base_scope.where.not(reopened_at: nil).count
      end

      def top_errors
        base_scope.where("occurred_at >= ?", 7.days.ago)
                  .group(:error_type)
                  .sum(:occurrence_count)
                  .sort_by { |_, count| -count }
                  .first(10)
                  .to_h
      end

      # Get 7-day error trend (daily counts)
      def errors_trend_7d
        base_scope.where("occurred_at >= ?", 7.days.ago)
                  .group_by_day(:occurred_at, range: 7.days.ago.to_date..Date.current, default_value: 0)
                  .sum(:occurrence_count)
      end

      # Get error counts by severity for last 7 days
      # OPTIMIZED: Use database filtering instead of loading all records into Ruby
      def errors_by_severity_7d
        scoped_errors = base_scope.where("occurred_at >= ?", 7.days.ago)

        {
          critical: scoped_errors.where(error_type: Services::SeverityClassifier::CRITICAL_ERROR_TYPES).sum(:occurrence_count),
          high: scoped_errors.where(error_type: Services::SeverityClassifier::HIGH_SEVERITY_ERROR_TYPES).sum(:occurrence_count),
          medium: scoped_errors.where(error_type: Services::SeverityClassifier::MEDIUM_SEVERITY_ERROR_TYPES).sum(:occurrence_count),
          low: scoped_errors.where.not(
            error_type: Services::SeverityClassifier::CRITICAL_ERROR_TYPES +
                       Services::SeverityClassifier::HIGH_SEVERITY_ERROR_TYPES +
                       Services::SeverityClassifier::MEDIUM_SEVERITY_ERROR_TYPES
          ).sum(:occurrence_count)
        }
      end

      # Detect if there's an error spike
      #  Uses baselines if available, falls back to simple 2x average
      def spike_detected?
        return false if errors_trend_7d.empty?

        today_count = event_count_since(Time.current.beginning_of_day)

        # Try baseline-based detection first
        if baseline_anomaly_detected?(today_count)
          return true
        end

        # Fall back to simple 2x average detection
        avg_count = errors_trend_7d.values.sum / 7.0
        return false if avg_count.zero?

        today_count >= (avg_count * 2)
      end

      # Get spike information
      #  Enhanced with baseline information
      def spike_info
        return nil unless spike_detected?

        today_count = event_count_since(Time.current.beginning_of_day)
        avg_count = (errors_trend_7d.values.sum / 7.0).round(1)

        info = {
          today_count: today_count,
          avg_count: avg_count,
          multiplier: (today_count / avg_count).round(1),
          severity: Services::StatisticalClassifier.spike_severity(today_count / avg_count)
        }

        # Add baseline info if available
        baseline_info = baseline_anomaly_info(today_count)
        info.merge!(baseline_info) if baseline_info.present?

        info
      end

      # Check if baseline indicates anomaly
      def baseline_anomaly_detected?(_count)
        return false unless defined?(Queries::BaselineStats)

        # Check most common error types for anomalies
        base_scope.distinct.pluck(:error_type, :platform).compact.any? do |(error_type, platform)|
          Queries::BaselineStats.new(error_type, platform)
                                .check_current_anomaly(sensitivity: 2, application_id: @application_id)[:anomaly]
        end
      end

      # Get baseline anomaly information
      def baseline_anomaly_info(_total_count)
        return nil unless defined?(Queries::BaselineStats)

        # Find the most anomalous error type
        anomalies = base_scope.distinct.pluck(:error_type, :platform).compact.map do |(error_type, platform)|
          result = Queries::BaselineStats.new(error_type, platform)
                                         .check_current_anomaly(sensitivity: 2, application_id: @application_id)
          next unless result[:anomaly]

          {
            error_type: error_type,
            platform: platform,
            count: result[:current_count],
            level: result[:level],
            std_devs_above: result[:std_devs_above]
          }
        end.compact

        return nil if anomalies.empty?

        # Return info about worst anomaly
        worst = anomalies.max_by { |a| a[:std_devs_above] || 0 }
        {
          baseline_detected: true,
          anomaly_error_type: worst[:error_type],
          anomaly_platform: worst[:platform],
          anomaly_level: worst[:level],
          std_devs_above: worst[:std_devs_above]&.round(1)
        }
      end

      # Errors per hour so far today. NOT a percentage.
      #
      # This value was rendered with a "%" sign against a scale that mapped
      # one error per hour to "1%", and was capped at 100 -- a rate of 4,000
      # errors/hour displayed as "100%". There is no request denominator to
      # make a real failure percentage from, so the honest figure is the rate
      # itself, uncapped, labelled with its unit.
      def error_rate
        today_events = event_count_since(Time.current.beginning_of_day)
        return 0.0 if today_events.zero?

        hours_today = ((Time.current - Time.current.beginning_of_day) / 1.hour).round(1)
        hours_today = 1.0 if hours_today < 1.0 # Avoid dividing by ~0 just after midnight

        (today_events / hours_today).round(1)
      end

      # Distinct users affected today, counted from OCCURRENCE rows.
      #
      # The group's user_id is overwritten by each new occurrence, so counting
      # it distinct across groups reported five users hitting one error as one
      # affected user. Storm count-only events create no occurrence row, so
      # this is a floor during a storm -- affected_users_incomplete? says when.
      def affected_users_today
        distinct_affected_users(Time.current.beginning_of_day, nil)
      end

      def affected_users_yesterday
        distinct_affected_users(1.day.ago.beginning_of_day, Time.current.beginning_of_day)
      end

      def distinct_affected_users(from, to)
        unless occurrences_available?
          scope = base_scope.where("occurred_at >= ?", from)
          scope = scope.where("occurred_at < ?", to) if to
          return scope.where.not(user_id: nil).distinct.count(:user_id)
        end

        occurrences = ErrorOccurrence.table_name
        scope = occurrence_scope.where("#{occurrences}.occurred_at >= ?", from)
        scope = scope.where("#{occurrences}.occurred_at < ?", to) if to
        scope.where.not(occurrences => { user_id: nil }).distinct.count("#{occurrences}.user_id")
      rescue StandardError
        0
      end

      # Calculate change in affected users (today vs yesterday)
      def affected_users_change
        today = affected_users_today
        yesterday = affected_users_yesterday

        return 0 if today.zero? && yesterday.zero?
        return today if yesterday.zero?

        today - yesterday
      end

      # Calculate percentage change in errors (today vs yesterday)
      def trend_percentage
        today = event_count_since(Time.current.beginning_of_day)
        yesterday = event_count_between(1.day.ago.beginning_of_day, Time.current.beginning_of_day)

        return 0.0 if today.zero? && yesterday.zero?
        return 100.0 if yesterday.zero? && today.positive?

        ((today - yesterday).to_f / yesterday * 100).round(1)
      end

      # Determine trend direction (increasing, decreasing, stable)
      def trend_direction
        trend = trend_percentage

        if trend > 10
          :increasing
        elsif trend < -10
          :decreasing
        else
          :stable
        end
      end

      # Get top 6 errors ranked by impact score
      # Impact = affected_users_count × occurrence_count
      # Top errors by impact = distinct affected users x events.
      #
      # This grouped by each row's own id and counted DISTINCT user_id within
      # that single row, which can only be zero or one -- so every error's
      # "affected users" was 1 and the impact score was just its occurrence
      # count. The user count comes from occurrence rows, where each event
      # carries its own user.
      def top_errors_by_impact
        errors = base_scope.where("occurred_at >= ?", 7.days.ago)
                           .order(occurrence_count: :desc)
                           .limit(50)
                           .to_a
        return [] if errors.empty?

        users_by_error = distinct_users_by_error_log(errors.map(&:id))

        errors.map { |error|
          affected = users_by_error.fetch(error.id, error.user_id.present? ? 1 : 0)
          {
            id: error.id,
            error_type: error.error_type,
            message: error.message&.truncate(80),
            severity: Services::SeverityClassifier.classify(error.error_type),
            occurrence_count: error.occurrence_count,
            affected_users: affected,
            impact_score: affected * error.occurrence_count.to_i,
            occurred_at: error.occurred_at
          }
        }.sort_by { |entry| -entry[:impact_score] }.first(6)
      end

      # error_log_id => distinct users with a recorded occurrence.
      def distinct_users_by_error_log(error_log_ids)
        return {} unless occurrences_available?
        return {} if error_log_ids.empty?

        ErrorOccurrence.where(error_log_id: error_log_ids)
                       .where.not(user_id: nil)
                       .group(:error_log_id)
                       .distinct
                       .count(:user_id)
      rescue StandardError
        {}
      end

      # Calculate average resolution time (MTTR) in hours for the last 30 days
      # Uses SQL AVG to avoid loading all resolved errors into Ruby memory
      def average_resolution_time
        scope = base_scope.resolved.where("resolved_at >= ?", 30.days.ago)
        return nil unless scope.exists?

        avg_seconds = scope.pick(Arel.sql(avg_seconds_sql))
        return nil unless avg_seconds

        (avg_seconds.to_f / 3600.0).round(2)
      end

      def avg_seconds_sql
        case db_adapter
        when :postgresql
          "AVG(EXTRACT(EPOCH FROM (resolved_at - occurred_at)))"
        when :mysql
          "AVG(TIMESTAMPDIFF(SECOND, occurred_at, resolved_at))"
        else
          # SQLite: julianday difference * 86400 gives seconds
          "AVG((julianday(resolved_at) - julianday(occurred_at)) * 86400)"
        end
      end

      def db_adapter
        adapter = ErrorLog.connection.adapter_name.downcase
        if adapter.include?("postgresql")
          :postgresql
        elsif adapter.include?("mysql") || adapter.include?("trilogy")
          :mysql
        else
          :sqlite
        end
      end
    end
  end
end
