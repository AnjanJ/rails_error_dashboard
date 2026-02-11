# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Detects cascade patterns by analyzing error occurrences
    #
    # Runs periodically to find errors that consistently follow other errors,
    # indicating a causal relationship.
    class CascadeDetector
      # Time window to look for cascades (errors within this window may be related)
      DETECTION_WINDOW = 60.seconds

      # Minimum times a pattern must occur to be considered a cascade
      MIN_CASCADE_FREQUENCY = 3

      # Minimum probability threshold (% of time parent leads to child)
      MIN_CASCADE_PROBABILITY = 0.7

      def self.call(lookback_hours: 24)
        new(lookback_hours: lookback_hours).detect_cascades
      end

      def initialize(lookback_hours: 24)
        @lookback_hours = lookback_hours
        @detected_count = 0
      end

      def detect_cascades
        return { detected: 0, updated: 0 } unless can_detect?

        # Get recent error occurrences
        start_time = @lookback_hours.hours.ago
        occurrences = ErrorOccurrence.where("occurred_at >= ?", start_time).order(:occurred_at)

        # For each error occurrence, find potential children
        patterns_found = Hash.new { |h, k| h[k] = { delays: [], count: 0 } }

        occurrences.each do |parent_occ|
          # Find occurrences within detection window
          potential_children = ErrorOccurrence
            .where("occurred_at > ? AND occurred_at <= ?",
                   parent_occ.occurred_at,
                   parent_occ.occurred_at + DETECTION_WINDOW)
            .where.not(error_log_id: parent_occ.error_log_id)

          potential_children.each do |child_occ|
            key = [ parent_occ.error_log_id, child_occ.error_log_id ]
            delay = (child_occ.occurred_at - parent_occ.occurred_at).to_f

            patterns_found[key][:delays] << delay
            patterns_found[key][:count] += 1
          end
        end

        # Filter and persist cascade patterns via Command
        updated_count = 0
        patterns_found.each do |(parent_id, child_id), data|
          next if data[:count] < MIN_CASCADE_FREQUENCY

          avg_delay = data[:delays].sum / data[:delays].size

          result = Commands::UpsertCascadePattern.call(
            parent_error_id: parent_id,
            child_error_id: child_id,
            frequency: data[:count],
            avg_delay_seconds: avg_delay
          )

          if result[:created]
            @detected_count += 1
          else
            updated_count += 1
          end
        end

        { detected: @detected_count, updated: updated_count }
      end

      private

      def can_detect?
        defined?(CascadePattern) && CascadePattern.table_exists? &&
        defined?(ErrorOccurrence) && ErrorOccurrence.table_exists?
      end
    end
  end
end
