# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Resolve multiple errors at once
    # This is a write operation that updates multiple ErrorLog records
    class BatchResolveErrors
      def self.call(error_ids, resolved_by_name: nil, resolution_comment: nil)
        new(error_ids, resolved_by_name, resolution_comment).call
      end

      def initialize(error_ids, resolved_by_name = nil, resolution_comment = nil)
        @error_ids = Array(error_ids).compact
        @resolved_by_name = resolved_by_name
        @resolution_comment = resolution_comment
      end

      def call
        return { success: false, count: 0, errors: ["No error IDs provided"] } if @error_ids.empty?

        errors = ErrorLog.where(id: @error_ids)

        resolved_count = 0
        failed_ids = []

        errors.each do |error|
          begin
            error.update!(
              resolved: true,
              resolved_at: Time.current,
              resolved_by_name: @resolved_by_name,
              resolution_comment: @resolution_comment
            )
            resolved_count += 1
          rescue => e
            failed_ids << error.id
            Rails.logger.error("Failed to resolve error #{error.id}: #{e.message}")
          end
        end

        {
          success: failed_ids.empty?,
          count: resolved_count,
          total: @error_ids.size,
          failed_ids: failed_ids,
          errors: failed_ids.empty? ? [] : ["Failed to resolve #{failed_ids.size} error(s)"]
        }
      rescue => e
        Rails.logger.error("Batch resolve failed: #{e.message}")
        { success: false, count: 0, total: @error_ids.size, errors: [e.message] }
      end
    end
  end
end
