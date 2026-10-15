# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Find errors that occur together in time (co-occurring errors)
    #
    # This query analyzes error occurrences to find patterns of errors
    # that happen within the same time window, which can indicate:
    # - Cascading failures (one error causes another)
    # - Related errors from the same underlying issue
    # - Correlated errors from the same feature/endpoint
    #
    # @example Find errors that occur with NoMethodError
    #   co_occurring = CoOccurringErrors.call(error_log_id: 123, window_minutes: 5)
    #   co_occurring.each do |result|
    #     puts "#{result[:error].error_type} occurred #{result[:frequency]} times together"
    #   end
    class CoOccurringErrors
      # The newest occurrences of the target error that are compared. This
      # renders on every error page while the feature is on, and it used to run
      # one window query per lifetime occurrence: 50k occurrences, 50k queries.
      TARGET_OCCURRENCES = 500
      # At most this many occurrences of other errors are read for those windows
      NEARBY_OCCURRENCES = 20_000

      # Find co-occurring errors
      #
      # @param error_log_id [Integer] ID of target error
      # @param window_minutes [Integer] Time window in minutes (default: 5)
      # @param min_frequency [Integer] Minimum co-occurrence count (default: 2)
      # @param limit [Integer] Maximum number of results (default: 10)
      # @return [Array<Hash>] Array of {error: ErrorLog, frequency: Integer, avg_delay_seconds: Float}
      def self.call(error_log_id:, window_minutes: 5, min_frequency: 2, limit: 10)
        new(error_log_id, window_minutes: window_minutes, min_frequency: min_frequency, limit: limit).find_co_occurring
      end

      def initialize(error_log_id, window_minutes: 5, min_frequency: 2, limit: 10)
        @error_log_id = error_log_id
        @window_minutes = window_minutes.to_i
        @min_frequency = min_frequency.to_i
        @limit = limit.to_i
      end

      # Four queries however many occurrences there are: the target exists, its
      # newest occurrence times, other errors' occurrences in those windows, and
      # the co-occurring errors themselves.
      def find_co_occurring
        return [] unless ErrorLog.exists?(id: @error_log_id)

        targets = ErrorOccurrence.where(error_log_id: @error_log_id)
          .order(occurred_at: :desc).limit(TARGET_OCCURRENCES).pluck(:occurred_at).sort
        return [] if targets.empty?

        window = @window_minutes.minutes
        stats = Hash.new { |h, k| h[k] = { count: 0, delay_sum: 0.0 } }

        nearby_occurrences(merged_windows(targets, window)).each do |error_log_id, occurred_at|
          # Each target occurrence within the window of this one is a pair, as
          # before. Delay is negative when this error came first.
          index = targets.bsearch_index { |target| target >= occurred_at - window }
          next unless index

          while index < targets.size && targets[index] <= occurred_at + window
            stats[error_log_id][:count] += 1
            stats[error_log_id][:delay_sum] += (occurred_at - targets[index]).to_f
            index += 1
          end
        end

        frequent = stats.select { |_id, data| data[:count] >= @min_frequency }
        errors = ErrorLog.where(id: frequent.keys).index_by(&:id)

        results = frequent.filter_map do |error_log_id, data|
          error = errors[error_log_id] or next
          { error: error, frequency: data[:count], avg_delay_seconds: (data[:delay_sum] / data[:count]).round(2) }
        end

        # Sort by frequency (most common first) and limit results
        results.sort_by { |r| -r[:frequency] }.first(@limit)
      end

      private

      # The windows around each target time, overlapping ones merged, so a burst
      # of target occurrences becomes one range
      def merged_windows(targets, window)
        targets.each_with_object([]) do |target, ranges|
          from = target - window
          to = target + window
          if ranges.any? && from <= ranges.last[1]
            ranges.last[1] = to
          else
            ranges << [ from, to ]
          end
        end
      end

      # [error_log_id, occurred_at] for other errors' occurrences in any window
      def nearby_occurrences(ranges)
        column = "#{ErrorOccurrence.table_name}.occurred_at"
        in_a_window = ranges.map { "(#{column} BETWEEN ? AND ?)" }.join(" OR ")

        ErrorOccurrence
          .where.not(error_log_id: @error_log_id)
          .where(in_a_window, *ranges.flatten)
          .order(occurred_at: :desc)
          .limit(NEARBY_OCCURRENCES)
          .pluck(:error_log_id, :occurred_at)
      end
    end
  end
end
