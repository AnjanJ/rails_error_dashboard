# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Aggregate job queue health stats from system_health across all errors
    # Scans error_logs system_health JSON, extracts job_queue data per error
    class JobHealthSummary
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

        base_query.select(:id, :system_health, :occurred_at).find_each(batch_size: 500) do |error_log|
          health = parse_system_health(error_log.system_health)
          next if health.blank?

          job_queue = health["job_queue"]
          next if job_queue.blank?

          adapter = job_queue["adapter"]
          next if adapter.blank?

          results << build_entry(error_log, job_queue, adapter)
        end

        # Sort by failed count descending (worst first)
        results.sort_by { |r| -(r[:failed] || 0) }
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] JobHealthSummary query failed: #{e.class}: #{e.message}")
        []
      end

      def build_entry(error_log, job_queue, adapter)
        entry = {
          error_id: error_log.id,
          adapter: adapter,
          occurred_at: error_log.occurred_at
        }

        case adapter
        when "sidekiq"
          entry.merge!(
            enqueued: job_queue["enqueued"],
            processed: job_queue["processed"],
            failed: job_queue["failed"],
            dead: job_queue["dead"],
            scheduled: job_queue["scheduled"],
            retry: job_queue["retry"],
            workers: job_queue["workers"]
          )
        when "solid_queue"
          entry.merge!(
            ready: job_queue["ready"],
            scheduled: job_queue["scheduled"],
            claimed: job_queue["claimed"],
            failed: job_queue["failed"],
            blocked: job_queue["blocked"]
          )
        when "good_job"
          entry.merge!(
            queued: job_queue["queued"],
            errored: job_queue["errored"],
            finished: job_queue["finished"]
          )
        end

        entry
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
