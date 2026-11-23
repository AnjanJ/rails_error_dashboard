# frozen_string_literal: true

module RailsErrorDashboard
  class SlackErrorNotificationJob < ApplicationJob
    include Concerns::TransientDelivery

    queue_as :error_notifications

    # @param locale [String, nil] resolved at enqueue time. nil for jobs
    #   enqueued by a pre-Phase-4 version still draining from the queue.
    # @param claimed_at [Time, nil] the cooldown claim to release if every
    #   attempt fails (Concerns::TransientDelivery). nil for rc.1's jobs.
    def perform(error_log_id, locale = nil, claimed_at = nil)
      error_log = ErrorLog.find_by(id: error_log_id)
      return unless error_log

      webhook_url = RailsErrorDashboard.configuration.slack_webhook_url
      return unless webhook_url.present?

      send_slack_notification(error_log, webhook_url, job_locale(locale))
    rescue TransientDeliveryError
      raise
    rescue => e
      Rails.logger.error("Failed to send Slack notification: #{e.message}")
    end

    private

    def send_slack_notification(error_log, webhook_url, locale)
      require "net/http"
      require "json"

      uri = URI(webhook_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      # CRITICAL: Add timeouts to prevent hanging the job queue
      http.open_timeout = 5  # 5 seconds to establish connection
      http.read_timeout = 10  # 10 seconds to read response

      request = Net::HTTP::Post.new(uri.request_uri, { "Content-Type" => "application/json" })
      request.body = Services::SlackPayloadBuilder.call(error_log, locale: locale).to_json

      response = deliver_or_retry { http.request(request) }

      unless check_delivery_response!(response, "Slack")
        Rails.logger.error("[RailsErrorDashboard] Slack notification failed: #{response.code} - #{response.body}")
      end
    end
  end
end
