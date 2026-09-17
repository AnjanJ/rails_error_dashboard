# frozen_string_literal: true

module RailsErrorDashboard
  # Stores baseline statistics for error types
  #
  # Baselines are calculated periodically (hourly, daily, weekly) to establish
  # "normal" error behavior. This enables anomaly detection by comparing current
  # error counts against historical baselines.
  #
  # @attr error_type [String] The type of error (e.g., "NoMethodError")
  # @attr platform [String] Platform (iOS, Android, API, Web)
  # @attr baseline_type [String] Time period type (hourly, daily, weekly)
  # @attr period_start [DateTime] Start of the period this baseline covers
  # @attr period_end [DateTime] End of the period this baseline covers
  # @attr count [Integer] Total errors in this period
  # @attr mean [Float] Average error count
  # @attr std_dev [Float] Standard deviation
  # @attr percentile_95 [Float] 95th percentile
  # @attr percentile_99 [Float] 99th percentile
  # @attr sample_size [Integer] Number of periods in the sample
  class ErrorBaseline < ErrorLogsRecord
    self.table_name = "rails_error_dashboard_error_baselines"

    BASELINE_TYPES = %w[hourly daily weekly].freeze

    validates :error_type, presence: true
    validates :platform, presence: true
    validates :baseline_type, presence: true, inclusion: { in: BASELINE_TYPES }
    validates :period_start, presence: true
    validates :period_end, presence: true
    validates :count, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :sample_size, presence: true, numericality: { greater_than_or_equal_to: 0 }

    validate :period_end_after_period_start

    scope :for_error_type, ->(error_type) { where(error_type: error_type) }
    scope :for_platform, ->(platform) { where(platform: platform) }
    scope :hourly, -> { where(baseline_type: "hourly") }
    scope :daily, -> { where(baseline_type: "daily") }
    scope :weekly, -> { where(baseline_type: "weekly") }
    scope :recent, -> { order(period_start: :desc) }

    # Check if a given count is anomalous compared to this baseline
    # @param current_count [Integer] Current error count to check
    # @param sensitivity [Integer] Number of standard deviations (default: 2)
    # @return [Symbol, nil] :elevated, :high, :critical, or nil if normal
    def anomaly_level(current_count, sensitivity: 2)
      return nil if mean.nil? || std_dev.nil?
      return nil if current_count <= mean

      # nil when std_dev is zero: a perfectly flat history has no spread to
      # measure against, and dividing by it made every count :critical.
      sigma = std_devs_above_mean(current_count)
      return nil if sigma.nil?

      # Half-open bands, highest first: a boundary value belongs to the band it
      # opens (3.0 is :high, 4.0 is :critical). Inclusive ranges matched
      # top-down gave each boundary to the band below it.
      if sigma >= sensitivity + 2
        :critical
      elsif sigma >= sensitivity + 1
        :high
      elsif sigma >= sensitivity
        :elevated
      end
    end

    # Check if current count is above baseline
    # @param current_count [Integer] Current error count
    # @param sensitivity [Integer] Number of standard deviations (default: 2)
    # @return [Boolean] True if count exceeds baseline + (sensitivity * std_dev)
    def exceeds_baseline?(current_count, sensitivity: 2)
      return false if mean.nil? || std_dev.nil?
      current_count > (mean + (sensitivity * std_dev))
    end

    # Get the threshold for anomaly detection
    # @param sensitivity [Integer] Number of standard deviations (default: 2)
    # @return [Float, nil] Threshold value or nil if stats not available
    def threshold(sensitivity: 2)
      return nil if mean.nil? || std_dev.nil?
      mean + (sensitivity * std_dev)
    end

    # Calculate how many standard deviations above mean
    # @param current_count [Integer] Current error count
    # @return [Float, nil] Number of standard deviations or nil
    def std_devs_above_mean(current_count)
      return nil if mean.nil? || std_dev.nil? || std_dev.zero?
      (current_count - mean) / std_dev
    end

    private

    def period_end_after_period_start
      return if period_start.nil? || period_end.nil?

      if period_end <= period_start
        errors.add(:period_end, "must be after period_start")
      end
    end
  end
end
