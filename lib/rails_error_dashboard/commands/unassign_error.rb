# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Unassign an error from its current user
    # This is a write operation that clears assignment fields on an ErrorLog record
    class UnassignError
      def self.call(error_id)
        new(error_id).call
      end

      def initialize(error_id)
        @error_id = error_id
      end

      def call
        error = ErrorLog.find(@error_id)
        error.unassign!
        error
      end
    end
  end
end
