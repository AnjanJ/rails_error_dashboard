# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Mute multiple errors at once
    class BatchMuteErrors
      include RailsErrorDashboard::Translation

      def self.call(error_ids, muted_by: nil, reason: nil)
        new(error_ids, muted_by, reason).call
      end

      def initialize(error_ids, muted_by = nil, reason = nil)
        @error_ids = Array(error_ids).compact
        @muted_by = muted_by
        @reason = reason
      end

      def call
        return { success: false, count: 0, errors: [ red_t("red.commands.no_error_ids") ] } if @error_ids.empty?

        errors = ErrorLog.where(id: @error_ids)

        muted_count = 0
        failed_ids = []
        failures = {}
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
            failures[error.id] = "#{e.class}: #{e.message}"
            # Rails.logger, not RED's logger: log_level defaults to :silent, and
            # this is the only record of why the row failed
            Rails.logger.warn("[RailsErrorDashboard] Failed to mute error #{error.id}: #{e.class}: #{e.message}")
          end
        end

        Services::AnalyticsCacheManager.clear if muted_count.positive?

        PluginRegistry.dispatch(:on_errors_batch_muted, muted_errors) if muted_errors.any?

        {
          success: failed_ids.empty?,
          count: muted_count,
          total: @error_ids.size,
          failed_ids: failed_ids,
          failures: failures,
          errors: failed_ids.empty? ? [] : [ "#{red_tp("red.commands.batch_failed.mute", count: failed_ids.size)} (#{failed_ids.map { |id| "##{id}" }.join(", ")})" ]
        }
      rescue => e
        RailsErrorDashboard::Logger.error("Batch mute failed: #{e.message}")
        { success: false, count: 0, total: @error_ids.size, errors: [ e.message ] }
      end
    end
  end
end
