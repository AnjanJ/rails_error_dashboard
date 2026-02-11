# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Update a cascade pattern's stats when a new detection occurs
    # This is a write operation that increments frequency, recalculates average delay,
    # and updates last_detected_at timestamp.
    class IncrementCascadeDetection
      def self.call(pattern, delay_seconds)
        new(pattern, delay_seconds).call
      end

      def initialize(pattern, delay_seconds)
        @pattern = pattern
        @delay_seconds = delay_seconds
      end

      def call
        @pattern.frequency += 1

        # Update average delay using incremental formula
        if @pattern.avg_delay_seconds.present?
          @pattern.avg_delay_seconds = ((@pattern.avg_delay_seconds * (@pattern.frequency - 1)) + @delay_seconds) / @pattern.frequency
        else
          @pattern.avg_delay_seconds = @delay_seconds
        end

        @pattern.last_detected_at = Time.current
        @pattern.save

        @pattern
      end
    end
  end
end
