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
        error.snooze!(@hours, reason: @reason)
        error
      end
    end
  end
end
