# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Resolve multiple errors at once
    # This is a write operation that updates multiple ErrorLog records
    class BatchResolveErrors
      include RailsErrorDashboard::Translation

      def self.call(error_ids, resolved_by_name: nil, resolution_comment: nil)
        new(error_ids, resolved_by_name, resolution_comment).call
      end

      def initialize(error_ids, resolved_by_name = nil, resolution_comment = nil)
        @error_ids = Array(error_ids).compact
        @resolved_by_name = resolved_by_name
        @resolution_comment = resolution_comment
      end

      def call
        return { success: false, count: 0, errors: [ red_t("red.commands.no_error_ids") ] } if @error_ids.empty?

        errors = ErrorLog.where(id: @error_ids)

        resolved_count = 0
        failed_ids = []
        failures = {}

        resolved_errors = []

        errors.each do |error|
          begin
            error.update!(
              resolved: true,
              resolved_at: Time.current,
              resolved_by_name: @resolved_by_name,
              resolution_comment: @resolution_comment,
              status: "resolved"
            )
            resolved_count += 1
            resolved_errors << error
          rescue => e
            failed_ids << error.id
            failures[error.id] = "#{e.class}: #{e.message}"
            # Rails.logger, not RED's logger: log_level defaults to :silent, and
            # this is the only record of why the row failed
            Rails.logger.warn("[RailsErrorDashboard] Failed to resolve error #{error.id}: #{e.class}: #{e.message}")
          end
        end

        Services::AnalyticsCacheManager.clear if resolved_count.positive?

        # Dispatch plugin event for batch resolved errors
        PluginRegistry.dispatch(:on_errors_batch_resolved, resolved_errors) if resolved_errors.any?

        # Each error resolved here is as resolved as one resolved on its own
        # page: the host's error_resolved callbacks (the issue tracker closes
        # the linked issue from one) and the instrumentation event fire per
        # error. Only the plugin event is batch-shaped, by design.
        resolved_errors.each do |error|
          Services::ResolutionCallbacks.call(error, resolved_by: @resolved_by_name)
        end

        {
          success: failed_ids.empty?,
          count: resolved_count,
          total: @error_ids.size,
          failed_ids: failed_ids,
          failures: failures,
          errors: failed_ids.empty? ? [] : [ "#{red_tp("red.commands.batch_failed.resolve", count: failed_ids.size)} (#{failed_ids.map { |id| "##{id}" }.join(", ")})" ]
        }
      rescue => e
        RailsErrorDashboard::Logger.error("Batch resolve failed: #{e.message}")
        { success: false, count: 0, total: @error_ids.size, errors: [ e.message ] }
      end
    end
  end
end
