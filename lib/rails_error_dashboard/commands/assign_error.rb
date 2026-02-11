# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Assign an error to a user
    # This is a write operation that updates assignment fields on an ErrorLog record
    class AssignError
      def self.call(error_id, assigned_to:)
        new(error_id, assigned_to).call
      end

      def initialize(error_id, assigned_to)
        @error_id = error_id
        @assigned_to = assigned_to
      end

      def call
        error = ErrorLog.find(@error_id)
        error.assign_to!(@assigned_to)
        error
      end
    end
  end
end
