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
        # Group by error_type, count distinct users and total occurrences
        user_counts = base_scope
          .group(:error_type)
          .distinct
          .count(:user_id)

        occurrence_counts = base_scope
          .group(:error_type)
          .count

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
          total_unique_users_affected: entries.sum { |e| e[:unique_users] },
          most_impactful: entries.first&.dig(:error_type),
          total_users: effective_total_users
        }
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
