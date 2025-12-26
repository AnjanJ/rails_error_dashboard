# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Calculate Mean Time to Resolution (MTTR) statistics
    # Provides metrics on how quickly errors are resolved
    class MttrStats
      def self.call(days = 30)
        new(days).call
      end

      def initialize(days = 30)
        @days = days
        @start_date = days.days.ago
      end

      def call
        {
          overall_mttr: calculate_overall_mttr,
          mttr_by_platform: mttr_by_platform,
          mttr_by_severity: mttr_by_severity,
          mttr_trend: mttr_trend_by_week,
          fastest_resolution: fastest_resolution_time,
          slowest_resolution: slowest_resolution_time,
          total_resolved: resolved_errors.count
        }
      end

      private

      def resolved_errors
        @resolved_errors ||= ErrorLog
          .where.not(resolved_at: nil)
          .where("occurred_at >= ?", @start_date)
      end

      def calculate_overall_mttr
        return 0 if resolved_errors.empty?

        total_hours = resolved_errors.sum do |error|
          ((error.resolved_at - error.occurred_at) / 3600.0).round(2)
        end
        (total_hours / resolved_errors.count).round(2)
      end

      def mttr_by_platform
        platforms = ErrorLog.distinct.pluck(:platform).compact

        platforms.each_with_object({}) do |platform, result|
          platform_resolved = resolved_errors.where(platform: platform)
          next if platform_resolved.empty?

          total_hours = platform_resolved.sum { |e| ((e.resolved_at - e.occurred_at) / 3600.0) }
          result[platform] = (total_hours / platform_resolved.count).round(2)
        end
      end

      def mttr_by_severity
        {
          critical: calculate_mttr_for_severity(:critical),
          high: calculate_mttr_for_severity(:high),
          medium: calculate_mttr_for_severity(:medium),
          low: calculate_mttr_for_severity(:low)
        }.compact
      end

      def calculate_mttr_for_severity(severity)
        severity_errors = resolved_errors.select { |e| e.severity == severity }
        return nil if severity_errors.empty?

        total_hours = severity_errors.sum { |e| ((e.resolved_at - e.occurred_at) / 3600.0) }
        (total_hours / severity_errors.count).round(2)
      end

      def mttr_trend_by_week
        trends = {}
        current_date = @start_date

        while current_date < Time.current
          week_end = current_date + 1.week
          week_resolved = ErrorLog
            .where.not(resolved_at: nil)
            .where("occurred_at >= ? AND occurred_at < ?", current_date, week_end)

          if week_resolved.any?
            total_hours = week_resolved.sum { |e| ((e.resolved_at - e.occurred_at) / 3600.0) }
            trends[current_date.to_date.to_s] = (total_hours / week_resolved.count).round(2)
          end

          current_date = week_end
        end

        trends
      end

      def fastest_resolution_time
        return nil if resolved_errors.empty?

        resolved_errors.min_by { |e| e.resolved_at - e.occurred_at }
                       .then { |e| ((e.resolved_at - e.occurred_at) / 60.0).round } # minutes
      end

      def slowest_resolution_time
        return nil if resolved_errors.empty?

        resolved_errors.max_by { |e| e.resolved_at - e.occurred_at }
                       .then { |e| ((e.resolved_at - e.occurred_at) / 3600.0).round(1) } # hours
      end
    end
  end
end
