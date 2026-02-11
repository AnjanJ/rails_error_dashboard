# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Unsnooze an error (clear snoozed_until)
    # This is a write operation that clears the snoozed_until field on an ErrorLog record
    class UnsnoozeError
      def self.call(error_id)
        new(error_id).call
      end

      def initialize(error_id)
        @error_id = error_id
      end

      def call
        error = ErrorLog.find(@error_id)
        error.update!(snoozed_until: nil)
        error
      end
    end
  end
end
