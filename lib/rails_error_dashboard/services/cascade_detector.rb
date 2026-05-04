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

        # Pluck (error_log_id, occurred_at) for every occurrence in the window
        # ordered chronologically. Using pluck instead of loading full
        # ActiveRecord rows keeps memory bounded to ~16 bytes/row instead of
        # ~5KB/row, which matters because the host app schedules this job and
        # the lookback window may contain a lot of occurrences.
        start_time = @lookback_hours.hours.ago
        rows = ErrorOccurrence
          .where("occurred_at >= ?", start_time)
          .order(:occurred_at)
          .pluck(:error_log_id, :occurred_at)

        # Two-pointer sweep: occurrences are time-sorted, so for each parent we
        # only advance the child pointer forward through occurrences within the
        # detection window. O(N + pairs) instead of O(N) inner SQL queries.
        patterns_found = Hash.new { |h, k| h[k] = { delays: [], count: 0 } }

        rows.each_with_index do |(parent_id, parent_time), i|
          window_end = parent_time + DETECTION_WINDOW
          j = i + 1
          while j < rows.length
            child_id, child_time = rows[j]
            break if child_time > window_end

            # Match the original SQL `occurred_at > parent` — strict, so two
            # occurrences with identical timestamps don't form a cascade pair.
            if child_id != parent_id && child_time > parent_time
              key = [ parent_id, child_id ]
              patterns_found[key][:delays] << (child_time - parent_time).to_f
              patterns_found[key][:count] += 1
            end
            j += 1
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
