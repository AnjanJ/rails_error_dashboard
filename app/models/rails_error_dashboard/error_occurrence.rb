# frozen_string_literal: true

module RailsErrorDashboard
  # Tracks individual occurrences of errors for co-occurrence analysis
  #
  # Each time an error is logged, we create an ErrorOccurrence record
  # to track when it happened, who was affected, and what request caused it.
  # This allows us to find errors that occur together in time windows.
  class ErrorOccurrence < ErrorLogsRecord
    self.table_name = "rails_error_dashboard_error_occurrences"

    belongs_to :error_log, class_name: "RailsErrorDashboard::ErrorLog"

    # Only define user association if User model exists
    if defined?(::User)
      belongs_to :user, optional: true
    end

    validates :occurred_at, presence: true
    validates :error_log_id, presence: true

    scope :recent, -> { order(occurred_at: :desc) }
    scope :in_time_window, ->(start_time, end_time) { where(occurred_at: start_time..end_time) }
    scope :for_user, ->(user_id) { where(user_id: user_id) }
    scope :for_request, ->(request_id) { where(request_id: request_id) }
    # Takes the raw session ID (or a stored digest). Rows are stored as a keyed
    # digest while filter_sensitive_data is on, and raw otherwise or before the
    # upgrade, so both forms are matched. Blank matches nothing.
    scope :for_session, lambda { |session_id|
      raw = session_id.to_s
      next none if raw.empty?

      where(session_id: [ raw, Services::SensitiveDataFilter.digest_session_id(raw) ].compact.uniq)
    }

    # Find occurrences within a time window around this occurrence
    # @param window_minutes [Integer] Time window in minutes (default: 5)
    # @return [ActiveRecord::Relation] Other occurrences in the time window
    def nearby_occurrences(window_minutes: 5)
      window = window_minutes.minutes
      start_time = occurred_at - window
      end_time = occurred_at + window

      self.class
        .in_time_window(start_time, end_time)
        .where.not(id: id) # Exclude self
    end

    # Find other error types that occurred near this occurrence
    # @param window_minutes [Integer] Time window in minutes (default: 5)
    # @return [ActiveRecord::Relation] ErrorLog records of co-occurring errors
    def co_occurring_error_types(window_minutes: 5)
      occurrence_ids = nearby_occurrences(window_minutes: window_minutes).pluck(:error_log_id)
      ErrorLog.where(id: occurrence_ids).where.not(error_type: error_log.error_type).distinct
    end
  end
end
