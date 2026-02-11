# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Build Slack Block Kit payload for error notifications
    #
    # No HTTP calls — accepts error data, returns a Hash ready for JSON serialization.
    #
    # @example
    #   SlackPayloadBuilder.call(error_log)
    #   # => { text: "...", blocks: [...] }
    class SlackPayloadBuilder
      # @param error_log [ErrorLog] The error to build a payload for
      # @return [Hash] Slack Block Kit payload
      def self.call(error_log)
        {
          text: "🚨 New Error Alert",
          blocks: [
            header_block,
            fields_block(error_log),
            message_block(error_log),
            user_block(error_log),
            request_block(error_log),
            actions_block(error_log),
            context_block(error_log)
          ].compact
        }
      end

      def self.header_block
        {
          type: "header",
          text: {
            type: "plain_text",
            text: "🚨 Error Alert",
            emoji: true
          }
        }
      end

      def self.fields_block(error_log)
        {
          type: "section",
          fields: [
            {
              type: "mrkdwn",
              text: "*Error Type:*\n`#{error_log.error_type}`"
            },
            {
              type: "mrkdwn",
              text: "*Platform:*\n#{NotificationHelpers.platform_emoji(error_log.platform)} #{error_log.platform || 'Unknown'}"
            },
            {
              type: "mrkdwn",
              text: "*Occurred:*\n#{error_log.occurred_at.strftime('%B %d, %Y at %I:%M %p')}"
            }
          ]
        }
      end

      def self.message_block(error_log)
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: "*Message:*\n```#{NotificationHelpers.truncate_message(error_log.message)}```"
          }
        }
      end

      def self.user_block(error_log)
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

      def self.request_block(error_log)
        return nil unless error_log.request_url.present?

        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: "*Request URL:*\n`#{NotificationHelpers.truncate_message(error_log.request_url, 200)}`"
          }
        }
      end

      def self.actions_block(error_log)
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
              url: NotificationHelpers.dashboard_url(error_log),
              style: "primary"
            }
          ]
        }
      end

      def self.context_block(error_log)
        {
          type: "context",
          elements: [
            {
              type: "mrkdwn",
              text: "Error ID: #{error_log.id}"
            }
          ]
        }
      end
    end
  end
end
