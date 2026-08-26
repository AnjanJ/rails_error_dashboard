# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Fetch available filter options
    # This is a read operation that returns distinct values for filters
    class FilterOptions
      def self.call(application_id: nil)
        new(application_id: application_id).call
      end

      def initialize(application_id: nil)
        @application_id = application_id
      end

      def call
        {
          error_types: base_scope.distinct.pluck(:error_type).compact.sort,
          platforms: base_scope.distinct.pluck(:platform).compact,
          environments: environments,
          applications: Application.ordered_by_name.pluck(:name, :id),
          assignees: assignees
        }
      end

      # Sorted so the select is stable between requests. Empty until the
      # environment migration has run, so the index simply shows no filter.
      def environments
        return [] unless ErrorLog.column_names.include?("environment")

        base_scope.distinct.pluck(:environment).compact.sort
      end

      def assignees
        base_scope.where.not(assigned_to: nil)
                  .select(:assigned_to)
                  .distinct
                  .pluck(:assigned_to)
                  .sort
      end

      private

      def base_scope
        scope = ErrorLog.all
        scope = scope.where(application_id: @application_id) if @application_id.present?
        scope
      end
    end
  end
end
