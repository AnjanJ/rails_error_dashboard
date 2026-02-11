# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Create or update an error baseline record
    #
    # Handles the persistence of baseline statistics calculated by
    # Services::BaselineCalculator. The calculator handles querying
    # and pure statistics; this command handles all writes.
    class UpsertBaseline
      def self.call(error_type:, platform:, baseline_type:, period_start:, period_end:, stats:, count:, sample_size:)
        new(
          error_type: error_type, platform: platform, baseline_type: baseline_type,
          period_start: period_start, period_end: period_end,
          stats: stats, count: count, sample_size: sample_size
        ).call
      end

      def initialize(error_type:, platform:, baseline_type:, period_start:, period_end:, stats:, count:, sample_size:)
        @error_type = error_type
        @platform = platform
        @baseline_type = baseline_type
        @period_start = period_start
        @period_end = period_end
        @stats = stats
        @count = count
        @sample_size = sample_size
      end

      def call
        baseline = ErrorBaseline.find_or_initialize_by(
          error_type: @error_type,
          platform: @platform,
          baseline_type: @baseline_type,
          period_start: @period_start
        )

        baseline.update!(
          period_end: @period_end,
          count: @count,
          mean: @stats[:mean],
          std_dev: @stats[:std_dev],
          percentile_95: @stats[:percentile_95],
          percentile_99: @stats[:percentile_99],
          sample_size: @sample_size
        )

        baseline
      end
    end
  end
end
