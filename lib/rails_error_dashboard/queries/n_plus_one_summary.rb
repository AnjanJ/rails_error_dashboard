# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Aggregate N+1 query patterns from breadcrumbs across all errors
    # Scans error_logs breadcrumbs JSON, runs NplusOneDetector per error, and groups by fingerprint
    class NplusOneSummary
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
          patterns: aggregated_patterns
        }
      end

      private

      def base_query
        scope = ErrorLog.where("occurred_at >= ?", @start_date)
                        .where.not(breadcrumbs: nil)
        scope = scope.where(application_id: @application_id) if @application_id.present?
        scope
      end

      def aggregated_patterns
        results = {}

        base_query.select(:id, :breadcrumbs, :occurred_at).find_each(batch_size: 500) do |error_log|
          crumbs = parse_breadcrumbs(error_log.breadcrumbs)
          next if crumbs.empty?

          patterns = Services::NplusOneDetector.call(crumbs)
          next if patterns.empty?

          patterns.each do |pattern|
            fingerprint = pattern[:fingerprint]

            if results[fingerprint]
              results[fingerprint][:count] += pattern[:count]
              results[fingerprint][:total_duration_ms] += pattern[:total_duration_ms]
              results[fingerprint][:error_ids] << error_log.id
              results[fingerprint][:last_seen] = [ results[fingerprint][:last_seen], error_log.occurred_at ].compact.max
            else
              results[fingerprint] = {
                fingerprint: fingerprint,
                sample_query: pattern[:sample_query],
                count: pattern[:count],
                error_ids: [ error_log.id ],
                total_duration_ms: pattern[:total_duration_ms],
                last_seen: error_log.occurred_at
              }
            end
          end
        end

        results.values.each do |r|
          r[:error_ids] = r[:error_ids].uniq
          r[:error_count] = r[:error_ids].size
          r[:total_duration_ms] = r[:total_duration_ms].round(2)
        end
        results.values.sort_by { |r| -r[:count] }
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] NplusOneSummary query failed: #{e.class}: #{e.message}")
        []
      end

      def parse_breadcrumbs(raw)
        return [] if raw.blank?
        JSON.parse(raw)
      rescue JSON::ParserError
        []
      end
    end
  end
end
