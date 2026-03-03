# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Aggregate connection pool health stats from system_health across all errors
    # Scans error_logs system_health JSON, extracts connection_pool data per error
    class DatabaseHealthSummary
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
                        .where.not(system_health: nil)
        scope = scope.where(application_id: @application_id) if @application_id.present?
        scope
      end

      def aggregated_entries
        results = []

        base_query.select(:id, :error_type, :system_health, :occurred_at).find_each(batch_size: 500) do |error_log|
          health = parse_system_health(error_log.system_health)
          next if health.blank?

          pool = health["connection_pool"]
          next if pool.blank?

          results << build_entry(error_log, pool)
        end

        # Sort by stress score descending (worst first)
        results.sort_by { |r| -(r[:busy] + r[:dead] + r[:waiting]) }
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] DatabaseHealthSummary query failed: #{e.class}: #{e.message}")
        []
      end

      def build_entry(error_log, pool)
        size = pool["size"].to_i
        busy = pool["busy"].to_i
        dead = pool["dead"].to_i
        idle = pool["idle"].to_i
        waiting = pool["waiting"].to_i
        utilization = size > 0 ? (busy.to_f / size * 100).round(1) : 0.0

        {
          error_id: error_log.id,
          error_type: error_log.error_type,
          size: size,
          busy: busy,
          dead: dead,
          idle: idle,
          waiting: waiting,
          utilization: utilization,
          occurred_at: error_log.occurred_at
        }
      end

      def parse_system_health(raw)
        return nil if raw.blank?
        JSON.parse(raw)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
