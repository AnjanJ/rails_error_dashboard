# frozen_string_literal: true

require 'httparty'

module RailsErrorDashboard
  # Job to send error notifications to custom webhook URLs
  # Supports multiple webhooks for different integrations
  class WebhookErrorNotificationJob < ApplicationJob
    queue_as :default

    def perform(error_log_id)
      error_log = ErrorLog.find(error_log_id)
      webhook_urls = RailsErrorDashboard.configuration.webhook_urls

      return unless webhook_urls.present?

      # Ensure webhook_urls is an array
      urls = Array(webhook_urls)

      payload = build_webhook_payload(error_log)

      urls.each do |url|
        send_webhook(url, payload, error_log)
      end
    rescue StandardError => e
      Rails.logger.error("Failed to send webhook notification: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
    end

    private

    def send_webhook(url, payload, error_log)
      response = HTTParty.post(
        url,
        body: payload.to_json,
        headers: {
          'Content-Type' => 'application/json',
          'User-Agent' => 'RailsErrorDashboard/1.0',
          'X-Error-Dashboard-Event' => 'error.created',
          'X-Error-Dashboard-ID' => error_log.id.to_s
        },
        timeout: 10 # 10 second timeout
      )

      unless response.success?
        Rails.logger.warn("Webhook failed for #{url}: #{response.code}")
      end
    rescue StandardError => e
      Rails.logger.error("Webhook error for #{url}: #{e.message}")
    end

    def build_webhook_payload(error_log)
      {
        event: "error.created",
        timestamp: Time.current.iso8601,
        error: {
          id: error_log.id,
          type: error_log.error_type,
          message: error_log.message,
          severity: error_log.severity.to_s,
          platform: error_log.platform,
          environment: error_log.environment,
          controller: error_log.controller_name,
          action: error_log.action_name,
          occurrence_count: error_log.occurrence_count,
          first_seen_at: error_log.first_seen_at&.iso8601,
          last_seen_at: error_log.last_seen_at&.iso8601,
          occurred_at: error_log.occurred_at.iso8601,
          resolved: error_log.resolved,
          request: {
            url: error_log.request_url,
            params: parse_request_params(error_log.request_params),
            user_agent: error_log.user_agent,
            ip_address: error_log.ip_address
          },
          user: {
            id: error_log.user_id
          },
          backtrace: extract_backtrace(error_log.backtrace),
          metadata: {
            error_hash: error_log.error_hash,
            dashboard_url: dashboard_url(error_log)
          }
        }
      }
    end

    def parse_request_params(params_json)
      return {} if params_json.nil?
      JSON.parse(params_json)
    rescue JSON::ParserError
      {}
    end

    def extract_backtrace(backtrace)
      return [] if backtrace.nil?

      lines = backtrace.is_a?(String) ? backtrace.lines : backtrace
      lines.first(20).map(&:strip)
    end

    def dashboard_url(error_log)
      config = RailsErrorDashboard.configuration
      base_url = config.dashboard_base_url || "http://localhost:3000"
      "#{base_url}/error_dashboard/errors/#{error_log.id}"
    end
  end
end
