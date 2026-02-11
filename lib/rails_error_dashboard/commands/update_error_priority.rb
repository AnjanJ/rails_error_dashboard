# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Update the priority level of an error
    # This is a write operation that updates the priority_level field on an ErrorLog record
    class UpdateErrorPriority
      def self.call(error_id, priority_level:)
        new(error_id, priority_level).call
      end

      def initialize(error_id, priority_level)
        @error_id = error_id
        @priority_level = priority_level
      end

      def call
        error = ErrorLog.find(@error_id)
        error.update!(priority_level: @priority_level)
        error
      end
    end
  end
end
