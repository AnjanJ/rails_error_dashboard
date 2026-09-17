# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Snooze an error for a given number of hours
    # This is a write operation that sets snoozed_until and optionally creates a comment
    # Returns {success: bool, error: ErrorLog}; a failure also carries
    # reason: :invalid_hours and writes nothing.
    class SnoozeError
      # 30 days. The form offers at most a week; the cap is for anything that
      # does not come from the form. Without one, a negative value "snoozed"
      # into the past and a huge one overflowed the timestamp.
      MAX_SNOOZE_HOURS = 720

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
        hours = whole_hours(@hours)

        unless hours && (1..MAX_SNOOZE_HOURS).cover?(hours)
          return { success: false, error: error, reason: :invalid_hours }
        end

        error.transaction do
          if @reason.present?
            error.comments.create!(
              author_name: error.assigned_to || "System",
              body: "Snoozed for #{hours} hours: #{@reason}"
            )
          end

          error.update!(snoozed_until: hours.hours.from_now)
        end

        { success: true, error: error }
      end

      private

      # An Integer, or a String that is one ("24"). Anything else -- a Float, a
      # nested parameter, "abc" -- is nil rather than a guess.
      def whole_hours(value)
        case value
        when Integer then value
        when String then Integer(value.strip, 10, exception: false)
        end
      end
    end
  end
end
