# frozen_string_literal: true

module RailsErrorDashboard
  # Stores aggregated counts of raised-then-rescued exceptions per hourly bucket.
  #
  # Swallowed exceptions are raised but silently rescued, never reaching the error
  # dashboard. This table tracks raise/rescue counts keyed by exception class,
  # raise location, rescue location, and hourly period.
  #
  # A high rescue_count/raise_count ratio indicates exceptions being swallowed.
  class SwallowedException < ErrorLogsRecord
    self.table_name = "rails_error_dashboard_swallowed_exceptions"

    belongs_to :application, optional: true

    validates :exception_class, presence: true
    validates :raise_location, presence: true
    validates :period_hour, presence: true
    validates :raise_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :rescue_count, presence: true, numericality: { greater_than_or_equal_to: 0 }

    scope :for_application, ->(app_id) { where(application_id: app_id) }
    scope :since, ->(time) { where("period_hour >= ?", time) }
    scope :recent, -> { order(period_hour: :desc) }

    # Rescue ratio: fraction of raises that were rescued (0.0 to 1.0)
    def rescue_ratio
      return 0.0 if raise_count.zero?
      rescue_count.to_f / raise_count
    end

    # Whether this exception is considered "swallowed" (rescue ratio >= threshold)
    def swallowed?(threshold: nil)
      threshold ||= RailsErrorDashboard.configuration.swallowed_exception_threshold
      rescue_ratio >= threshold
    end
  end
end
