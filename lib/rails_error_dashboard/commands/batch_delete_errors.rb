# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Delete multiple errors at once
    # This is a write operation that destroys multiple ErrorLog records
    class BatchDeleteErrors
      def self.call(error_ids)
        new(error_ids).call
      end

      def initialize(error_ids)
        @error_ids = Array(error_ids).compact
      end

      def call
        return { success: false, count: 0, errors: [ "No error IDs provided" ] } if @error_ids.empty?

        errors = ErrorLog.where(id: @error_ids)
        count = errors.count
        error_ids_to_delete = errors.pluck(:id)

        errors.destroy_all

        # Dispatch plugin event for batch deleted errors
        PluginRegistry.dispatch(:on_errors_batch_deleted, error_ids_to_delete) if error_ids_to_delete.any?

        {
          success: true,
          count: count,
          total: @error_ids.size,
          errors: []
        }
      rescue => e
        Rails.logger.error("Batch delete failed: #{e.message}")
        { success: false, count: 0, total: @error_ids.size, errors: [ e.message ] }
      end
    end
  end
end
