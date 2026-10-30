# frozen_string_literal: true

module RailsErrorDashboard
  # The event names RED posts to config.webhook_urls, and the only place they
  # are written. They used to be literals in four files, which is how they came
  # to be in three styles. docs/WEBHOOKS.md is the contract; a spec keeps it and
  # this list together, and 1.x may add events but never rename or remove one.
  module Webhooks
    ERROR_CREATED = "error.created"
    STORM_DETECTED = "storm.detected"
    NOTIFICATIONS_SUPPRESSED = "notifications.suppressed"
    BASELINE_ANOMALY_DETECTED = "baseline.anomaly_detected"

    EVENTS = {
      error_created: ERROR_CREATED,
      storm_detected: STORM_DETECTED,
      notifications_suppressed: NOTIFICATIONS_SUPPRESSED,
      baseline_anomaly_detected: BASELINE_ANOMALY_DETECTED
    }.freeze
  end
end
