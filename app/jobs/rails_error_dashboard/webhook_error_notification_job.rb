# frozen_string_literal: true

module RailsErrorDashboard
  # Job to send error notifications to custom webhook URLs
  # Supports multiple webhooks for different integrations
  class WebhookErrorNotificationJob < ApplicationJob
    queue_as :default

    # @param locale [String, nil] resolved at enqueue time. nil for jobs
    #   enqueued by a pre-Phase-4 version still draining from the queue.
    def perform(error_log_id, locale = nil)
      error_log = ErrorLog.find(error_log_id)
      webhook_urls = RailsErrorDashboard.configuration.webhook_urls

      return unless webhook_urls.present?

      # Ensure webhook_urls is an array
      urls = Array(webhook_urls)

      payload = Services::WebhookPayloadBuilder.call(error_log, locale: job_locale(locale))

      urls.each do |url|
        send_webhook(url, payload, error_log)
      end
    rescue StandardError => e
      Rails.logger.error("[RailsErrorDashboard] Failed to send webhook notification: #{e.message}")
      Rails.logger.error(e.backtrace&.first(5)&.join("\n")) if e.backtrace
    end

    private

    def send_webhook(url, payload, error_log)
      headers = {
        "X-Error-Dashboard-Event" => "error.created",
        "X-Error-Dashboard-ID" => error_log.id.to_s
      }

      # Serialises, signs (when webhook_signing_secret is set) and posts.
      response = Services::WebhookDelivery.post(url, payload, headers: headers)

      unless response_success?(response)
        Rails.logger.warn("[RailsErrorDashboard] Webhook failed for #{url}: #{response_code(response)}")
      end
    rescue StandardError => e
      Rails.logger.error("[RailsErrorDashboard] Webhook error for #{url}: #{e.message}")
    end

    def response_success?(response)
      if response.respond_to?(:success?)
        response.success?
      else
        response.is_a?(Net::HTTPSuccess)
      end
    end

    def response_code(response)
      response.respond_to?(:code) ? response.code : response&.code
    end
  end
end
