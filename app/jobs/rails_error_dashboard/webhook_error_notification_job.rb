# frozen_string_literal: true

module RailsErrorDashboard
  # Job to send error notifications to custom webhook URLs.
  #
  # One job per URL (ErrorNotificationDispatcher), so a retry re-posts only the
  # URL that failed, with the same X-Error-Dashboard-Delivery id
  # (hardening-1-0-rc2, REQ-32). A job enqueued by rc.1 has no URL and posts
  # every one.
  class WebhookErrorNotificationJob < ApplicationJob
    include Concerns::TransientDelivery

    queue_as :default

    # @param locale [String, nil] resolved at enqueue time. nil for jobs
    #   enqueued by a pre-Phase-4 version still draining from the queue.
    # @param claimed_at [Time, nil] the cooldown claim to release if every
    #   attempt fails (Concerns::TransientDelivery). nil for rc.1's jobs.
    # @param url_digest [String, nil] WebhookDelivery.url_digest of the one
    #   URL to post. nil for rc.1's jobs, which post every URL.
    def perform(error_log_id, locale = nil, claimed_at = nil, url_digest = nil)
      error_log = ErrorLog.find(error_log_id)
      webhook_urls = RailsErrorDashboard.configuration.webhook_urls

      return unless webhook_urls.present?

      urls = Array(webhook_urls)
      # A URL removed from webhook_urls since the enqueue matches nothing.
      urls = urls.select { |url| Services::WebhookDelivery.url_digest(url) == url_digest }.first(1) if url_digest

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
      delivery_id = Services::WebhookDelivery.delivery_id(job_id, url)
      response = deliver_or_retry { Services::WebhookDelivery.post(url, payload, delivery_id: delivery_id) }

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
