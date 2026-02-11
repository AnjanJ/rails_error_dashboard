# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Create or update a cascade pattern from detection results
    #
    # This consolidates all cascade pattern writes: find_or_initialize,
    # set frequency/delay, save, and calculate probability.
    # CascadeDetector (the service) handles pure detection logic and
    # delegates all persistence to this command.
    class UpsertCascadePattern
      def self.call(parent_error_id:, child_error_id:, frequency:, avg_delay_seconds:)
        new(parent_error_id: parent_error_id, child_error_id: child_error_id,
            frequency: frequency, avg_delay_seconds: avg_delay_seconds).call
      end

      def initialize(parent_error_id:, child_error_id:, frequency:, avg_delay_seconds:)
        @parent_error_id = parent_error_id
        @child_error_id = child_error_id
        @frequency = frequency
        @avg_delay_seconds = avg_delay_seconds
      end

      def call
        pattern = CascadePattern.find_or_initialize_by(
          parent_error_id: @parent_error_id,
          child_error_id: @child_error_id
        )

        is_new = pattern.new_record?

        if is_new
          pattern.frequency = @frequency
          pattern.avg_delay_seconds = @avg_delay_seconds
          pattern.last_detected_at = Time.current
          pattern.save
        else
          IncrementCascadeDetection.call(pattern, @avg_delay_seconds)
        end

        CalculateCascadeProbability.call(pattern)

        { pattern: pattern, created: is_new }
      end
    end
  end
end
