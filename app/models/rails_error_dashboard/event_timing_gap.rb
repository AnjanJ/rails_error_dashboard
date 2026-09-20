# frozen_string_literal: true

module RailsErrorDashboard
  # An interval whose per-event timing evidence was lost.
  #
  # See the migration for why this is its own table rather than a flag on the
  # storm episode: the episode is optional, and it is written after the counts
  # transaction has already committed.
  #
  # Inherits ErrorLogsRecord so separate-database routing applies.
  class EventTimingGap < ErrorLogsRecord
    self.table_name = "rails_error_dashboard_event_timing_gaps"

    # Gaps overlapping [from, to). Open-ended when +to+ is nil.
    #
    # Overlap, not containment: a gap that began before the window and runs
    # into it still makes that window's timing unreliable. Checking only
    # "starts inside the window" is the mistake the episode predicate made.
    scope :overlapping, ->(from, to = nil) {
      scope = where(arel_table[:covered_until].gteq(from))
      to ? scope.where(arel_table[:covered_from].lt(to)) : scope
    }

    # Whether any recorded gap affects the given window.
    #
    # Every guard is deliberate: the table may not be migrated on an older
    # host, and this is read on the dashboard path, which must never raise.
    #
    # @param from [Time] start of the window being displayed
    # @param application_id [Integer, nil]
    # @return [Boolean]
    def self.affecting?(from, application_id: nil)
      return false unless table_exists?

      scope = overlapping(from)
      # A NULL application_id means the gap applies everywhere, so it is
      # included whatever is being filtered for.
      scope = scope.where(application_id: [ application_id, nil ]) if application_id.present?
      scope.exists?
    rescue StandardError => e
      RailsErrorDashboard::Logger.debug(
        "[RailsErrorDashboard] EventTimingGap.affecting? failed: #{e.class} - #{e.message}"
      )
      false
    end

    def self.table_exists?
      connection.table_exists?(table_name)
    rescue *Commands::LogError::RETRYABLE_STORE_ERRORS
      raise
    rescue StandardError
      false
    end
  end
end
