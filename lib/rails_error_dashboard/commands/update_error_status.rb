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
        success = error.update_status!(@status, comment: @comment)
        { success: success, error: error }
      end
    end
  end
end
