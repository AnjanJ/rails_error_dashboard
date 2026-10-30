# frozen_string_literal: true

module RailsErrorDashboard
  # The four bodies as 0.17.0 posted them, to the type. 0.18.0 added version and
  # timestamp and renamed three event values; nothing here may change in 1.x.
  # A key's value is a class, a list of classes it may be, or a nested body.
  module WebhookContract
    BOOLEAN = [ TrueClass, FalseClass ].freeze

    ERROR = {
      "id" => Integer, "application" => String, "type" => String, "message" => String,
      "platform" => String, "severity" => String, "occurred_at" => String
    }.freeze

    BODIES = {
      "error.created" => {
        "event" => String,
        "timestamp" => String,
        "error" => ERROR.merge(
          "environment" => String, "controller" => String, "action" => String,
          "occurrence_count" => Integer, "first_seen_at" => String, "last_seen_at" => String,
          "resolved" => BOOLEAN,
          "request" => { "url" => String, "params" => Hash, "user_agent" => String, "ip_address" => String },
          "user" => { "id" => Integer },
          "backtrace" => Array,
          "metadata" => { "error_hash" => String, "dashboard_url" => String }
        )
      },
      "baseline.anomaly_detected" => {
        "event" => String,
        "timestamp" => String,
        "error" => ERROR,
        "anomaly" => { "level" => String, "std_devs_above" => Float, "threshold" => Float, "baseline_type" => String },
        "dashboard_url" => String
      },
      "storm.detected" => {
        "event" => String, "started_at" => String, "state" => String, "application" => String
      },
      "notifications.suppressed" => {
        "event" => String, "limit" => Integer, "window_seconds" => Integer, "application" => String
      }
    }.freeze

    HEADERS = %w[
      Content-Type User-Agent X-Error-Dashboard-Event X-Error-Dashboard-ID
      X-Error-Dashboard-Timestamp X-Error-Dashboard-Signature-256
    ].freeze
  end
end
