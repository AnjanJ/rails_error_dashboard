# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Fetch available filter options
    # This is a read operation that returns distinct values for filters
    class FilterOptions
      def self.call
        new.call
      end

      def call
        {
          environments: ErrorLog.distinct.pluck(:environment).compact,
          error_types: ErrorLog.distinct.pluck(:error_type).compact.sort,
          platforms: ErrorLog.distinct.pluck(:platform).compact
        }
      end
    end
  end
end
