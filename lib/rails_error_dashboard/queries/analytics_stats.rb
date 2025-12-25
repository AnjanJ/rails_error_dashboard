# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Fetch analytics statistics for charts and trends
    # This is a read operation that aggregates error data over time
    class AnalyticsStats
      def self.call(days = 30)
        new(days).call
      end

      def initialize(days = 30)
        @days = days
        @start_date = days.days.ago
      end

      def call
        {
          days: @days,
          error_stats: error_statistics,
          errors_over_time: errors_over_time,
          errors_by_type: errors_by_type,
          errors_by_platform: errors_by_platform,
          errors_by_hour: errors_by_hour,
          top_users: top_affected_users,
          resolution_rate: resolution_rate,
          mobile_errors: mobile_errors_count,
          api_errors: api_errors_count,
          pattern_insights: pattern_insights
        }
      end

      private

      def base_query
        ErrorLog.where("occurred_at >= ?", @start_date)
      end

      def error_statistics
        {
          total: base_query.count,
          unresolved: base_query.unresolved.count,
          by_type: base_query.group(:error_type).count.sort_by { |_, count| -count }.to_h,
          by_day: base_query.group("DATE(occurred_at)").count
        }
      end

      def errors_over_time
        base_query.group_by_day(:occurred_at).count
      end

      def errors_by_type
        base_query.group(:error_type)
                  .count
                  .sort_by { |_, count| -count }
                  .first(10)
                  .to_h
      end

      def errors_by_platform
        base_query.group(:platform).count
      end

      def errors_by_hour
        base_query.group_by_hour(:occurred_at).count
      end

      def top_affected_users
        user_model = RailsErrorDashboard.configuration.user_model

        base_query.where.not(user_id: nil)
                  .group(:user_id)
                  .count
                  .sort_by { |_, count| -count }
                  .first(10)
                  .map { |user_id, count| [ find_user_email(user_id, user_model), count ] }
                  .to_h
      end

      def find_user_email(user_id, user_model)
        user = user_model.constantize.find_by(id: user_id)
        user&.email || "User ##{user_id}"
      rescue
        "User ##{user_id}"
      end

      def resolution_rate
        total = error_statistics[:total]
        return 0 if total.zero?

        resolved_count = ErrorLog.resolved.where("occurred_at >= ?", @start_date).count
        ((resolved_count.to_f / total) * 100).round(1)
      end

      def mobile_errors_count
        base_query.where(platform: [ "iOS", "Android" ]).count
      end

      def api_errors_count
        base_query.where("platform IS NULL OR platform = ?", "API").count
      end

      #  Pattern insights for top error types
      # Analyzes occurrence patterns and bursts for top 5 error types
      def pattern_insights
        return {} unless defined?(Services::PatternDetector)

        # Get top 5 error types by count
        top_errors = errors_by_type.first(5)

        insights = {}
        top_errors.each do |error_type, _count|
          # Get platform for this error type (most common platform)
          platform = base_query.where(error_type: error_type)
                              .group(:platform)
                              .count
                              .max_by { |_, count| count }
                              &.first || "API"

          # Analyze pattern for this error type
          pattern = Services::PatternDetector.analyze_cyclical_pattern(
            error_type: error_type,
            platform: platform,
            days: @days
          )

          # Detect bursts
          bursts = Services::PatternDetector.detect_bursts(
            error_type: error_type,
            platform: platform,
            days: [ 7, @days ].min # Use 7 days for burst detection, or less if analyzing shorter period
          )

          insights[error_type] = {
            pattern: pattern,
            bursts: bursts,
            has_pattern: pattern[:pattern_type] != :none,
            has_bursts: bursts.any?
          }
        end

        insights
      end
    end
  end
end
