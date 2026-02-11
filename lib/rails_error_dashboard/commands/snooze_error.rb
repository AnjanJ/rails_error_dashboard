# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Snooze an error for a given number of hours
    # This is a write operation that sets snoozed_until and optionally creates a comment
    class SnoozeError
      def self.call(error_id, hours:, reason: nil)
        new(error_id, hours, reason).call
      end

      def initialize(error_id, hours, reason)
        @error_id = error_id
        @hours = hours
        @reason = reason
      end

      def call
        error = ErrorLog.find(@error_id)
        snooze_until = @hours.hours.from_now

        # Store snooze reason in comments if provided
        if @reason.present?
          error.comments.create!(
            author_name: error.assigned_to || "System",
            body: "Snoozed for #{@hours} hours: #{@reason}"
          )
        end

        error.update!(snoozed_until: snooze_until)
        error
      end
    end
  end
end
