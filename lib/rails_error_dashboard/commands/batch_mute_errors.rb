# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Mute multiple errors at once
    class BatchMuteErrors
      def self.call(error_ids, muted_by: nil, reason: nil)
        new(error_ids, muted_by, reason).call
      end

      def initialize(error_ids, muted_by = nil, reason = nil)
        @error_ids = Array(error_ids).compact
        @muted_by = muted_by
        @reason = reason
      end

      def call
        return { success: false, count: 0, errors: [ "No error IDs provided" ] } if @error_ids.empty?

        errors = ErrorLog.where(id: @error_ids)

        muted_count = 0
        failed_ids = []
        muted_errors = []

        errors.each do |error|
          begin
            error.update!(
              muted: true,
              muted_at: Time.current,
              muted_by: @muted_by,
              muted_reason: @reason
            )
            muted_count += 1
            muted_errors << error
          rescue => e
            failed_ids << error.id
            RailsErrorDashboard::Logger.error("Failed to mute error #{error.id}: #{e.message}")
          end
        end

        PluginRegistry.dispatch(:on_errors_batch_muted, muted_errors) if muted_errors.any?

        {
          success: failed_ids.empty?,
          count: muted_count,
          total: @error_ids.size,
          failed_ids: failed_ids,
          errors: failed_ids.empty? ? [] : [ "Failed to mute #{failed_ids.size} error(s)" ]
        }
      rescue => e
        RailsErrorDashboard::Logger.error("Batch mute failed: #{e.message}")
        { success: false, count: 0, total: @error_ids.size, errors: [ e.message ] }
      end
    end
  end
end
