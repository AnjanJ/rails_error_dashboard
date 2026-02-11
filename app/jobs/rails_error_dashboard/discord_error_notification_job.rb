# frozen_string_literal: true

require "httparty"

module RailsErrorDashboard
  # Job to send error notifications to Discord via webhook
  class DiscordErrorNotificationJob < ApplicationJob
    queue_as :default

    def perform(error_log_id)
      error_log = ErrorLog.find(error_log_id)
      webhook_url = RailsErrorDashboard.configuration.discord_webhook_url

      return unless webhook_url.present?

      payload = Services::DiscordPayloadBuilder.call(error_log)

      HTTParty.post(
        webhook_url,
        body: payload.to_json,
        headers: { "Content-Type" => "application/json" },
        timeout: 10  # CRITICAL: 10 second timeout to prevent hanging
      )
    rescue StandardError => e
      Rails.logger.error("[RailsErrorDashboard] Failed to send Discord notification: #{e.message}")
      Rails.logger.error(e.backtrace&.first(5)&.join("\n")) if e.backtrace
    end
  end
end
