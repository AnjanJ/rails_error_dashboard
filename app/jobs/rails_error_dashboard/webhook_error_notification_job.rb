# frozen_string_literal: true

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
      headers = {
        "Content-Type" => "application/json",
        "User-Agent" => "RailsErrorDashboard/1.0",
        "X-Error-Dashboard-Event" => "error.created",
        "X-Error-Dashboard-ID" => error_log.id.to_s
      }

      response = post_json(url, payload, headers)

      unless response_success?(response)
        Rails.logger.warn("[RailsErrorDashboard] Webhook failed for #{url}: #{response_code(response)}")
      end
    rescue StandardError => e
      Rails.logger.error("[RailsErrorDashboard] Webhook error for #{url}: #{e.message}")
    end

    def post_json(url, payload, headers)
      if defined?(HTTParty)
        HTTParty.post(url, body: payload.to_json, headers: headers, timeout: 10)
      else
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 5
        http.read_timeout = 10
        request = Net::HTTP::Post.new(uri.path, headers)
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
  end
end
