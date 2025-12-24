# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Fetch dashboard statistics
    # This is a read operation that aggregates error data for the dashboard
    class DashboardStats
      def self.call
        new.call
      end

      def call
        {
          total_today: ErrorLog.where("occurred_at >= ?", Time.current.beginning_of_day).count,
          total_week: ErrorLog.where("occurred_at >= ?", 7.days.ago).count,
          total_month: ErrorLog.where("occurred_at >= ?", 30.days.ago).count,
          unresolved: ErrorLog.unresolved.count,
          resolved: ErrorLog.resolved.count,
          by_environment: ErrorLog.group(:environment).count,
          by_platform: ErrorLog.group(:platform).count,
          top_errors: top_errors
        }
      end

      private

      def top_errors
        ErrorLog.where("occurred_at >= ?", 7.days.ago)
                .group(:error_type)
                .count
                .sort_by { |_, count| -count }
                .first(10)
                .to_h
      end
    end
  end
end
