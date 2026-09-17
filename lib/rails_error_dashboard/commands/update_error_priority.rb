# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Update the priority level of an error
    # This is a write operation that updates the priority_level field on an ErrorLog record
    # Returns {success: bool, error: ErrorLog}; a failure also carries
    # reason: :invalid_priority and leaves the existing priority alone.
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
        level = whole_number(@priority_level)

        # The column is an integer, so an unchecked "x" was cast and stored as
        # 0 -- silently replacing a real priority with Low.
        unless ErrorLog::PRIORITY_LEVELS.key?(level)
          return { success: false, error: error, reason: :invalid_priority }
        end

        error.update!(priority_level: level)
        { success: true, error: error }
      end

      private

      # An Integer, or a String that is one ("3"). A nested parameter, a Float
      # or free text is nil.
      def whole_number(value)
        case value
        when Integer then value
        when String then Integer(value.strip, 10, exception: false)
        end
      end
    end
  end
end
