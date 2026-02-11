# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Calculate and persist cascade probability for a pattern
    # Probability = (times child follows parent) / (total parent occurrences)
    class CalculateCascadeProbability
      def self.call(pattern)
        new(pattern).call
      end

      def initialize(pattern)
        @pattern = pattern
      end

      def call
        parent_occurrence_count = @pattern.parent_error.error_occurrences.count
        return if parent_occurrence_count.zero?

        @pattern.cascade_probability = (@pattern.frequency.to_f / parent_occurrence_count).round(3)
        @pattern.save

        @pattern
      end
    end
  end
end
