# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Analyze recurring and persistent errors
    # Returns data about high-frequency errors, persistent issues, and cyclical patterns
    class RecurringIssues
      def self.call(days = 30)
        new(days).call
      end

      def initialize(days = 30)
        @days = days
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

      def base_query
        ErrorLog.where("occurred_at >= ?", @start_date)
      end

      def high_frequency_errors
        # Errors with high occurrence count
        base_query
          .where("occurrence_count > ?", 10)
          .group(:error_type)
          .select("error_type,
                   SUM(occurrence_count) as total_occurrences,
                   MIN(first_seen_at) as first_occurrence,
                   MAX(last_seen_at) as last_occurrence,
                   COUNT(*) as unique_error_count")
          .order("total_occurrences DESC")
          .limit(10)
          .map do |error|
            first_seen = error.first_occurrence.is_a?(Time) ? error.first_occurrence : Time.parse(error.first_occurrence.to_s)
            last_seen = error.last_occurrence.is_a?(Time) ? error.last_occurrence : Time.parse(error.last_occurrence.to_s)

            {
              error_type: error.error_type,
              total_occurrences: error.total_occurrences,
              first_seen: first_seen,
              last_seen: last_seen,
              duration_days: ((last_seen - first_seen) / 1.day).round,
              still_active: last_seen > 24.hours.ago
            }
          end
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
          pattern = Services::PatternDetector.analyze_cyclical_pattern(
            error_type: error_type,
            platform: nil,
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
