# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Rank errors by unique user impact — how many distinct users each error type affects.
    # Surfaces "this error affected 847 unique users" prominently.
    # An error hitting 1 user 1000 times is different from an error hitting 1000 users once.
    class UserImpactSummary
      def self.call(days = 30, application_id: nil)
        new(days, application_id: application_id).call
      end

      def initialize(days = 30, application_id: nil)
        @days = days
        @application_id = application_id
        @start_date = days.days.ago
      end

      def call
        all_entries = build_entries
        {
          entries: all_entries,
          summary: build_summary(all_entries)
        }
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] UserImpactSummary failed: #{e.class}: #{e.message}")
        empty_result
      end

      private

      def base_scope
        scope = ErrorLog.where("occurred_at >= ?", @start_date)
                        .where.not(user_id: nil)
        scope = scope.where(application_id: @application_id) if @application_id.present?
        scope
      end

      def build_entries
        # Distinct users per error type, from OCCURRENCE rows: the group's
        # user_id is overwritten by each new occurrence, so counting it
        # distinct across groups reported five users hitting one error as one.
        user_counts = distinct_users_by_type

        # EVENTS per type, not groups. occurrence_count is exact and includes
        # storm-shed events, which create no occurrence row.
        occurrence_counts = base_scope
          .group(:error_type)
          .sum(:occurrence_count)

        total_users = effective_total_users

        user_counts.map do |error_type, unique_users|
          occurrences = occurrence_counts[error_type] || 0
          sample = base_scope.where(error_type: error_type).order(occurred_at: :desc).first
          impact_pct = total_users && total_users > 0 ? (unique_users.to_f / total_users * 100).round(1) : nil

          {
            error_type: error_type,
            message: sample&.message.to_s.truncate(120),
            unique_users: unique_users,
            total_occurrences: occurrences,
            impact_percentage: impact_pct,
            severity: sample&.severity,
            last_seen: sample&.occurred_at,
            id: sample&.id
          }
        end.sort_by { |e| -e[:unique_users] }
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] UserImpactSummary.build_entries failed: #{e.class}: #{e.message}")
        []
      end

      def build_summary(entries)
        {
          total_error_types_with_users: entries.size,
          # Summing per-type distinct counts counted one user once per type
          # they hit. One distinct count across the whole window is the actual
          # number of people affected.
          total_unique_users_affected: total_distinct_users(entries),
          most_impactful: entries.first&.dig(:error_type),
          total_users: effective_total_users
        }
      end

      def occurrences_available?
        defined?(ErrorOccurrence) && ErrorOccurrence.table_exists?
      rescue StandardError
        false
      end

      # error_type => distinct users who actually experienced it.
      def distinct_users_by_type
        unless occurrences_available?
          return base_scope.group(:error_type).distinct.count(:user_id)
        end

        occurrences = ErrorOccurrence.table_name
        logs = ErrorLog.table_name
        scope = ErrorOccurrence.joins(:error_log)
                               .where("#{occurrences}.occurred_at >= ?", @start_date)
                               .where.not(occurrences => { user_id: nil })
        scope = scope.where(logs => { application_id: @application_id }) if @application_id.present?

        counts = scope.group("#{logs}.error_type").distinct.count("#{occurrences}.user_id")
        # An error whose events predate occurrence tracking still belongs in
        # the list; fall back to the group's own user for those types.
        fallback = base_scope.group(:error_type).distinct.count(:user_id)
        fallback.merge(counts) { |_type, old_count, new_count| [ old_count, new_count ].max }
      rescue StandardError
        base_scope.group(:error_type).distinct.count(:user_id)
      end

      # One distinct count over the whole window, not a sum of per-type counts.
      def total_distinct_users(entries)
        unless occurrences_available?
          return base_scope.distinct.count(:user_id)
        end

        occurrences = ErrorOccurrence.table_name
        logs = ErrorLog.table_name
        scope = ErrorOccurrence.joins(:error_log)
                               .where("#{occurrences}.occurred_at >= ?", @start_date)
                               .where.not(occurrences => { user_id: nil })
        scope = scope.where(logs => { application_id: @application_id }) if @application_id.present?

        [ scope.distinct.count("#{occurrences}.user_id"), entries.map { |e| e[:unique_users] }.max.to_i ].max
      rescue StandardError
        entries.sum { |e| e[:unique_users] }
      end

      def effective_total_users
        RailsErrorDashboard.configuration.effective_total_users
      rescue => e
        nil
      end

      def empty_result
        { entries: [], summary: { total_error_types_with_users: 0, total_unique_users_affected: 0, most_impactful: nil, total_users: nil } }
      end
    end
  end
end
