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

      payload = build_discord_payload(error_log)

      HTTParty.post(
        webhook_url,
        body: payload.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    rescue StandardError => e
      Rails.logger.error("Failed to send Discord notification: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
    end

    private

    def build_discord_payload(error_log)
      {
        embeds: [ {
          title: "🚨 New Error: #{error_log.error_type}",
          description: truncate_message(error_log.message),
          color: severity_color(error_log),
          fields: [
            {
              name: "Platform",
              value: error_log.platform || "Unknown",
              inline: true
            },
            {
              name: "Environment",
              value: error_log.environment || "Unknown",
              inline: true
            },
            {
              name: "Occurrences",
              value: error_log.occurrence_count.to_s,
              inline: true
            },
            {
              name: "Controller",
              value: error_log.controller_name || "N/A",
              inline: true
            },
            {
              name: "Action",
              value: error_log.action_name || "N/A",
              inline: true
            },
            {
              name: "First Seen",
              value: format_time(error_log.first_seen_at),
              inline: true
            },
            {
              name: "Location",
              value: extract_first_backtrace_line(error_log.backtrace),
              inline: false
            }
          ],
          footer: {
            text: "Rails Error Dashboard"
          },
          timestamp: error_log.occurred_at.iso8601
        } ]
      }
    end

    def severity_color(error_log)
      case error_log.severity
      when :critical
        16711680 # Red
      when :high
        16744192 # Orange
      when :medium
        16776960 # Yellow
      else
        8421504  # Gray
      end
    end

    def truncate_message(message, length = 200)
      return "" if message.nil?
      message.length > length ? "#{message[0...length]}..." : message
    end

    def format_time(time)
      return "N/A" if time.nil?
      time.strftime("%Y-%m-%d %H:%M:%S UTC")
    end

    def extract_first_backtrace_line(backtrace)
      return "N/A" if backtrace.nil?

      lines = backtrace.is_a?(String) ? backtrace.lines : backtrace
      first_line = lines.first&.strip

      return "N/A" if first_line.nil?

      # Truncate if too long
      first_line.length > 100 ? "#{first_line[0...100]}..." : first_line
    end
  end
end
