# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Developer-focused insights
    # Provides actionable metrics instead of environment breakdowns
    class DeveloperInsights
      def self.call(days = 7)
        new(days).call
      end

      def initialize(days = 7)
        @days = days
        @start_date = days.days.ago
      end

      def call
        {
          critical_metrics: critical_metrics,
          error_trends: error_trends,
          hot_spots: hot_spots,
          platform_health: platform_health,
          resolution_metrics: resolution_metrics,
          error_velocity: error_velocity,
          top_impacted_users: top_impacted_users,
          recurring_issues: recurring_issues
        }
      end

      private

      def base_query
        @base_query ||= ErrorLog.where("occurred_at >= ?", @start_date)
      end

      # Critical metrics developers care about
      def critical_metrics
        {
          total_errors: base_query.count,
          unresolved_count: base_query.unresolved.count,
          critical_unresolved: base_query.unresolved.where(
            error_type: critical_error_types
          ).count,
          new_error_types: new_error_types_count,
          recurring_errors: base_query.where("occurrence_count > ?", 5).count,
          errors_last_hour: ErrorLog.where("occurred_at >= ?", 1.hour.ago).count,
          errors_trending_up: errors_trending_up?
        }
      end

      # Error trends over time
      def error_trends
        {
          hourly: hourly_distribution,
          daily: daily_distribution,
          by_type_over_time: type_trends
        }
      end

      # Hot spots - where errors are concentrated
      def hot_spots
        {
          top_error_types: base_query.group(:error_type)
                                    .order("count_id DESC")
                                    .limit(10)
                                    .count,
          most_frequent: base_query.order(occurrence_count: :desc)
                                  .limit(10)
                                  .pluck(:error_type, :message, :occurrence_count)
                                  .map { |type, msg, count|
                                    { error_type: type, message: msg.truncate(100), count: count }
                                  },
          recent_spikes: detect_spikes
        }
      end

      # Platform health breakdown
      def platform_health
        platforms = base_query.group(:platform).count

        {
          by_platform: platforms,
          ios_stability: calculate_stability("iOS"),
          android_stability: calculate_stability("Android"),
          api_stability: calculate_stability("API")
        }
      end

      # Resolution metrics
      def resolution_metrics
        total = base_query.count
        resolved = base_query.resolved.count

        {
          resolution_rate: total.zero? ? 0 : (resolved.to_f / total * 100).round(2),
          average_resolution_time: average_resolution_time,
          unresolved_age: unresolved_age_distribution,
          resolved_today: ErrorLog.resolved
                                 .where("resolved_at >= ?", Time.current.beginning_of_day)
                                 .count
        }
      end

      # Error velocity - how fast errors are being introduced
      def error_velocity
        current_period = base_query.count
        previous_period = ErrorLog.where(
          "occurred_at >= ? AND occurred_at < ?",
          (@days * 2).days.ago,
          @start_date
        ).count

        change = current_period - previous_period
        change_percent = previous_period.zero? ? 0 : (change.to_f / previous_period * 100).round(2)

        {
          current_period_count: current_period,
          previous_period_count: previous_period,
          change: change,
          change_percent: change_percent,
          trend: change >= 0 ? "increasing" : "decreasing"
        }
      end

      # Users most impacted by errors
      def top_impacted_users
        base_query.where.not(user_id: nil)
                 .group(:user_id)
                 .order("count_id DESC")
                 .limit(10)
                 .count
                 .transform_keys { |user_id| user_id || "Guest" }
      end

      # Recurring issues that keep coming back
      def recurring_issues
        base_query.where("occurrence_count > ?", 3)
                 .where("(last_seen_at - first_seen_at) > ?", 1.day.to_i)
                 .order(occurrence_count: :desc)
                 .limit(10)
                 .pluck(:error_type, :message, :occurrence_count, :first_seen_at, :last_seen_at)
                 .map { |type, msg, count, first, last|
                   {
                     error_type: type,
                     message: msg.truncate(100),
                     occurrence_count: count,
                     duration_days: ((last - first) / 1.day).round(1),
                     first_seen: first,
                     last_seen: last
                   }
                 }
      end

      # Helper methods

      def critical_error_types
        %w[
          SecurityError
          NoMemoryError
          SystemStackError
          SignalException
          ActiveRecord::StatementInvalid
        ]
      end

      def new_error_types_count
        # Error types that first appeared in this period
        current_types = base_query.distinct.pluck(:error_type)
        all_time_types = ErrorLog.where("occurred_at < ?", @start_date)
                               .distinct
                               .pluck(:error_type)

        (current_types - all_time_types).count
      end

      def errors_trending_up?
        last_24h = ErrorLog.where("occurred_at >= ?", 24.hours.ago).count
        prev_24h = ErrorLog.where("occurred_at >= ? AND occurred_at < ?",
                                 48.hours.ago, 24.hours.ago).count

        last_24h > prev_24h
      end

      def hourly_distribution
        base_query.group("EXTRACT(HOUR FROM occurred_at)")
                 .order("EXTRACT(HOUR FROM occurred_at)")
                 .count
      end

      def daily_distribution
        base_query.group("DATE(occurred_at)")
                 .order("DATE(occurred_at)")
                 .count
      end

      def type_trends
        # Get top 5 error types and their trend over days
        top_types = base_query.group(:error_type)
                             .order("count_id DESC")
                             .limit(5)
                             .pluck(:error_type)

        trends = {}
        top_types.each do |error_type|
          trends[error_type] = base_query.where(error_type: error_type)
                                        .group("DATE(occurred_at)")
                                        .count
        end

        trends
      end

      def calculate_stability(platform)
        total = base_query.where(platform: platform).count
        return 100.0 if total.zero?

        # Stability = 100 - (errors per 1000 requests ratio)
        # Simplified: just show error rate
        100.0 - [ (total.to_f / 10), 100.0 ].min
      end

      def average_resolution_time
        resolved_errors = base_query.resolved
                                   .where.not(resolved_at: nil)

        return 0 if resolved_errors.count.zero?

        total_time = resolved_errors.sum { |error|
          (error.resolved_at - error.occurred_at).to_i
        }

        average_seconds = total_time / resolved_errors.count
        (average_seconds / 3600.0).round(2) # Convert to hours
      end

      def unresolved_age_distribution
        unresolved = base_query.unresolved

        {
          under_1_hour: unresolved.where("occurred_at >= ?", 1.hour.ago).count,
          "1_24_hours": unresolved.where("occurred_at >= ? AND occurred_at < ?",
                                       24.hours.ago, 1.hour.ago).count,
          "1_7_days": unresolved.where("occurred_at >= ? AND occurred_at < ?",
                                      7.days.ago, 24.hours.ago).count,
          over_7_days: unresolved.where("occurred_at < ?", 7.days.ago).count
        }
      end

      def detect_spikes
        # Find error types that suddenly spiked in last 24 hours
        last_24h = ErrorLog.where("occurred_at >= ?", 24.hours.ago)
        prev_24h = ErrorLog.where("occurred_at >= ? AND occurred_at < ?",
                                 48.hours.ago, 24.hours.ago)

        current_counts = last_24h.group(:error_type).count
        previous_counts = prev_24h.group(:error_type).count

        spikes = []
        current_counts.each do |error_type, current_count|
          previous_count = previous_counts[error_type] || 0

          # Spike if current is > 2x previous AND at least 5 errors
          if current_count > previous_count * 2 && current_count >= 5
            spikes << {
              error_type: error_type,
              current_count: current_count,
              previous_count: previous_count,
              increase_percent: previous_count.zero? ? 999 : ((current_count - previous_count).to_f / previous_count * 100).round(0)
            }
          end
        end

        spikes.sort_by { |s| -s[:increase_percent] }.first(5)
      end
    end
  end
end
