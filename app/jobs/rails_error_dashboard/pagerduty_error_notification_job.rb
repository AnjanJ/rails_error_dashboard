# frozen_string_literal: true

require 'httparty'

module RailsErrorDashboard
  # Job to send critical error notifications to PagerDuty
  # Only triggers for critical severity errors
  class PagerdutyErrorNotificationJob < ApplicationJob
    queue_as :default

    PAGERDUTY_EVENTS_API = 'https://events.pagerduty.com/v2/enqueue'

    def perform(error_log_id)
      error_log = ErrorLog.find(error_log_id)

      # Only trigger PagerDuty for critical errors
      return unless error_log.critical?

      routing_key = RailsErrorDashboard.configuration.pagerduty_integration_key
      return unless routing_key.present?

      payload = build_pagerduty_payload(error_log, routing_key)

      response = HTTParty.post(
        PAGERDUTY_EVENTS_API,
        body: payload.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      unless response.success?
        Rails.logger.error("PagerDuty API error: #{response.code} - #{response.body}")
      end
    rescue StandardError => e
      Rails.logger.error("Failed to send PagerDuty notification: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
    end

    private

    def build_pagerduty_payload(error_log, routing_key)
      {
        routing_key: routing_key,
        event_action: "trigger",
        payload: {
          summary: "Critical Error: #{error_log.error_type} in #{error_log.platform}",
          severity: "critical",
          source: error_source(error_log),
          component: error_log.controller_name || "Unknown",
          group: error_log.error_type,
          class: error_log.error_type,
          custom_details: {
            message: error_log.message,
            controller: error_log.controller_name,
            action: error_log.action_name,
            platform: error_log.platform,
            environment: error_log.environment,
            occurrences: error_log.occurrence_count,
            first_seen_at: error_log.first_seen_at&.iso8601,
            last_seen_at: error_log.last_seen_at&.iso8601,
            request_url: error_log.request_url,
            backtrace: extract_backtrace_summary(error_log.backtrace),
            error_id: error_log.id
          }
        },
        links: dashboard_links(error_log),
        client: "Rails Error Dashboard",
        client_url: dashboard_url(error_log)
      }
    end

    def error_source(error_log)
      if error_log.controller_name && error_log.action_name
        "#{error_log.controller_name}##{error_log.action_name}"
      elsif error_log.request_url
        error_log.request_url
      else
        error_log.platform || "Rails Application"
      end
    end

    def extract_backtrace_summary(backtrace)
      return [] if backtrace.nil?

      lines = backtrace.is_a?(String) ? backtrace.lines : backtrace
      lines.first(10).map(&:strip)
    end

    def dashboard_links(error_log)
      [
        {
          href: dashboard_url(error_log),
          text: "View in Error Dashboard"
        }
      ]
    end

    def dashboard_url(error_log)
      # This will need to be configured per deployment
      # For now, return a placeholder
      config = RailsErrorDashboard.configuration
      base_url = config.dashboard_base_url || "http://localhost:3000"
      "#{base_url}/error_dashboard/errors/#{error_log.id}"
    end
  end
end
