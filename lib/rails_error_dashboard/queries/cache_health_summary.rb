# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Aggregate cache health stats from breadcrumbs across all errors
    # Scans error_logs breadcrumbs JSON, runs CacheAnalyzer per error, collects per-error stats
    class CacheHealthSummary
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
          entries: aggregated_entries
        }
      end

      private

      def base_query
        scope = ErrorLog.where("occurred_at >= ?", @start_date)
                        .where.not(breadcrumbs: nil)
        scope = scope.where(application_id: @application_id) if @application_id.present?
        scope
      end

      def aggregated_entries
        results = []

        base_query.select(:id, :breadcrumbs, :occurred_at).find_each(batch_size: 500) do |error_log|
          crumbs = parse_breadcrumbs(error_log.breadcrumbs)
          next if crumbs.empty?

          analysis = Services::CacheAnalyzer.call(crumbs)
          next if analysis.nil?

          results << {
            error_id: error_log.id,
            reads: analysis[:reads],
            writes: analysis[:writes],
            hits: analysis[:hits],
            misses: analysis[:misses],
            hit_rate: analysis[:hit_rate],
            total_duration_ms: analysis[:total_duration_ms],
            slowest_message: analysis[:slowest]&.dig(:message),
            slowest_duration_ms: analysis[:slowest]&.dig(:duration_ms),
            occurred_at: error_log.occurred_at
          }
        end

        # Sort: nil hit_rate last, then by hit_rate asc (worst first)
        results.sort_by { |r| [ r[:hit_rate].nil? ? 1 : 0, r[:hit_rate] || 999 ] }
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] CacheHealthSummary query failed: #{e.class}: #{e.message}")
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
