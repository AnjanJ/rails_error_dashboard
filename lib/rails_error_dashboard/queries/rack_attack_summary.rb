# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Aggregate Rack Attack events from breadcrumbs across all errors
    # Scans error_logs breadcrumbs JSON, filters for "rack_attack" category crumbs,
    # and groups by rule name with counts, unique IPs, paths, and error associations.
    class RackAttackSummary
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
          events: aggregated_events
        }
      end

      private

      def base_query
        scope = ErrorLog.where("occurred_at >= ?", @start_date)
                        .where.not(breadcrumbs: nil)
        scope = scope.where(application_id: @application_id) if @application_id.present?
        scope
      end

      def aggregated_events
        results = {}

        base_query.select(:id, :breadcrumbs, :occurred_at).find_each(batch_size: 500) do |error_log|
          crumbs = parse_breadcrumbs(error_log.breadcrumbs)
          next if crumbs.empty?

          rack_attack_crumbs = crumbs.select { |c| c["c"] == "rack_attack" }
          next if rack_attack_crumbs.empty?

          rack_attack_crumbs.each do |crumb|
            meta = crumb["meta"] || {}
            rule = meta["rule"].to_s.presence || "unknown"

            if results[rule]
              results[rule][:count] += 1
              results[rule][:ips] << meta["discriminator"].to_s if meta["discriminator"].present?
              results[rule][:paths] << meta["path"].to_s if meta["path"].present?
              results[rule][:error_ids] << error_log.id
              results[rule][:last_seen] = [ results[rule][:last_seen], error_log.occurred_at ].compact.max
            else
              results[rule] = {
                rule: rule,
                match_type: meta["type"].to_s,
                count: 1,
                ips: Set.new([ meta["discriminator"].to_s ].reject(&:blank?)),
                paths: Set.new([ meta["path"].to_s ].reject(&:blank?)),
                error_ids: [ error_log.id ],
                last_seen: error_log.occurred_at
              }
            end
          end
        end

        results.values.each do |r|
          r[:error_ids] = r[:error_ids].uniq
          r[:error_count] = r[:error_ids].size
          r[:unique_ips] = r[:ips].size
          r[:top_path] = r[:paths].first
          r[:ips] = r[:ips].to_a
          r[:paths] = r[:paths].to_a
        end
        results.values.sort_by { |r| -r[:count] }
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] RackAttackSummary query failed: #{e.class}: #{e.message}")
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
