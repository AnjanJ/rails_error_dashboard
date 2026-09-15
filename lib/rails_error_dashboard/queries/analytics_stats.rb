# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Fetch analytics statistics for charts and trends
    # This is a read operation that aggregates error data over time
    class AnalyticsStats
      def initialize(days = 30, application_id: nil)
        @days = days
        @application_id = application_id
        @start_date = days.days.ago
      end

      def self.call(days = 30, application_id: nil)
        new(days, application_id: application_id).call
      end

      def call
        # Cache analytics data for 5 minutes to reduce database load
        # Cache key includes days parameter and last error update timestamp
        Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
          {
            days: @days,
            error_stats: error_statistics,
            errors_over_time: errors_over_time,
            errors_by_type: errors_by_type,
            errors_by_platform: errors_by_platform,
            errors_by_environment: errors_by_environment,
            errors_by_hour: errors_by_hour,
            top_users: top_affected_users,
            resolution_rate: resolution_rate,
            mobile_errors: mobile_errors_count,
            api_errors: api_errors_count,
            pattern_insights: pattern_insights
          }
        end
      end

      def cache_key
        # Cache key includes:
        # - Query class name
        # - Days parameter (different time ranges = different caches)
        # - Application ID (per-app caching)
        # - Last error update timestamp (auto-invalidates when errors change)
        # - Start date (ensures correct time window)
        [
          "analytics_stats",
          @days,
          @application_id || "all",
          base_scope.maximum(:updated_at)&.to_i || 0,
          @start_date.to_date.to_s
        ].join("/")
      end

      private

      def base_scope
        scope = ErrorLog.all
        scope = scope.where(application_id: @application_id) if @application_id.present?
        scope
      end

      def base_query
        base_scope.where("occurred_at >= ?", @start_date)
      end

      # Two counting units, kept distinct on purpose.
      #
      # An ErrorLog row is a GROUP; its occurrence_count says how many times
      # that error actually happened. Volume figures are EVENTS (the sum), so
      # this page agrees with the Overview, which counts the same way. Resolved
      # and unresolved stay GROUP counts -- a group is the thing that gets
      # resolved, and an event cannot be.
      def error_statistics
        {
          total: event_count,
          total_groups: base_query.count,
          unresolved: base_query.unresolved.count,
          resolved: base_query.resolved.count,
          by_type: base_query.group(:error_type).sum(:occurrence_count).sort_by { |_, count| -count }.to_h,
          by_day: base_query.group("DATE(occurred_at)").sum(:occurrence_count),
          affected_users_incomplete: affected_users_incomplete?
        }
      end

      # Total EVENTS in the window. dashboard_stats.rb and
      # platform_comparison.rb:165 count the same way.
      def event_count
        base_query.sum(:occurrence_count)
      end

      def errors_over_time
        base_query.group_by_day(:occurred_at).sum(:occurrence_count)
      end

      def errors_by_type
        base_query.group(:error_type)
                  .sum(:occurrence_count)
                  .sort_by { |_, count| -count }
                  .first(10)
                  .to_h
      end

      def errors_by_platform
        base_query.group(:platform).sum(:occurrence_count)
      end

      # NULL (captured before the column existed) is reported under :unknown
      # rather than dropped, so the chart's total still matches the period.
      def errors_by_environment
        return {} unless ErrorLog.column_names.include?("environment")

        base_query.group(:environment).sum(:occurrence_count).transform_keys { |env| env.nil? ? :unknown : env }
      end

      def errors_by_hour
        # group_by_hour_of_day buckets into 0..23 to show diurnal patterns
        # (when in the day errors peak). The chart title says "Errors by Hour
        # of Day" — group_by_hour produced a chronological time series instead.
        base_query.group_by_hour_of_day(:occurred_at).sum(:occurrence_count)
      end

      # Events per user, counted from OCCURRENCE rows.
      #
      # The group's user_id is overwritten by each new occurrence, so grouping
      # ErrorLog by it attributed a whole group to whoever happened to hit it
      # last -- at most one user per group, and their "count" was a number of
      # groups. Occurrence rows carry the user of each individual event.
      #
      # Storm count-only events create no occurrence row, so during a storm
      # this is a floor; affected_users_incomplete? says when.
      def top_affected_users
        user_model = RailsErrorDashboard.configuration.user_model

        counts = user_event_counts
        counts.sort_by { |_, count| -count }
              .first(10)
              .map { |user_id, count| { user_id: user_id, email: find_user_email(user_id, user_model), count: count } }
      end

      def user_event_counts
        return group_user_counts unless occurrences_available?

        occurrences = ErrorOccurrence.table_name
        counts = occurrence_scope.where("#{occurrences}.occurred_at >= ?", @start_date)
                                 .where.not(occurrences => { user_id: nil })
                                 .group("#{occurrences}.user_id")
                                 .count

        # A user whose events predate occurrence tracking -- or whose events
        # were shed by storm protection, which writes no occurrence row -- still
        # belongs in the table. Fall back to the group's own user for those,
        # taking whichever count is larger. UserImpactSummary merges the same way.
        group_user_counts.merge(counts) { |_user, group_count, occurrence_count| [ group_count, occurrence_count ].max }
      rescue StandardError
        group_user_counts
      end

      def group_user_counts
        base_query.where.not(user_id: nil).group(:user_id).sum(:occurrence_count)
      end

      # Occurrence rows joined back to error_logs, so the application filter
      # (which the occurrence table has no column for) still applies.
      def occurrence_scope
        scope = ErrorOccurrence.joins(:error_log)
        scope = scope.where(ErrorLog.table_name => { application_id: @application_id }) if @application_id.present?
        scope
      end

      def occurrences_available?
        defined?(ErrorOccurrence) && ErrorOccurrence.table_exists?
      rescue StandardError
        false
      end

      # True when the window holds more events than recorded occurrences --
      # storm shedding dropped per-event rows, so any occurrence-derived
      # figure (the affected-user table) is a floor, not a total.
      def affected_users_incomplete?
        return false unless occurrences_available?

        occurrences = ErrorOccurrence.table_name
        recorded = occurrence_scope.where("#{occurrences}.occurred_at >= ?", @start_date).count
        recorded < event_count
      rescue StandardError
        false
      end

      def find_user_email(user_id, user_model)
        user = user_model.constantize.find_by(id: user_id)
        user&.email || "User ##{user_id}"
      rescue
        "User ##{user_id}"
      end

      # Resolution rate is GROUPS over GROUPS.
      #
      # Volume is now measured in events, but resolving is something that
      # happens to a group, so dividing resolved groups by total events would
      # collapse the rate toward zero the moment any error recurred. The
      # Overview computes this the same way (resolved / resolved + unresolved),
      # so both pages report one rate.
      #
      # Same scoped relation on both sides: an unscoped numerator counted every
      # application's resolved errors against one application's total, and the
      # "rate" went past 100%.
      def resolution_rate
        resolved_count = base_query.resolved.count
        total_groups = resolved_count + base_query.unresolved.count
        return 0 if total_groups.zero?

        ((resolved_count.to_f / total_groups) * 100).round(1)
      end

      def mobile_errors_count
        base_query.where(platform: [ "iOS", "Android" ]).sum(:occurrence_count)
      end

      def api_errors_count
        base_query.where("platform IS NULL OR platform = ?", "API").sum(:occurrence_count)
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

          # Fetch timestamps for this error type+platform (Query fetches, Service computes)
          pattern_scope = base_query.where(error_type: error_type, platform: platform)
          timestamps = pattern_scope.pluck(:occurred_at)

          # Analyze pattern using pure algorithm
          pattern = Services::PatternDetector.analyze_cyclical_pattern(
            timestamps: timestamps,
            days: @days
          )

          # Detect bursts using pure algorithm
          burst_days = [ 7, @days ].min
          burst_timestamps = base_query.where(error_type: error_type, platform: platform)
                                       .where("occurred_at >= ?", burst_days.days.ago)
                                       .pluck(:occurred_at)
          bursts = Services::PatternDetector.detect_bursts(timestamps: burst_timestamps)

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
