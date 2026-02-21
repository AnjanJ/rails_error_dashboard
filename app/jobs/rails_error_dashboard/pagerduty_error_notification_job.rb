# frozen_string_literal: true

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
      response = post_json(PAGERDUTY_EVENTS_API, payload)

      unless response_success?(response)
        Rails.logger.error("[RailsErrorDashboard] PagerDuty API error: #{response_code(response)} - #{response_body(response)}")
      end
    rescue StandardError => e
      Rails.logger.error("[RailsErrorDashboard] Failed to send PagerDuty notification: #{e.message}")
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
        request = Net::HTTP::Post.new(uri.path, { "Content-Type" => "application/json" })
        request.body = payload.to_json
        http.request(request)
      end
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

    def response_body(response)
      response.respond_to?(:body) ? response.body : response&.body
    end
  end
end
