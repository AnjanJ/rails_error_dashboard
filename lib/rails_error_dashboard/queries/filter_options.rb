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
          error_types: ErrorLog.distinct.pluck(:error_type).compact.sort,
          platforms: ErrorLog.distinct.pluck(:platform).compact,
          applications: Application.ordered_by_name.pluck(:name, :id)
        }
      end
    end
  end
end
