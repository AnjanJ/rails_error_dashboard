# frozen_string_literal: true

require "httparty"

module RailsErrorDashboard
  # Job to send critical error notifications to PagerDuty
  # Only triggers for critical severity errors
  class PagerdutyErrorNotificationJob < ApplicationJob
    queue_as :default

    PAGERDUTY_EVENTS_API = "https://events.pagerduty.com/v2/enqueue"

    def perform(error_log_id)
      error_log = ErrorLog.find(error_log_id)

      # Only trigger PagerDuty for critical errors
      return unless error_log.critical?

      routing_key = RailsErrorDashboard.configuration.pagerduty_integration_key
      return unless routing_key.present?

      payload = Services::PagerdutyPayloadBuilder.call(error_log, routing_key: routing_key)

      response = HTTParty.post(
        PAGERDUTY_EVENTS_API,
        body: payload.to_json,
        headers: { "Content-Type" => "application/json" },
        timeout: 10  # CRITICAL: 10 second timeout to prevent hanging
      )

      unless response.success?
        Rails.logger.error("[RailsErrorDashboard] PagerDuty API error: #{response.code} - #{response.body}")
      end
    rescue StandardError => e
      Rails.logger.error("[RailsErrorDashboard] Failed to send PagerDuty notification: #{e.message}")
      Rails.logger.error(e.backtrace&.first(5)&.join("\n")) if e.backtrace
    end
  end
end
