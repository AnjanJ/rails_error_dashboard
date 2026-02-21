# frozen_string_literal: true

module RailsErrorDashboard
  # Job to send error notifications to Discord via webhook
  class DiscordErrorNotificationJob < ApplicationJob
    queue_as :default

    def perform(error_log_id)
      error_log = ErrorLog.find(error_log_id)
      webhook_url = RailsErrorDashboard.configuration.discord_webhook_url

      return unless webhook_url.present?

      payload = Services::DiscordPayloadBuilder.call(error_log)
      post_json(webhook_url, payload)
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
        request = Net::HTTP::Post.new(uri.path, { "Content-Type" => "application/json" })
        request.body = payload.to_json
        http.request(request)
      end
    end
  end
end
