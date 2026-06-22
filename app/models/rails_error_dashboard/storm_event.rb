# frozen_string_literal: true

module RailsErrorDashboard
  # One row per storm-protection episode (per process). Powers the dashboard
  # banner and the storm history page. Counts are exact, not extrapolated.
  # Inherits ErrorLogsRecord so separate-database routing applies.
  class StormEvent < ErrorLogsRecord
    self.table_name = "rails_error_dashboard_storm_events"

    scope :active, -> { where(ended_at: nil) }
    scope :recent_first, -> { order(started_at: :desc) }
    scope :ended_within, ->(duration) { where.not(ended_at: nil).where(ended_at: duration.ago..) }

    def active?
      ended_at.nil?
    end

    def duration_seconds
      return nil unless ended_at

      (ended_at - started_at).round
    end

    # @return [Array<Hash>] top fingerprints by count, [] when absent/corrupt
    def top_fingerprints_list
      return [] if top_fingerprints.blank?

      parsed = JSON.parse(top_fingerprints)
      parsed.is_a?(Array) ? parsed : []
    rescue JSON::ParserError
      []
    end
  end
end
