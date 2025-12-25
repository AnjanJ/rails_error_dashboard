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
        query = ErrorLog.order(occurred_at: :desc)
        # Only eager load user if User model exists
        query = query.includes(:user) if defined?(::User)
        query = apply_filters(query)
        query
      end

      private

      def apply_filters(query)
        query = filter_by_error_type(query)
        query = filter_by_resolved(query)
        query = filter_by_platform(query)
        query = filter_by_search(query)
        query = filter_by_severity(query)
        query
      end

      def filter_by_error_type(query)
        return query unless @filters[:error_type].present?

        query.where(error_type: @filters[:error_type])
      end

      def filter_by_resolved(query)
        # Default to unresolved only if no explicit filter is set
        # If unresolved param is explicitly "false" or "0", show all errors
        # Otherwise, default to showing only unresolved errors
        if @filters[:unresolved] == "false" || @filters[:unresolved] == "0"
          # Show all errors (resolved and unresolved)
          return query
        else
          # Default: show only unresolved errors
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
    end
  end
end
