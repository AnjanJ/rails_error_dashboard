# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Aggregate deprecation warnings from breadcrumbs across all errors
    # Scans error_logs breadcrumbs JSON, extracts deprecation crumbs, and groups by message+source
    class DeprecationWarnings
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
          deprecations: aggregated_deprecations
        }
      end

      private

      def base_query
        scope = ErrorLog.where("occurred_at >= ?", @start_date)
                        .where.not(breadcrumbs: nil)
        scope = scope.where(application_id: @application_id) if @application_id.present?
        scope
      end

      def aggregated_deprecations
        results = {}

        base_query.select(:id, :breadcrumbs, :occurred_at).find_each(batch_size: 500) do |error_log|
          crumbs = parse_breadcrumbs(error_log.breadcrumbs)
          next if crumbs.empty?

          crumbs.each do |crumb|
            next unless crumb["c"] == "deprecation"

            message = crumb["m"].to_s
            next if message.blank?

            source = crumb.dig("meta", "caller").to_s
            key = "#{message}|||#{source}"

            if results[key]
              results[key][:count] += 1
              results[key][:error_ids] << error_log.id
              results[key][:last_seen] = [ results[key][:last_seen], error_log.occurred_at ].compact.max
            else
              results[key] = {
                message: message,
                source: source.presence || "Unknown",
                count: 1,
                error_ids: [ error_log.id ],
                last_seen: error_log.occurred_at
              }
            end
          end
        end

        results.values.each { |r| r[:error_ids] = r[:error_ids].uniq }
        results.values.sort_by { |r| -r[:count] }
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] DeprecationWarnings query failed: #{e.class}: #{e.message}")
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
