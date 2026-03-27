# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Build a digest summary of error activity for a time period.
    # Aggregates stats from existing queries into a single hash suitable for email templates.
    #
    # @example
    #   DigestBuilder.call(period: :daily)
    #   # => { period: :daily, stats: { new_errors: 12, ... }, top_errors: [...], ... }
    class DigestBuilder
      PERIODS = {
        daily: { days: 1, label: "Last 24 hours" },
        weekly: { days: 7, label: "Last 7 days" }
      }.freeze

      def self.call(period: :daily, application_id: nil)
        new(period: period, application_id: application_id).call
      end

      def initialize(period: :daily, application_id: nil)
        @period = PERIODS.key?(period) ? period : :daily
        @days = PERIODS[@period][:days]
        @application_id = application_id
        @start_date = @days.days.ago
      end

      def call
        {
          period: @period,
          period_label: PERIODS[@period][:label],
          generated_at: Time.current,
          stats: build_stats,
          top_errors: top_errors,
          critical_unresolved: critical_unresolved,
          comparison: build_comparison
        }
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] DigestBuilder failed: #{e.class}: #{e.message}")
        empty_result
      end

      private

      def base_scope
        scope = ErrorLog.where("occurred_at >= ?", @start_date)
        scope = scope.where(application_id: @application_id) if @application_id.present?
        scope
      end

      def build_stats
        scope = base_scope

        new_errors = scope.where("occurrence_count <= 1").count
        total_occurrences = scope.sum(:occurrence_count)
        resolved = scope.where(resolved: true).count
        unresolved = scope.where(resolved: false).count
        # Severity is computed from error_type via SeverityClassifier (not a DB column).
        # Count critical+high by matching known error type patterns via SQL WHERE IN.
        critical_types = Services::SeverityClassifier::CRITICAL_ERROR_TYPES +
                         Services::SeverityClassifier::HIGH_SEVERITY_ERROR_TYPES
        critical_high = scope.where(error_type: critical_types).count

        total = resolved + unresolved
        resolution_rate = total > 0 ? (resolved.to_f / total * 100).round(1) : 0

        {
          new_errors: new_errors,
          total_occurrences: total_occurrences,
          resolved: resolved,
          unresolved: unresolved,
          critical_high: critical_high,
          resolution_rate: resolution_rate
        }
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] DigestBuilder.build_stats failed: #{e.class}: #{e.message}")
        { new_errors: 0, total_occurrences: 0, resolved: 0, unresolved: 0, critical_high: 0, resolution_rate: 0 }
      end

      def top_errors
        base_scope
          .where(resolved: false)
          .group(:error_type)
          .order("count_all DESC")
          .limit(5)
          .count
          .map do |error_type, count|
            sample = base_scope.where(error_type: error_type).order(occurred_at: :desc).first
            {
              error_type: error_type,
              message: sample&.message.to_s.truncate(100),
              count: count,
              id: sample&.id
            }
          end
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] DigestBuilder.top_errors failed: #{e.class}: #{e.message}")
        []
      end

      def critical_unresolved
        critical_types = Services::SeverityClassifier::CRITICAL_ERROR_TYPES +
                         Services::SeverityClassifier::HIGH_SEVERITY_ERROR_TYPES
        base_scope
          .where(resolved: false)
          .where(error_type: critical_types)
          .order(occurred_at: :desc)
          .limit(5)
          .map do |error|
            {
              error_type: error.error_type,
              message: error.message.to_s.truncate(100),
              severity: error.severity,
              id: error.id
            }
          end
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] DigestBuilder.critical_unresolved failed: #{e.class}: #{e.message}")
        []
      end

      def build_comparison
        previous_start = (@days * 2).days.ago
        previous_end = @start_date

        current_count = base_scope.count
        previous_scope = ErrorLog.where("occurred_at >= ? AND occurred_at < ?", previous_start, previous_end)
        previous_scope = previous_scope.where(application_id: @application_id) if @application_id.present?
        previous_count = previous_scope.count

        delta = current_count - previous_count
        percentage = previous_count > 0 ? ((delta.to_f / previous_count) * 100).round(1) : nil

        {
          current_count: current_count,
          previous_count: previous_count,
          error_delta: delta,
          error_delta_percentage: percentage
        }
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] DigestBuilder.build_comparison failed: #{e.class}: #{e.message}")
        { current_count: 0, previous_count: 0, error_delta: 0, error_delta_percentage: nil }
      end

      def empty_result
        {
          period: @period,
          period_label: PERIODS.dig(@period, :label) || "Unknown",
          generated_at: Time.current,
          stats: { new_errors: 0, total_occurrences: 0, resolved: 0, unresolved: 0, critical_high: 0, resolution_rate: 0 },
          top_errors: [],
          critical_unresolved: [],
          comparison: { current_count: 0, previous_count: 0, error_delta: 0, error_delta_percentage: nil }
        }
      end
    end
  end
end
