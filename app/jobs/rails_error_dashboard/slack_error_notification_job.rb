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

      request = Net::HTTP::Post.new(uri.path, { "Content-Type" => "application/json" })
      request.body = slack_payload(error_log).to_json

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error("Slack notification failed: #{response.code} - #{response.body}")
      end
    end

    def slack_payload(error_log)
      {
        text: "🚨 New Error in #{error_log.environment.titleize} Environment",
        blocks: [
          {
            type: "header",
            text: {
              type: "plain_text",
              text: "🚨 Error Alert",
              emoji: true
            }
          },
          {
            type: "section",
            fields: [
              {
                type: "mrkdwn",
                text: "*Error Type:*\n`#{error_log.error_type}`"
              },
              {
                type: "mrkdwn",
                text: "*Environment:*\n#{error_log.environment.titleize}"
              },
              {
                type: "mrkdwn",
                text: "*Platform:*\n#{platform_emoji(error_log.platform)} #{error_log.platform || 'Unknown'}"
              },
              {
                type: "mrkdwn",
                text: "*Occurred:*\n#{error_log.occurred_at.strftime('%B %d, %Y at %I:%M %p')}"
              }
            ]
          },
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "*Message:*\n```#{truncate_message(error_log.message)}```"
            }
          },
          user_section(error_log),
          request_section(error_log),
          {
            type: "actions",
            elements: [
              {
                type: "button",
                text: {
                  type: "plain_text",
                  text: "View Details",
                  emoji: true
                },
                url: dashboard_url(error_log),
                style: "primary"
              }
            ]
          },
          {
            type: "context",
            elements: [
              {
                type: "mrkdwn",
                text: "Error ID: #{error_log.id}"
              }
            ]
          }
        ].compact
      }
    end

    def user_section(error_log)
      return nil unless error_log.user_id.present?

      user_email = error_log.user&.email || "User ##{error_log.user_id}"

      {
        type: "section",
        fields: [
          {
            type: "mrkdwn",
            text: "*User:*\n#{user_email}"
          },
          {
            type: "mrkdwn",
            text: "*IP Address:*\n#{error_log.ip_address || 'N/A'}"
          }
        ]
      }
    end

    def request_section(error_log)
      return nil unless error_log.request_url.present?

      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: "*Request URL:*\n`#{truncate_message(error_log.request_url, 200)}`"
        }
      }
    end

    def platform_emoji(platform)
      case platform&.downcase
      when "ios"
        "📱"
      when "android"
        "🤖"
      when "api"
        "🔌"
      else
        "💻"
      end
    end

    def truncate_message(message, length = 500)
      return "" unless message
      message.length > length ? "#{message[0...length]}..." : message
    end

    def dashboard_url(error_log)
      # Generate URL to error dashboard
      # This will need to be configured based on your app's URL
      base_url = RailsErrorDashboard.configuration.dashboard_base_url || "http://localhost:3000"
      "#{base_url}/error_dashboard/errors/#{error_log.id}"
    end
  end
end
