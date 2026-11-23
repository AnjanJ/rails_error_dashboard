# frozen_string_literal: true

module RailsErrorDashboard
  # Job to send error notifications to custom webhook URLs
  # Supports multiple webhooks for different integrations
  class WebhookErrorNotificationJob < ApplicationJob
    include Concerns::TransientDelivery

    queue_as :default

    # @param locale [String, nil] resolved at enqueue time. nil for jobs
    #   enqueued by a pre-Phase-4 version still draining from the queue.
    # @param claimed_at [Time, nil] the cooldown claim to release if every
    #   attempt fails (Concerns::TransientDelivery). nil for rc.1's jobs.
    def perform(error_log_id, locale = nil, claimed_at = nil)
      error_log = ErrorLog.find(error_log_id)
      webhook_urls = RailsErrorDashboard.configuration.webhook_urls

      return unless webhook_urls.present?

      # Ensure webhook_urls is an array
      urls = Array(webhook_urls)

      payload = Services::WebhookPayloadBuilder.call(error_log, locale: job_locale(locale))

      # Every URL is tried before a transient failure retries the job, so one
      # unreachable receiver does not stop the next.
      transient = nil
      urls.each do |url|
        send_webhook(url, payload)
      rescue TransientDeliveryError => e
        transient ||= e
      end
      raise transient if transient
    rescue TransientDeliveryError
      raise
    rescue StandardError => e
      Rails.logger.error("[RailsErrorDashboard] Failed to send webhook notification: #{e.message}")
      Rails.logger.error(e.backtrace&.first(5)&.join("\n")) if e.backtrace
    end

    private

    def send_webhook(url, payload)
      # Adds the contract's version and headers, serialises, signs (when
      # webhook_signing_secret is set) and posts.
      response = deliver_or_retry { Services::WebhookDelivery.post(url, payload) }

      unless check_delivery_response!(response, "Webhook #{url}")
        Rails.logger.warn("[RailsErrorDashboard] Webhook failed for #{url}: #{response_code(response)}")
      end
    rescue TransientDeliveryError
      raise
    rescue StandardError => e
      Rails.logger.error("[RailsErrorDashboard] Webhook error for #{url}: #{e.message}")
    end

    def response_code(response)
      response.respond_to?(:code) ? response.code : response&.code
    end
  end
end
