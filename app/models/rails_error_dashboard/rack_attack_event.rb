# frozen_string_literal: true

module RailsErrorDashboard
  # Stores aggregated Rack::Attack throttle/blocklist/track events per hourly bucket.
  #
  # Rack::Attack events are NOT errors — a throttled request returns HTTP 429 without
  # raising. They are therefore persisted independently of error_logs rather than as
  # a side-effect of error capture (see issue #143).
  #
  # Rows are aggregated hourly by (rule, match_type, discriminator, path) so that a
  # rate-limit flood collapses to a handful of rows instead of one INSERT per request.
  class RackAttackEvent < ErrorLogsRecord
    self.table_name = "rails_error_dashboard_rack_attack_events"

    # Event types emitted by Rack::Attack (v5.0+)
    MATCH_TYPES = %w[throttle blocklist track safelist].freeze

    belongs_to :application, optional: true

    validates :rule, presence: true
    validates :match_type, presence: true
    validates :period_hour, presence: true
    validates :event_count, presence: true, numericality: { greater_than_or_equal_to: 0 }

    scope :for_application, ->(app_id) { where(application_id: app_id) }
    scope :since, ->(time) { where("period_hour >= ?", time) }
    scope :recent, -> { order(period_hour: :desc) }
    scope :throttles, -> { where(match_type: "throttle") }
    scope :blocklists, -> { where(match_type: "blocklist") }

    # Whether this event represents a hard block rather than a rate limit
    def blocked?
      match_type == "blocklist"
    end
  end
end
