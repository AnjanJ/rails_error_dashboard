# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Aggregate ActionCable events from breadcrumbs across all errors
    # Scans error_logs breadcrumbs JSON, filters for "action_cable" category crumbs,
    # and groups by channel name with counts by event type.
    class ActionCableSummary
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
          channels: aggregated_channels
        }
      end

      private

      def base_query
        scope = ErrorLog.where("occurred_at >= ?", @start_date)
                        .where.not(breadcrumbs: nil)
        scope = scope.where(application_id: @application_id) if @application_id.present?
        scope
      end

      def aggregated_channels
        results = {}

        base_query.select(:id, :breadcrumbs, :occurred_at).find_each(batch_size: 500) do |error_log|
          crumbs = parse_breadcrumbs(error_log.breadcrumbs)
          next if crumbs.empty?

          ac_crumbs = crumbs.select { |c| c["c"] == "action_cable" }
          next if ac_crumbs.empty?

          ac_crumbs.each do |crumb|
            meta = crumb["meta"] || {}
            channel = meta["channel"].to_s.presence || "Unknown"
            event_type = meta["event_type"].to_s

            results[channel] ||= {
              channel: channel,
              perform_count: 0,
              transmit_count: 0,
              subscription_count: 0,
              rejection_count: 0,
              error_ids: [],
              last_seen: nil
            }

            entry = results[channel]

            case event_type
            when "perform_action"
              entry[:perform_count] += 1
            when "transmit"
              entry[:transmit_count] += 1
            when "transmit_subscription_confirmation"
              entry[:subscription_count] += 1
            when "transmit_subscription_rejection"
              entry[:rejection_count] += 1
            end

            entry[:error_ids] << error_log.id
            entry[:last_seen] = [ entry[:last_seen], error_log.occurred_at ].compact.max
          end
        end

        results.values.each do |r|
          r[:error_ids] = r[:error_ids].uniq
          r[:error_count] = r[:error_ids].size
          r[:total_events] = r[:perform_count] + r[:transmit_count] + r[:subscription_count] + r[:rejection_count]
        end
        results.values.sort_by { |r| [ -r[:rejection_count], -r[:total_events] ] }
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] ActionCableSummary query failed: #{e.class}: #{e.message}")
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
