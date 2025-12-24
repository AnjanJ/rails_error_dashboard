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
        query = ErrorLog.includes(:user).order(occurred_at: :desc)
        query = apply_filters(query)
        query
      end

      private

      def apply_filters(query)
        query = filter_by_environment(query)
        query = filter_by_error_type(query)
        query = filter_by_resolved(query)
        query = filter_by_platform(query)
        query = filter_by_search(query)
        query
      end

      def filter_by_environment(query)
        return query unless @filters[:environment].present?

        query.where(environment: @filters[:environment])
      end

      def filter_by_error_type(query)
        return query unless @filters[:error_type].present?

        query.where(error_type: @filters[:error_type])
      end

      def filter_by_resolved(query)
        return query unless @filters[:unresolved] == 'true' || @filters[:unresolved] == true

        query.unresolved
      end

      def filter_by_platform(query)
        return query unless @filters[:platform].present?

        query.where(platform: @filters[:platform])
      end

      def filter_by_search(query)
        return query unless @filters[:search].present?

        query.where('message ILIKE ?', "%#{@filters[:search]}%")
      end
    end
  end
end
