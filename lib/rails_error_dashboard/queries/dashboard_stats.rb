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
          spike_info: spike_info
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
    end
  end
end
