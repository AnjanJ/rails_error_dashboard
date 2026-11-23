# frozen_string_literal: true

module RailsErrorDashboard
  # Job to send error notifications to Discord via webhook
  class DiscordErrorNotificationJob < ApplicationJob
    include Concerns::TransientDelivery

    queue_as :default

    # @param locale [String, nil] resolved at enqueue time. nil for jobs
    #   enqueued by a pre-Phase-4 version still draining from the queue.
    # @param claimed_at [Time, nil] the cooldown claim to release if every
    #   attempt fails (Concerns::TransientDelivery). nil for rc.1's jobs.
    def perform(error_log_id, locale = nil, claimed_at = nil)
      error_log = ErrorLog.find(error_log_id)
      webhook_url = RailsErrorDashboard.configuration.discord_webhook_url

      return unless webhook_url.present?

      payload = Services::DiscordPayloadBuilder.call(error_log, locale: job_locale(locale))
      response = deliver_or_retry { post_json(webhook_url, payload) }

      unless check_delivery_response!(response, "Discord")
        Rails.logger.error("[RailsErrorDashboard] Discord notification failed: #{response.code}")
      end
    rescue TransientDeliveryError
      raise
    rescue StandardError => e
      Rails.logger.error("[RailsErrorDashboard] Failed to send Discord notification: #{e.message}")
      Rails.logger.error(e.backtrace&.first(5)&.join("\n")) if e.backtrace
    end

    private

    def post_json(url, payload)
      if defined?(HTTParty)
        HTTParty.post(url, body: payload.to_json,
          headers: { "Content-Type" => "application/json" }, timeout: 10)
      else
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 5
        http.read_timeout = 10
        request = Net::HTTP::Post.new(uri.request_uri, { "Content-Type" => "application/json" })
        request.body = payload.to_json
        http.request(request)
      end
    end
  end
end
