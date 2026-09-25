# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Analyze recurring and persistent errors
    # Returns data about high-frequency errors, persistent issues, and cyclical patterns
    class RecurringIssues
      # Minimum events IN THE WINDOW for a group to count as high frequency.
      HIGH_FREQUENCY_THRESHOLD = 10

      def self.call(days = 30, application_id: nil)
        new(days, application_id: application_id).call
      end

      def initialize(days = 30, application_id: nil)
        @days = days
        @application_id = application_id
        @start_date = days.days.ago
      end

      def call
        {
          high_frequency_errors: high_frequency_errors,
          persistent_errors: persistent_errors,
          cyclical_patterns: cyclical_patterns
        }
      end

      private

      # Every group of the application, NOT cut by date -- what EventVolume
      # must be handed, or it never sees an older group's recurrences.
      def app_scope
        scope = ErrorLog.all
        scope = scope.where(application_id: @application_id) if @application_id.present?
        scope
      end

      # Groups FIRST SEEN in the window, for the group lists below.
      def base_query
        app_scope.where("occurred_at >= ?", @start_date)
      end

      # EVENT figure: error types whose groups fired more than
      # HIGH_FREQUENCY_THRESHOLD times in the window, by events in the window.
      #
      # Selecting groups by first-seen and summing their LIFETIME
      # occurrence_count listed only errors born in the window -- a chronic
      # error that fired all month was never "high frequency" once it was a
      # month old. The threshold stays per group (not per type) so eleven
      # one-off groups of one type do not qualify; it now counts this window.
      def high_frequency_errors
        events_by_group = Queries::EventVolume.by_group_attribute(app_scope, :id, @start_date)
                                              .select { |_, count| count > HIGH_FREQUENCY_THRESHOLD }
        return [] if events_by_group.empty?

        groups = ErrorLog.where(id: events_by_group.keys)
                         .pluck(:id, :error_type, :first_seen_at, :last_seen_at, :occurred_at)

        groups.group_by { |_, error_type, *| error_type }
              .map do |error_type, rows|
                # first_seen_at/last_seen_at are NULL on rows from before those
                # columns; occurred_at is the only timestamp such a row has.
                first_seen = rows.map { |_, _, first, _, occurred| first || occurred }.min
                last_seen = rows.map { |_, _, _, last, occurred| last || occurred }.max

                {
                  error_type: error_type,
                  total_occurrences: rows.sum { |id, *| events_by_group[id] },
                  first_seen: first_seen,
                  last_seen: last_seen,
                  duration_days: ((last_seen - first_seen) / 1.day).round,
                  still_active: last_seen > 24.hours.ago
                }
              end
              .sort_by { |entry| [ -entry[:total_occurrences], entry[:error_type].to_s ] }
              .first(10)
      end

      def persistent_errors
        # Errors that have been unresolved for longest time
        base_query
          .where(resolved: false)
          .where("first_seen_at < ?", 7.days.ago)
          .order("first_seen_at ASC")
          .limit(10)
          .map do |error|
            {
              id: error.id,
              error_type: error.error_type,
              message: error.message.to_s.truncate(100),
              first_seen: error.first_seen_at,
              age_days: ((Time.current - error.first_seen_at) / 1.day).round,
              occurrence_count: error.occurrence_count,
              platform: error.platform
            }
          end
      end

      def cyclical_patterns
        # Use existing PatternDetector if available
        return {} unless defined?(Services::PatternDetector)

        top_error_types = base_query.group(:error_type).count.sort_by { |_, count| -count }.first(5).to_h.keys

        top_error_types.each_with_object({}) do |error_type, result|
          timestamps = base_query.where(error_type: error_type).pluck(:occurred_at)
          pattern = Services::PatternDetector.analyze_cyclical_pattern(
            timestamps: timestamps,
            days: @days
          )
          result[error_type] = pattern if pattern[:pattern_strength] > 0.6
        end
      rescue NameError
        {} # PatternDetector not available
      end
    end
  end
end
