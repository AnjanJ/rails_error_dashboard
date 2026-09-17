# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Assign an error to a user
    # This is a write operation that updates assignment fields on an ErrorLog record
    # Returns {success: bool, error: ErrorLog}; a failure also carries
    # reason: :blank_assignee and writes nothing.
    class AssignError
      MAX_ASSIGNEE_LENGTH = 255

      def self.call(error_id, assigned_to:)
        new(error_id, assigned_to).call
      end

      def initialize(error_id, assigned_to)
        @error_id = error_id
        @assigned_to = assigned_to
      end

      def call
        error = ErrorLog.find(@error_id)

        # A blank name used to "assign" the error to nobody and still move it to
        # in_progress. A nested parameter is not a name either.
        assignee = @assigned_to.is_a?(String) ? @assigned_to.strip.presence : nil
        return { success: false, error: error, reason: :blank_assignee } unless assignee

        error.update!(
          assigned_to: assignee.truncate(MAX_ASSIGNEE_LENGTH, omission: ""),
          assigned_at: Time.current,
          status: "in_progress" # Auto-transition to in_progress when assigned
        )
        { success: true, error: error }
      end
    end
  end
end
