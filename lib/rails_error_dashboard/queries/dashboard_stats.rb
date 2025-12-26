# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Fetch dashboard statistics
    # This is a read operation that aggregates error data for the dashboard
    class DashboardStats
      def self.call
        new.call
      end

      def call
        {
          total_today: ErrorLog.where("occurred_at >= ?", Time.current.beginning_of_day).count,
          total_week: ErrorLog.where("occurred_at >= ?", 7.days.ago).count,
          total_month: ErrorLog.where("occurred_at >= ?", 30.days.ago).count,
          unresolved: ErrorLog.unresolved.count,
          resolved: ErrorLog.resolved.count,
          by_platform: ErrorLog.group(:platform).count,
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
          top_errors_by_impact: top_errors_by_impact
        }
      end

      private

      def top_errors
        ErrorLog.where("occurred_at >= ?", 7.days.ago)
                .group(:error_type)
                .count
                .sort_by { |_, count| -count }
                .first(10)
                .to_h
      end

      # Get 7-day error trend (daily counts)
      def errors_trend_7d
        ErrorLog.where("occurred_at >= ?", 7.days.ago)
                .group_by_day(:occurred_at, range: 7.days.ago.to_date..Date.current, default_value: 0)
                .count
      end

      # Get error counts by severity for last 7 days
      def errors_by_severity_7d
        last_7_days = ErrorLog.where("occurred_at >= ?", 7.days.ago)

        {
          critical: last_7_days.select { |e| e.severity == :critical }.count,
          high: last_7_days.select { |e| e.severity == :high }.count,
          medium: last_7_days.select { |e| e.severity == :medium }.count,
          low: last_7_days.select { |e| e.severity == :low }.count
        }
      end

      # Detect if there's an error spike
      #  Uses baselines if available, falls back to simple 2x average
      def spike_detected?
        return false if errors_trend_7d.empty?

        today_count = ErrorLog.where("occurred_at >= ?", Time.current.beginning_of_day).count

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

        today_count = ErrorLog.where("occurred_at >= ?", Time.current.beginning_of_day).count
        avg_count = (errors_trend_7d.values.sum / 7.0).round(1)

        info = {
          today_count: today_count,
          avg_count: avg_count,
          multiplier: (today_count / avg_count).round(1),
          severity: spike_severity(today_count / avg_count)
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
        ErrorLog.distinct.pluck(:error_type, :platform).compact.any? do |(error_type, platform)|
          stats = Queries::BaselineStats.new(error_type, platform)
          error_count = ErrorLog.where(
            error_type: error_type,
            platform: platform
          ).where("occurred_at >= ?", Time.current.beginning_of_day).count

          result = stats.check_anomaly(error_count, sensitivity: 2)
          result[:anomaly]
        end
      end

      # Get baseline anomaly information
      def baseline_anomaly_info(_total_count)
        return nil unless defined?(Queries::BaselineStats)

        # Find the most anomalous error type
        anomalies = ErrorLog.distinct.pluck(:error_type, :platform).compact.map do |(error_type, platform)|
          stats = Queries::BaselineStats.new(error_type, platform)
          error_count = ErrorLog.where(
            error_type: error_type,
            platform: platform
          ).where("occurred_at >= ?", Time.current.beginning_of_day).count

          result = stats.check_anomaly(error_count, sensitivity: 2)
          next unless result[:anomaly]

          {
            error_type: error_type,
            platform: platform,
            count: error_count,
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

      # Determine spike severity based on multiplier
      def spike_severity(multiplier)
        case multiplier
        when 0...2
          :normal
        when 2...5
          :elevated
        when 5...10
          :high
        else
          :critical
        end
      end

      # Calculate error rate as a percentage
      # Since we don't track total requests, we'll use error count as proxy
      # In the future, this could be: (errors / total_requests) * 100
      def error_rate
        today_errors = ErrorLog.where("occurred_at >= ?", Time.current.beginning_of_day).count
        return 0.0 if today_errors.zero?

        # For now, use a simple heuristic: errors per hour today
        # Assume we want < 1 error per hour = good (< 1%)
        # 1-5 errors per hour = warning (1-5%)
        # > 5 errors per hour = critical (> 5%)
        hours_today = ((Time.current - Time.current.beginning_of_day) / 1.hour).round(1)
        hours_today = 1.0 if hours_today < 1.0 # Avoid division by zero in early morning

        errors_per_hour = today_errors / hours_today
        # Convert to percentage scale (0-100)
        # Scale: 0 errors/hr = 0%, 1 error/hr = 1%, 10 errors/hr = 10%, etc.
        [errors_per_hour, 100.0].min.round(1)
      end

      # Count distinct users affected by errors today
      def affected_users_today
        ErrorLog.where("occurred_at >= ?", Time.current.beginning_of_day)
                .where.not(user_id: nil)
                .distinct
                .count(:user_id)
      end

      # Count distinct users affected by errors yesterday
      def affected_users_yesterday
        ErrorLog.where("occurred_at >= ? AND occurred_at < ?",
                      1.day.ago.beginning_of_day,
                      Time.current.beginning_of_day)
                .where.not(user_id: nil)
                .distinct
                .count(:user_id)
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
        today = ErrorLog.where("occurred_at >= ?", Time.current.beginning_of_day).count
        yesterday = ErrorLog.where("occurred_at >= ? AND occurred_at < ?",
                                  1.day.ago.beginning_of_day,
                                  Time.current.beginning_of_day).count

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

      # Get top 5 errors ranked by impact score
      # Impact = affected_users_count × occurrence_count
      def top_errors_by_impact
        ErrorLog.where("occurred_at >= ?", 7.days.ago)
                .group(:error_type, :id)
                .select("error_type, id, occurrence_count,
                        COUNT(DISTINCT user_id) as affected_users,
                        COUNT(DISTINCT user_id) * occurrence_count as impact_score")
                .order("impact_score DESC")
                .limit(5)
                .map do |error|
                  full_error = ErrorLog.find(error.id)
                  {
                    id: error.id,
                    error_type: error.error_type,
                    message: full_error.message&.truncate(80),
                    severity: full_error.severity,
                    occurrence_count: error.occurrence_count,
                    affected_users: error.affected_users.to_i,
                    impact_score: error.impact_score.to_i,
                    occurred_at: full_error.occurred_at
                  }
                end
      end
    end
  end
end
