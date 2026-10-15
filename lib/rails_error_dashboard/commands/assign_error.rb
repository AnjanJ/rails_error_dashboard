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
          **status_attributes(error)
        )
        # The stat cards are cached; a reopened error must show up at once.
        Services::AnalyticsCacheManager.clear if error.saved_change_to_resolved?

        { success: true, error: error }
      end

      private

      # Assigning means someone is working on it, so the error moves to
      # in_progress. Doing that to a resolved error used to leave
      # resolved: true and resolved_at behind: a row that was in_progress to
      # the eye, resolved to the scopes, and matched by neither the unresolved
      # nor the resolved lookup, so its next recurrence opened a new row.
      # Assigning a resolved error reopens it. wont_fix is sticky (H-6): the
      # assignee is recorded and the status stays.
      def status_attributes(error)
        return {} if error.status == "wont_fix"

        attrs = { status: "in_progress" }
        if error.resolved? || error.status == "resolved"
          attrs[:resolved] = false
          attrs[:resolved_at] = nil
        end
        attrs
      end
    end
  end
end
