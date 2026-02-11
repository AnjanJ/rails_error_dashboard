# frozen_string_literal: true

module RailsErrorDashboard
  class SlackErrorNotificationJob < ApplicationJob
    queue_as :error_notifications

    def perform(error_log_id)
      error_log = ErrorLog.find_by(id: error_log_id)
      return unless error_log

      webhook_url = RailsErrorDashboard.configuration.slack_webhook_url
      return unless webhook_url.present?

      send_slack_notification(error_log, webhook_url)
    rescue => e
      Rails.logger.error("Failed to send Slack notification: #{e.message}")
    end

    private

    def send_slack_notification(error_log, webhook_url)
      require "net/http"
      require "json"

      uri = URI(webhook_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      # CRITICAL: Add timeouts to prevent hanging the job queue
      http.open_timeout = 5  # 5 seconds to establish connection
      http.read_timeout = 10  # 10 seconds to read response

      request = Net::HTTP::Post.new(uri.path, { "Content-Type" => "application/json" })
      request.body = Services::SlackPayloadBuilder.call(error_log).to_json

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error("[RailsErrorDashboard] Slack notification failed: #{response.code} - #{response.body}")
      end
    rescue Timeout::Error, Errno::ECONNREFUSED, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
      # Network errors - log and fail gracefully
      Rails.logger.error("[RailsErrorDashboard] Slack HTTP request failed: #{e.class} - #{e.message}")
      nil
    end
  end
end
