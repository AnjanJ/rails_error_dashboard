# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Fetch errors with improved filtering for developers
    # Removes environment filtering (each env has separate DB)
    # Adds time-based, severity, and frequency filtering
    class ErrorsListV2
      def self.call(filters = {})
        new(filters).call
      end

      def initialize(filters = {})
        @filters = filters
      end

      def call
        query = ErrorLog.includes(:user).order(occurred_at: :desc)
        query = apply_filters(query)
        query
      end

      private

      def apply_filters(query)
        query = filter_by_timeframe(query)
        query = filter_by_error_type(query)
        query = filter_by_resolved(query)
        query = filter_by_platform(query)
        query = filter_by_severity(query)
        query = filter_by_frequency(query)
        query = filter_by_search(query)
        query
      end

      # Time-based filtering (more useful than environment)
      def filter_by_timeframe(query)
        return query unless @filters[:timeframe].present?

        case @filters[:timeframe]
        when "last_hour"
          query.where("occurred_at >= ?", 1.hour.ago)
        when "today"
          query.where("occurred_at >= ?", Time.current.beginning_of_day)
        when "yesterday"
          query.where("occurred_at >= ? AND occurred_at < ?",
                     1.day.ago.beginning_of_day,
                     Time.current.beginning_of_day)
        when "last_7_days"
          query.where("occurred_at >= ?", 7.days.ago)
        when "last_30_days"
          query.where("occurred_at >= ?", 30.days.ago)
        when "last_90_days"
          query.where("occurred_at >= ?", 90.days.ago)
        else
          query
        end
      end

      def filter_by_error_type(query)
        return query unless @filters[:error_type].present?

        query.where(error_type: @filters[:error_type])
      end

      def filter_by_resolved(query)
        return query unless @filters[:unresolved] == "true" || @filters[:unresolved] == true

        query.unresolved
      end

      def filter_by_platform(query)
        return query unless @filters[:platform].present?

        query.where(platform: @filters[:platform])
      end

      # Filter by severity (based on error type)
      def filter_by_severity(query)
        return query unless @filters[:severity].present?

        case @filters[:severity]
        when "critical"
          # Security, data loss, crashes
          critical_errors = [
            "SecurityError",
            "ActiveRecord::RecordInvalid",
            "NoMemoryError",
            "SystemStackError",
            "SignalException"
          ]
          query.where(error_type: critical_errors)
        when "high"
          # Business logic failures
          high_errors = [
            "ActiveRecord::RecordNotFound",
            "ArgumentError",
            "TypeError",
            "NoMethodError"
          ]
          query.where(error_type: high_errors)
        when "medium"
          # Validation, timeouts
          medium_errors = [
            "ActiveRecord::RecordInvalid",
            "Timeout::Error",
            "Net::ReadTimeout"
          ]
          query.where(error_type: medium_errors)
        else
          query
        end
      end

      # Filter by frequency (how often error occurs)
      def filter_by_frequency(query)
        return query unless @filters[:frequency].present?

        case @filters[:frequency]
        when "high"
          # Occurs more than 10 times
          query.where("occurrence_count > ?", 10)
        when "medium"
          # Occurs 3-10 times
          query.where("occurrence_count >= ? AND occurrence_count <= ?", 3, 10)
        when "low"
          # Occurs 1-2 times
          query.where("occurrence_count <= ?", 2)
        when "recurring"
          # Seen multiple times over more than 1 hour
          query.where("occurrence_count > ? AND (last_seen_at - first_seen_at) > ?",
                     1, 1.hour.to_i)
        else
          query
        end
      end

      def filter_by_search(query)
        return query unless @filters[:search].present?

        search_term = "%#{@filters[:search]}%"
        query.where("message ILIKE ? OR error_type ILIKE ? OR backtrace ILIKE ?",
                   search_term, search_term, search_term)
      end
    end
  end
end
