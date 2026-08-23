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
      # @param locale [String] resolved by the enqueueing thread (P4-T1)
      #
      # As in SlackPayloadBuilder, the Block Kit "type" values are Slack's
      # vocabulary and stay English; only the labels and button text move.
      def self.slack_payload(error_log, anomaly_data, locale: I18nStore::DEFAULT_LOCALE)
        {
          text: NotificationHelpers.t("red.notifications.baseline_alert.fallback", locale),
          blocks: [
            {
              type: "header",
              text: {
                type: "plain_text",
                text: NotificationHelpers.t("red.notifications.baseline_alert.heading", locale)
              }
            },
            {
              type: "section",
              fields: [
                {
                  type: "mrkdwn",
                  text: NotificationHelpers.field(:application, NotificationHelpers.app_name(error_log), locale)
                },
                {
                  type: "mrkdwn",
                  text: NotificationHelpers.field(:error_type, error_log.error_type, locale)
                },
                {
                  type: "mrkdwn",
                  text: NotificationHelpers.field(:platform, error_log.platform, locale)
                },
                {
                  type: "mrkdwn",
                  text: baseline_field(
                    :severity,
                    "#{anomaly_emoji(anomaly_data[:level])} #{anomaly_level(anomaly_data[:level], locale)}",
                    locale
                  )
                },
                {
                  type: "mrkdwn",
                  text: baseline_field(:std_devs, std_devs_text(anomaly_data, locale), locale)
                }
              ]
            },
            {
              type: "section",
              text: {
                type: "mrkdwn",
                # Message content is diagnostic output — never translated.
                text: NotificationHelpers.field(
                  :message, "```#{NotificationHelpers.truncate_message(error_log.message, 200)}```", locale
                )
              }
            },
            {
              type: "section",
              text: {
                type: "mrkdwn",
                text: baseline_field(
                  :baseline_info,
                  "#{baseline_label(:threshold, locale)}: #{threshold_text(anomaly_data, locale)}\n" \
                    "#{baseline_label(:baseline_type, locale)}: #{anomaly_data[:baseline_type]}",
                  locale
                )
              }
            },
            {
              type: "actions",
              elements: [
                {
                  type: "button",
                  text: {
                    type: "plain_text",
                    text: NotificationHelpers.t("red.notifications.baseline_alert.view_in_dashboard", locale)
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
      def self.discord_payload(error_log, anomaly_data, locale: I18nStore::DEFAULT_LOCALE)
        {
          embeds: [
            {
              title: NotificationHelpers.t("red.notifications.baseline_alert.heading", locale),
              color: anomaly_color(anomaly_data[:level]),
              fields: [
                { name: NotificationHelpers.label(:application, locale), value: NotificationHelpers.app_name(error_log), inline: true },
                { name: NotificationHelpers.label(:error_type, locale), value: error_log.error_type, inline: true },
                { name: NotificationHelpers.label(:platform, locale), value: error_log.platform, inline: true },
                { name: baseline_label(:severity, locale), value: anomaly_level(anomaly_data[:level], locale), inline: true },
                { name: baseline_label(:std_devs, locale), value: std_devs_text(anomaly_data, locale), inline: true },
                { name: baseline_label(:threshold, locale), value: threshold_text(anomaly_data, locale), inline: true },
                { name: baseline_label(:baseline_type, locale), value: anomaly_data[:baseline_type] || NotificationHelpers.not_available(locale), inline: true },
                { name: NotificationHelpers.label(:message, locale), value: "```#{NotificationHelpers.truncate_message(error_log.message, 200)}```", inline: false }
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
      # Machine-readable. Every key AND value here is consumed by whatever the
      # operator has wired up downstream, so nothing is localized — the locale
      # is accepted only so the signature matches its siblings (REQ-2, REQ-6).
      def self.webhook_payload(error_log, anomaly_data, locale: I18nStore::DEFAULT_LOCALE)
        _locale = locale

        {
          event: "baseline_anomaly",
          timestamp: Time.current.iso8601,
          error: {
            id: error_log.id,
            application: NotificationHelpers.app_name(error_log),
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

      # A label from red.notifications.baseline_alert.labels. Separate from
      # NotificationHelpers.label because these are anomaly-specific and do not
      # appear on an ordinary error alert.
      def self.baseline_label(label, locale)
        NotificationHelpers.t("red.notifications.baseline_alert.labels.#{label}", locale)
      end

      # Slack's bold-label-newline-value shape, for a baseline-only label.
      def self.baseline_field(label, value, locale)
        "*#{baseline_label(label, locale)}:*\n#{value}"
      end

      # Anomaly levels are their own vocabulary — an anomaly can be "elevated",
      # an error cannot — so they do not reuse red.common.severity. Previously
      # rendered with .upcase on the raw symbol, which applies English
      # morphology to a machine value.
      def self.anomaly_level(level, locale)
        key = ANOMALY_EMOJIS.key?(level) ? level : :unknown
        NotificationHelpers.t("red.notifications.baseline_alert.level.#{key}", locale)
      end

      def self.std_devs_text(anomaly_data, locale)
        NotificationHelpers.t(
          "red.notifications.baseline_alert.std_devs_above",
          locale,
          value: anomaly_data[:std_devs_above]&.round(1)
        )
      end

      # "N errors" was an English binary plural; it is now a real plural key.
      #
      # The threshold is a rounded float (e.g. 12.5) but plural selection needs
      # an Integer, so :count carries the integer and :value the number that is
      # actually displayed. A locale whose plural rules differ at 1 vs 1.5 is
      # not a case CLDR expresses, so rounding for selection is correct.
      def self.threshold_text(anomaly_data, locale)
        rounded = anomaly_data[:threshold]&.round(1)

        NotificationHelpers.t(
          "red.notifications.baseline_alert.threshold_errors",
          locale,
          count: rounded.to_i,
          value: rounded
        )
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
