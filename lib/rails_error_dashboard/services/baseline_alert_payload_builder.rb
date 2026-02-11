# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Build notification payloads for baseline anomaly alerts
    #
    # No HTTP calls — accepts error + anomaly data, returns platform-specific Hashes.
    #
    # @example
    #   BaselineAlertPayloadBuilder.slack_payload(error_log, anomaly_data)
    #   BaselineAlertPayloadBuilder.discord_payload(error_log, anomaly_data)
    #   BaselineAlertPayloadBuilder.webhook_payload(error_log, anomaly_data)
    class BaselineAlertPayloadBuilder
      ANOMALY_EMOJIS = {
        critical: "🔴",
        high: "🟠",
        elevated: "🟡"
      }.freeze

      ANOMALY_COLORS = {
        critical: 15158332,  # Red
        high: 16744192,      # Orange
        elevated: 16776960   # Yellow
      }.freeze

      DEFAULT_EMOJI = "⚪"
      DEFAULT_COLOR = 9807270 # Gray

      # Build Slack Block Kit payload for baseline anomaly
      # @param error_log [ErrorLog] The error
      # @param anomaly_data [Hash] Anomaly information
      # @return [Hash] Slack payload
      def self.slack_payload(error_log, anomaly_data)
        {
          text: "🚨 Baseline Anomaly Alert",
          blocks: [
            {
              type: "header",
              text: {
                type: "plain_text",
                text: "🚨 Baseline Anomaly Detected"
              }
            },
            {
              type: "section",
              fields: [
                {
                  type: "mrkdwn",
                  text: "*Error Type:*\n#{error_log.error_type}"
                },
                {
                  type: "mrkdwn",
                  text: "*Platform:*\n#{error_log.platform}"
                },
                {
                  type: "mrkdwn",
                  text: "*Severity:*\n#{anomaly_emoji(anomaly_data[:level])} #{anomaly_data[:level].to_s.upcase}"
                },
                {
                  type: "mrkdwn",
                  text: "*Standard Deviations:*\n#{anomaly_data[:std_devs_above]&.round(1)}σ above baseline"
                }
              ]
            },
            {
              type: "section",
              text: {
                type: "mrkdwn",
                text: "*Message:*\n```#{NotificationHelpers.truncate_message(error_log.message, 200)}```"
              }
            },
            {
              type: "section",
              text: {
                type: "mrkdwn",
                text: "*Baseline Info:*\nThreshold: #{anomaly_data[:threshold]&.round(1)} errors\nBaseline Type: #{anomaly_data[:baseline_type]}"
              }
            },
            {
              type: "actions",
              elements: [
                {
                  type: "button",
                  text: {
                    type: "plain_text",
                    text: "View in Dashboard"
                  },
                  url: NotificationHelpers.dashboard_url(error_log)
                }
              ]
            }
          ]
        }
      end

      # Build Discord embed payload for baseline anomaly
      # @param error_log [ErrorLog] The error
      # @param anomaly_data [Hash] Anomaly information
      # @return [Hash] Discord payload
      def self.discord_payload(error_log, anomaly_data)
        {
          embeds: [
            {
              title: "🚨 Baseline Anomaly Detected",
              color: anomaly_color(anomaly_data[:level]),
              fields: [
                { name: "Error Type", value: error_log.error_type, inline: true },
                { name: "Platform", value: error_log.platform, inline: true },
                { name: "Severity", value: anomaly_data[:level].to_s.upcase, inline: true },
                { name: "Standard Deviations", value: "#{anomaly_data[:std_devs_above]&.round(1)}σ above baseline", inline: true },
                { name: "Threshold", value: "#{anomaly_data[:threshold]&.round(1)} errors", inline: true },
                { name: "Baseline Type", value: anomaly_data[:baseline_type] || "N/A", inline: true },
                { name: "Message", value: "```#{NotificationHelpers.truncate_message(error_log.message, 200)}```", inline: false }
              ],
              url: NotificationHelpers.dashboard_url(error_log),
              timestamp: Time.current.iso8601
            }
          ]
        }
      end

      # Build generic webhook payload for baseline anomaly
      # @param error_log [ErrorLog] The error
      # @param anomaly_data [Hash] Anomaly information
      # @return [Hash] Webhook payload
      def self.webhook_payload(error_log, anomaly_data)
        {
          event: "baseline_anomaly",
          timestamp: Time.current.iso8601,
          error: {
            id: error_log.id,
            type: error_log.error_type,
            message: error_log.message,
            platform: error_log.platform,
            severity: error_log.severity.to_s,
            occurred_at: error_log.occurred_at.iso8601
          },
          anomaly: {
            level: anomaly_data[:level].to_s,
            std_devs_above: anomaly_data[:std_devs_above],
            threshold: anomaly_data[:threshold],
            baseline_type: anomaly_data[:baseline_type]
          },
          dashboard_url: NotificationHelpers.dashboard_url(error_log)
        }
      end

      # @param level [Symbol] Anomaly level (:critical, :high, :elevated)
      # @return [String] Emoji
      def self.anomaly_emoji(level)
        ANOMALY_EMOJIS[level] || DEFAULT_EMOJI
      end

      # @param level [Symbol] Anomaly level
      # @return [Integer] Discord color integer
      def self.anomaly_color(level)
        ANOMALY_COLORS[level] || DEFAULT_COLOR
      end
    end
  end
end
