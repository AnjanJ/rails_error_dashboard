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
        # Cache key includes the days parameter and the cache generation
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
        # - The cache generation (bumped by user actions; see AnalyticsCacheManager).
        #   Captures do not bump it: they rely on the 5-minute TTL.
        # - Start date (ensures correct time window)
        [
          "analytics_stats",
          @days,
          @application_id || "all",
          Services::AnalyticsCacheManager.generation,
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
      # An ErrorLog row is a GROUP; its occurred_at is FIRST-SEEN and is never
      # rewritten when the error recurs.
      #
      #   EVENT figures  -> Queries::EventVolume, which counts occurrence rows
      #                     + storm buckets + the untracked remainder, each
      #                     against its OWN timestamp.
      #   GROUP figures  -> base_query, which selects groups by first-seen.
      #                     Correct here: a group is the thing that gets
      #                     resolved, and an event cannot be.
      #
      # Mixing them is what made this page disagree with the Overview: filtering
      # GROUPS by first-seen and then summing their LIFETIME occurrence_count
      # answers "how much total volume do the groups born in this window carry",
      # not "how many events happened in this window". A group first seen in
      # August that recurred today was excluded entirely, so the page reported
      # zero events while its own affected-users table listed the very event.
      def error_statistics
        {
          total: event_count,
          total_groups: base_query.count,
          unresolved: base_query.unresolved.count,
          resolved: base_query.resolved.count,
          by_type: volume.by_group_attribute(:error_type).sort_by { |_, count| -count }.to_h,
          by_day: volume.by_day.transform_keys(&:to_s),
          affected_users_incomplete: affected_users_incomplete?
        }
      end

      # One EventVolume for the window, reused by every EVENT figure below so
      # they cannot drift apart from each other or from the headline total.
      def volume
        @volume ||= Queries::EventVolume.new(base_scope, @start_date)
      end

      # Total EVENTS in the window. dashboard_stats.rb counts the same way,
      # through the same primitive -- that agreement is asserted by
      # spec/queries/overview_analytics_agreement_spec.rb.
      def event_count
        volume.count
      end

      def errors_over_time
        volume.by_day
      end

      # Top 10 by EVENTS. Deliberately a partial breakdown -- it does not sum
      # to the headline total, and the agreement spec treats it as such.
      def errors_by_type
        volume.by_group_attribute(:error_type)
              .sort_by { |_, count| -count }
              .first(10)
              .to_h
      end

      def errors_by_platform
        volume.by_group_attribute(:platform)
      end

      # NULL (captured before the column existed) is reported under :unknown
      # rather than dropped, so the chart's total still matches the period.
      def errors_by_environment
        return {} unless ErrorLog.column_names.include?("environment")

        volume.by_group_attribute(:environment).transform_keys { |env| env.nil? ? :unknown : env }
      end

      # Diurnal pattern: which hour of the day errors peak in, 0..23.
      #
      # Counted per EVENT against the event's own timestamp. Grouping ErrorLog
      # by its first-seen hour put a group's whole lifetime volume on the hour
      # it was first seen, so a recurrence never moved the curve.
      def errors_by_hour
        volume.by_hour_of_day
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
        # belongs in the table. The fallback covers ONLY groups with no
        # occurrence coverage at all in this window.
        #
        # It used to merge by taking the larger of the two counts per user, and
        # that overstated real users: the group's user_id is overwritten by
        # every new occurrence, so group_user_counts attributes a group's whole
        # lifetime count to whoever hit it LAST. For occurrences {A: 2, B: 1}
        # the group figure for B was 3, max kept 3, and the page reported five
        # events for a three-event group. A number that overstates a user's
        # events cannot be presented as an "at least" bound, so the uncovered
        # case is counted and the covered case is left to the occurrence rows.
        uncovered = uncovered_group_user_counts
        counts.merge(uncovered) { |_user, from_occurrences, from_groups| from_occurrences + from_groups }
      rescue StandardError
        group_user_counts
      end

      # GROUP-based on purpose: this is the fallback for groups with no
      # per-event record, where the group's own user_id and lifetime count are
      # the only evidence that exists. Routing it through EventVolume would be
      # wrong -- EventVolume counts events, and this needs the per-user split
      # that only the group row carries. See design.md D5.
      def group_user_counts
        base_query.where.not(user_id: nil).group(:user_id).sum(:occurrence_count)
      end

      # Groups in this window that have NO occurrence row at all: rows from
      # before occurrence tracking, and groups whose every event was shed by
      # storm protection. Their occurrence_count is the only evidence those
      # events happened, and the group's own user_id the only attribution
      # available -- a floor, which affected_users_incomplete? reports.
      #
      # A group with even one occurrence row is excluded: its per-event rows
      # are authoritative, and adding the group total on top is what produced
      # the overcount.
      def uncovered_group_user_counts
        covered = ErrorOccurrence.where(error_log_id: base_query.select(:id)).select(:error_log_id)

        base_query.where.not(user_id: nil)
                  .where.not(id: covered)
                  .group(:user_id)
                  .sum(:occurrence_count)
      rescue StandardError
        {}
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
        Queries::EventVolume.in_window(base_scope.where(platform: [ "iOS", "Android" ]), @start_date)
      end

      def api_errors_count
        Queries::EventVolume.in_window(
          base_scope.where("platform IS NULL OR platform = ?", "API"), @start_date
        )
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
