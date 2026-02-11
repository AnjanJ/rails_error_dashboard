# frozen_string_literal: true

require "httparty"

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

      payload = Services::WebhookPayloadBuilder.call(error_log)

      urls.each do |url|
        send_webhook(url, payload, error_log)
      end
    rescue StandardError => e
      Rails.logger.error("[RailsErrorDashboard] Failed to send webhook notification: #{e.message}")
      Rails.logger.error(e.backtrace&.first(5)&.join("\n")) if e.backtrace
    end

    private

    def send_webhook(url, payload, error_log)
      response = HTTParty.post(
        url,
        body: payload.to_json,
        headers: {
          "Content-Type" => "application/json",
          "User-Agent" => "RailsErrorDashboard/1.0",
          "X-Error-Dashboard-Event" => "error.created",
          "X-Error-Dashboard-ID" => error_log.id.to_s
        },
        timeout: 10  # CRITICAL: 10 second timeout to prevent hanging
      )

      unless response.success?
        Rails.logger.warn("[RailsErrorDashboard] Webhook failed for #{url}: #{response.code}")
      end
    rescue StandardError => e
      Rails.logger.error("[RailsErrorDashboard] Webhook error for #{url}: #{e.message}")
    end
  end
end
