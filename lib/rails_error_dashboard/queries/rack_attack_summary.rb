# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Aggregate Rack Attack events from the rack_attack_events table.
    #
    # Previously this scanned every error_log's breadcrumbs JSON in Ruby, which was
    # both expensive (full-table scan + JSON.parse per row) and incomplete (events
    # were only stored when an unrelated error happened to occur in the same
    # request). Events now have their own table, so this is indexed SQL.
    #
    # Returns rows grouped by rule with counts, unique discriminators (IPs),
    # the most frequent path, and last-seen timestamps.
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
          events: aggregated_events,
          overflow_count: overflow_count
        }
      end

      private

      def base_query
        scope = RackAttackEvent.where("period_hour >= ?", @start_date)
        scope = scope.for_application(@application_id) if @application_id.present?
        scope
      end

      # Counts dropped by the tracker's LRU eviction, kept out of the per-rule
      # listing (they belong to no single rule) but reported so the dashboard
      # never silently under-states volume.
      def overflow_count
        base_query.where(match_type: RackAttackEvent::OVERFLOW_MATCH_TYPE).sum(:event_count).to_i
      rescue => e
        0
      end

      def aggregated_events
        rows = base_query
          .where.not(match_type: RackAttackEvent::OVERFLOW_MATCH_TYPE)
          .pluck(
            :rule, :match_type, :discriminator, :path, :event_count, :last_seen_at,
            :period_hour, :user_agent
          )
        return [] if rows.empty?

        grouped = {}

        rows.each do |rule, match_type, discriminator, path, event_count, last_seen_at, period_hour, user_agent|
          key = rule.to_s.presence || "unknown"
          count = event_count.to_i
          seen_at = last_seen_at || period_hour

          entry = grouped[key] ||= {
            rule: key,
            match_type: match_type.to_s,
            count: 0,
            ips: Set.new,
            path_counts: Hash.new(0),
            agent_counts: Hash.new(0),
            ai_count: 0,
            last_seen: nil
          }

          entry[:count] += count
          entry[:ips] << discriminator.to_s if discriminator.present?
          entry[:path_counts][path.to_s] += count if path.present?
          if user_agent.present?
            agent = Services::AiAgentClassifier.name(user_agent) || user_agent.to_s
            entry[:agent_counts][agent] += count
            entry[:ai_count] += count if Services::AiAgentClassifier.ai?(user_agent)
          end
          entry[:last_seen] = [ entry[:last_seen], seen_at ].compact.max

          # Prefer the most severe match type when a rule spans several. A rule
          # that both tracks and blocks should surface as "blocklist".
          entry[:match_type] = match_type.to_s if severity(match_type) > severity(entry[:match_type])
        end

        grouped.values.each do |r|
          # "Top path" now means genuinely most-frequent, not first-seen.
          r[:top_path] = r[:path_counts].max_by { |_path, count| count }&.first
          r[:paths] = r[:path_counts].sort_by { |_p, c| -c }.map(&:first)
          r[:unique_ips] = r[:ips].size
          r[:ips] = r[:ips].to_a
          # Which client matched most often — the question unique_ips cannot
          # answer, because one AI agent is a whole fleet of addresses (#170).
          r[:top_agent] = r[:agent_counts].max_by { |_agent, count| count }&.first
          r[:agents] = r[:agent_counts].sort_by { |_a, c| -c }.map(&:first)
          r[:unique_agents] = r[:agent_counts].size
          # Distinct rate-limited clients is the meaningful figure here; the old
          # breadcrumb-derived :error_count no longer applies now that events are
          # stored independently of errors.
          r[:error_count] = 0
          r.delete(:path_counts)
          r.delete(:agent_counts)
        end

        grouped.values.sort_by { |r| -r[:count] }
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] RackAttackSummary query failed: #{e.class}: #{e.message}")
        []
      end

      # Ordering used to pick the most severe match type for a rule.
      def severity(match_type)
        case match_type.to_s
        when "blocklist" then 3
        when "throttle"  then 2
        when "track"     then 1
        else 0
        end
      end
    end
  end
end
