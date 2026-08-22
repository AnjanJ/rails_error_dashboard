# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Unmute multiple errors at once
    class BatchUnmuteErrors
      include RailsErrorDashboard::Translation

      def self.call(error_ids)
        new(error_ids).call
      end

      def initialize(error_ids)
        @error_ids = Array(error_ids).compact
      end

      def call
        return { success: false, count: 0, errors: [ red_t("red.commands.no_error_ids") ] } if @error_ids.empty?

        errors = ErrorLog.where(id: @error_ids)

        unmuted_count = 0
        failed_ids = []
        unmuted_errors = []

        errors.each do |error|
          begin
            error.update!(
              muted: false,
              muted_at: nil,
              muted_by: nil,
              muted_reason: nil
            )
            unmuted_count += 1
            unmuted_errors << error
          rescue => e
            failed_ids << error.id
            RailsErrorDashboard::Logger.error("Failed to unmute error #{error.id}: #{e.message}")
          end
        end

        PluginRegistry.dispatch(:on_errors_batch_unmuted, unmuted_errors) if unmuted_errors.any?

        {
          success: failed_ids.empty?,
          count: unmuted_count,
          total: @error_ids.size,
          failed_ids: failed_ids,
          errors: failed_ids.empty? ? [] : [ red_tp("red.commands.batch_failed.unmute", count: failed_ids.size) ]
        }
      rescue => e
        RailsErrorDashboard::Logger.error("Batch unmute failed: #{e.message}")
        { success: false, count: 0, total: @error_ids.size, errors: [ e.message ] }
      end
    end
  end
end
