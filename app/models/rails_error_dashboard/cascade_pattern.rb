# frozen_string_literal: true

module RailsErrorDashboard
  # Tracks cascade patterns where one error causes another
  #
  # A cascade pattern represents a causal relationship between errors:
  # Parent Error → Child Error
  #
  # For example: DatabaseConnectionError → NoMethodError
  # When a database connection fails, subsequent code may try to call
  # methods on nil objects, causing NoMethodError.
  #
  # @attr parent_error_id [Integer] The error that happens first (potential cause)
  # @attr child_error_id [Integer] The error that happens after (potential effect)
  # @attr frequency [Integer] How many times this cascade has been observed
  # @attr avg_delay_seconds [Float] Average time between parent and child
  # @attr cascade_probability [Float] Likelihood (0.0-1.0) that parent causes child
  # @attr last_detected_at [DateTime] When this cascade was last observed
  class CascadePattern < ErrorLogsRecord
    self.table_name = "rails_error_dashboard_cascade_patterns"

    belongs_to :parent_error, class_name: "RailsErrorDashboard::ErrorLog"
    belongs_to :child_error, class_name: "RailsErrorDashboard::ErrorLog"

    validates :parent_error_id, presence: true
    validates :child_error_id, presence: true
    validates :frequency, presence: true, numericality: { greater_than: 0 }
    validate :parent_and_child_must_be_different

    scope :high_confidence, -> { where("cascade_probability >= ?", 0.7) }
    scope :frequent, ->(min_frequency = 3) { where("frequency >= ?", min_frequency) }
    scope :recent, -> { order(last_detected_at: :desc) }
    scope :by_parent, ->(error_id) { where(parent_error_id: error_id) }
    scope :by_child, ->(error_id) { where(child_error_id: error_id) }

    # Update cascade pattern stats — delegates to Command
    def increment_detection!(delay_seconds)
      Commands::IncrementCascadeDetection.call(self, delay_seconds)
    end

    # Calculate cascade probability — delegates to Command
    def calculate_probability!
      Commands::CalculateCascadeProbability.call(self)
    end

    # Check if this is a strong cascade pattern
    def strong_cascade?
      cascade_probability.present? && cascade_probability >= 0.7 && frequency >= 3
    end

    private

    def parent_and_child_must_be_different
      if parent_error_id == child_error_id
        errors.add(:child_error_id, "cannot be the same as parent error")
      end
    end
  end
end
