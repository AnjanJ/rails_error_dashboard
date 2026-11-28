# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Delete multiple errors at once
    # This is a write operation that deletes multiple ErrorLog records and
    # everything that references them
    class BatchDeleteErrors
      include RailsErrorDashboard::Translation

      def self.call(error_ids)
        new(error_ids).call
      end

      def initialize(error_ids)
        @error_ids = Array(error_ids).compact
      end

      def call
        return { success: false, count: 0, errors: [ red_t("red.commands.no_error_ids") ] } if @error_ids.empty?

        # The ids that are really there, so the plugins hear about those only.
        error_ids_to_delete = ErrorLog.where(id: @error_ids).pluck(:id)

        # Dependents first, each table 1,000 rows at a time, no row loaded: the
        # retention job's delete. destroy_all loaded every error, occurrence,
        # comment and cascade pattern, and deleted them one statement each.
        count = RetentionCleanupJob.delete_with_dependents(ErrorLog.where(id: error_ids_to_delete))
        Services::AnalyticsCacheManager.clear

        # Dispatch plugin event for batch deleted errors
        PluginRegistry.dispatch(:on_errors_batch_deleted, error_ids_to_delete) if error_ids_to_delete.any?

        {
          success: true,
          count: count,
          total: @error_ids.size,
          errors: []
        }
      rescue => e
        RailsErrorDashboard::Logger.error("Batch delete failed: #{e.message}")
        { success: false, count: 0, total: @error_ids.size, errors: [ e.message ] }
      end
    end
  end
end
