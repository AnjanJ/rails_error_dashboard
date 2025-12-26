# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Fetch errors with filtering and pagination
    # This is a read operation that returns a filtered collection of errors
    class ErrorsList
      def self.call(filters = {})
        new(filters).call
      end

      def initialize(filters = {})
        @filters = filters
      end

      def call
        query = ErrorLog
        # Only eager load user if User model exists
        query = query.includes(:user) if defined?(::User)
        query = apply_filters(query)
        query = apply_sorting(query)
        query
      end

      private

      def apply_filters(query)
        query = filter_by_error_type(query)
        query = filter_by_resolved(query)
        query = filter_by_platform(query)
        query = filter_by_search(query)
        query = filter_by_severity(query)
        query = filter_by_timeframe(query)
        query = filter_by_frequency(query)
        # Phase 3: Workflow filters
        query = filter_by_status(query)
        query = filter_by_assignment(query)
        query = filter_by_priority(query)
        query = filter_by_snoozed(query)
        query
      end

      def filter_by_error_type(query)
        return query unless @filters[:error_type].present?

        query.where(error_type: @filters[:error_type])
      end

      def filter_by_resolved(query)
        # Handle unresolved filter with explicit true/false values
        # When checkbox is unchecked: unresolved=false → show all errors
        # When checkbox is checked: unresolved=true → show only unresolved errors
        # When no filter: nil → default to unresolved only

        case @filters[:unresolved]
        when false, "false", "0"
          # Explicitly show all errors (resolved and unresolved)
          query
        when true, "true", "1"
          # Explicitly show only unresolved errors
          query.unresolved
        when nil, ""
          # Default: show only unresolved errors when no filter is set
          query.unresolved
        else
          # Fallback: show only unresolved errors
          query.unresolved
        end
      end

      def filter_by_platform(query)
        return query unless @filters[:platform].present?

        query.where(platform: @filters[:platform])
      end

      def filter_by_search(query)
        return query unless @filters[:search].present?

        # Use PostgreSQL full-text search if available (much faster with GIN index)
        # Otherwise fall back to LIKE query
        if postgresql?
          # Use to_tsquery for full-text search with GIN index
          # This is dramatically faster on large datasets
          search_term = @filters[:search].split.map { |word| "#{word}:*" }.join(" & ")
          query.where("to_tsvector('english', message) @@ to_tsquery('english', ?)", search_term)
        else
          # Fall back to LIKE for SQLite/MySQL
          # Use LOWER() for case-insensitive search
          query.where("LOWER(message) LIKE LOWER(?)", "%#{@filters[:search]}%")
        end
      end

      def postgresql?
        ActiveRecord::Base.connection.adapter_name.downcase == "postgresql"
      end

      def filter_by_severity(query)
        return query unless @filters[:severity].present?

        # Map severity levels to error types
        error_types = case @filters[:severity].to_sym
        when :critical
          ErrorLog::CRITICAL_ERROR_TYPES
        when :high
          ErrorLog::HIGH_SEVERITY_ERROR_TYPES
        when :medium
          ErrorLog::MEDIUM_SEVERITY_ERROR_TYPES
        when :low
          # Low severity = everything NOT in the other categories
          all_categorized = ErrorLog::CRITICAL_ERROR_TYPES +
                           ErrorLog::HIGH_SEVERITY_ERROR_TYPES +
                           ErrorLog::MEDIUM_SEVERITY_ERROR_TYPES
          # Use NOT IN to filter out categorized errors
          return query.where.not(error_type: all_categorized)
        else
          return query
        end

        query.where(error_type: error_types)
      end

      # Phase 3: Workflow filter methods

      def filter_by_status(query)
        return query unless @filters[:status].present?
        return query unless ErrorLog.column_names.include?("status")

        query.by_status(@filters[:status])
      end

      def filter_by_assignment(query)
        return query unless @filters[:assigned_to].present?
        return query unless ErrorLog.column_names.include?("assigned_to")

        case @filters[:assigned_to]
        when "__unassigned__"
          query.unassigned
        when "__assigned__"
          query.assigned
        else
          query.by_assignee(@filters[:assigned_to])
        end
      end

      def filter_by_priority(query)
        return query unless @filters[:priority_level].present?
        return query unless ErrorLog.column_names.include?("priority_level")

        query.by_priority(@filters[:priority_level])
      end

      def filter_by_snoozed(query)
        return query unless ErrorLog.column_names.include?("snoozed_until")

        # If hide_snoozed is checked, exclude snoozed errors
        if @filters[:hide_snoozed] == "1" || @filters[:hide_snoozed] == true
          query.active
        else
          query
        end
      end

      def filter_by_timeframe(query)
        return query unless @filters[:timeframe].present?

        case @filters[:timeframe]
        when "last_hour"
          query.where("occurred_at >= ?", 1.hour.ago)
        when "today"
          query.where("occurred_at >= ?", Time.current.beginning_of_day)
        when "yesterday"
          query.where("occurred_at BETWEEN ? AND ?",
                      1.day.ago.beginning_of_day,
                      1.day.ago.end_of_day)
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

      def filter_by_frequency(query)
        return query unless @filters[:frequency].present?

        case @filters[:frequency]
        when "once"
          query.where(occurrence_count: 1)
        when "few"
          query.where("occurrence_count BETWEEN ? AND ?", 2, 9)
        when "frequent"
          query.where("occurrence_count BETWEEN ? AND ?", 10, 99)
        when "very_frequent"
          query.where("occurrence_count >= ?", 100)
        when "recurring"
          # Errors that occurred multiple times AND are still active
          query.where("occurrence_count > ?", 5)
               .where("last_seen_at > ?", 24.hours.ago)
        else
          query
        end
      end

      def apply_sorting(query)
        sort_column = @filters[:sort_by].presence || "occurred_at"
        sort_direction = @filters[:sort_direction].presence || "desc"

        # Validate sort direction
        sort_direction = %w[asc desc].include?(sort_direction) ? sort_direction : "desc"

        # Map severity to priority for sorting (since severity is an enum/method)
        # We'll use priority_score which factors in severity
        case sort_column
        when "occurred_at", "first_seen_at", "last_seen_at", "created_at", "resolved_at"
          query.order(sort_column => sort_direction)
        when "occurrence_count", "priority_score"
          query.order(sort_column => sort_direction, occurred_at: :desc)
        when "error_type", "platform", "app_version"
          query.order(sort_column => sort_direction, occurred_at: :desc)
        when "severity"
          # Sort by priority_score as proxy for severity (critical=highest score)
          query.order(priority_score: sort_direction, occurred_at: :desc)
        else
          # Default sort
          query.order(occurred_at: :desc)
        end
      end
    end
  end
end
