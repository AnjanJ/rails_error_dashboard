# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Aggregate swallowed exception data across hourly buckets for dashboard display.
    #
    # Groups by (exception_class, raise_location, rescue_location) and sums raise/rescue counts.
    # Filters to entries with rescue_ratio >= threshold (i.e., likely swallowed).
    # Returns array of hashes sorted by total rescue count descending.
    class SwallowedExceptionSummary
      def self.call(days = 30, application_id: nil)
        new(days, application_id: application_id).call
      end

      def initialize(days = 30, application_id: nil)
        @days = days
        @application_id = application_id
        @start_date = days.days.ago.beginning_of_hour
        @threshold = RailsErrorDashboard.configuration.swallowed_exception_threshold
      end

      def call
        entries = aggregated_entries
        {
          entries: entries,
          summary: {
            total_swallowed_classes: entries.map { |e| e[:exception_class] }.uniq.size,
            total_rescue_count: entries.sum { |e| e[:rescue_count] },
            total_raise_count: entries.sum { |e| e[:raise_count] }
          }
        }
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] SwallowedExceptionSummary failed: #{e.class}: #{e.message}")
        { entries: [], summary: { total_swallowed_classes: 0, total_rescue_count: 0, total_raise_count: 0 } }
      end

      private

      def base_query
        return SwallowedException.none unless table_exists?

        scope = SwallowedException.since(@start_date)
        scope = scope.for_application(@application_id) if @application_id.present?
        scope
      end

      def aggregated_entries
        rows = base_query
          .group(:exception_class, :raise_location, :rescue_location)
          .select(
            :exception_class, :raise_location, :rescue_location,
            "SUM(raise_count) AS total_raise_count",
            "SUM(rescue_count) AS total_rescue_count",
            "MAX(last_seen_at) AS last_seen"
          )

        rows.filter_map do |row|
          raise_count = row.total_raise_count.to_i
          rescue_count = row.total_rescue_count.to_i
          ratio = raise_count > 0 ? (rescue_count.to_f / raise_count).round(4) : 0.0

          next unless ratio >= @threshold

          last_seen = row.last_seen
          last_seen = Time.zone.parse(last_seen) if last_seen.is_a?(String)

          {
            exception_class: row.exception_class,
            raise_location: row.raise_location,
            rescue_location: row.rescue_location,
            raise_count: raise_count,
            rescue_count: rescue_count,
            rescue_ratio: ratio,
            last_seen: last_seen
          }
        end.sort_by { |e| -e[:rescue_count] }
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] SwallowedExceptionSummary query failed: #{e.class}: #{e.message}")
        []
      end

      def table_exists?
        SwallowedException.table_exists?
      rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
        false
      end
    end
  end
end
