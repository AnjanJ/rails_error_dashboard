# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Update the status of an error with optional comment
    # This is a write operation that validates transitions and updates status
    # Returns {success: bool, error: ErrorLog}
    class UpdateErrorStatus
      def self.call(error_id, status:, comment: nil)
        new(error_id, status, comment).call
      end

      def initialize(error_id, status, comment)
        @error_id = error_id
        @status = status
        @comment = comment
      end

      def call
        error = ErrorLog.find(@error_id)

        unless error.can_transition_to?(@status)
          return { success: false, error: error }
        end

        error.transaction do
          error.update!(status: @status)

          # Auto-resolve if status is "resolved"
          error.update!(resolved: true) if @status == "resolved"

          # Add comment about status change
          if @comment.present?
            error.comments.create!(
              author_name: error.assigned_to || "System",
              body: "Status changed to #{@status}: #{@comment}"
            )
          end
        end

        { success: true, error: error }
      end
    end
  end
end
