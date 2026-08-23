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
      # @param locale [String] resolved by the enqueueing thread (P4-T1)
      # @return [Hash] Slack Block Kit payload
      #
      # Only the human-readable *values* are localized. Every "type" and
      # "style" below is Slack Block Kit vocabulary that Slack parses —
      # translating one would produce an invalid payload, not a localized one.
      def self.call(error_log, locale: I18nStore::DEFAULT_LOCALE)
        {
          text: NotificationHelpers.t("red.notifications.error_alert.fallback", locale),
          blocks: [
            header_block(locale),
            fields_block(error_log, locale),
            message_block(error_log, locale),
            user_block(error_log, locale),
            request_block(error_log, locale),
            actions_block(error_log, locale),
            context_block(error_log, locale)
          ].compact
        }
      end

      def self.header_block(locale)
        {
          type: "header",
          text: {
            type: "plain_text",
            text: NotificationHelpers.t("red.notifications.error_alert.heading", locale),
            emoji: true
          }
        }
      end

      def self.fields_block(error_log, locale)
        {
          type: "section",
          fields: [
            {
              type: "mrkdwn",
              text: NotificationHelpers.field(:application, NotificationHelpers.app_name(error_log), locale)
            },
            {
              type: "mrkdwn",
              text: NotificationHelpers.field(:error_type, "`#{error_log.error_type}`", locale)
            },
            {
              type: "mrkdwn",
              text: NotificationHelpers.field(
                :platform,
                "#{NotificationHelpers.platform_emoji(error_log.platform)} " \
                  "#{error_log.platform || NotificationHelpers.unknown(locale)}",
                locale
              )
            },
            {
              type: "mrkdwn",
              text: NotificationHelpers.field(
                :occurred, NotificationHelpers.format_datetime(error_log.occurred_at, locale), locale
              )
            }
          ]
        }
      end

      def self.message_block(error_log, locale)
        {
          type: "section",
          text: {
            type: "mrkdwn",
            # Message content is diagnostic output and is never translated.
            text: NotificationHelpers.field(
              :message, "```#{NotificationHelpers.truncate_message(error_log.message)}```", locale
            )
          }
        }
      end

      def self.user_block(error_log, locale)
        return nil unless error_log.user_id.present?

        user_email = error_log.user&.email ||
          NotificationHelpers.t("red.notifications.error_alert.user_fallback", locale, id: error_log.user_id)

        {
          type: "section",
          fields: [
            {
              type: "mrkdwn",
              text: NotificationHelpers.field(:user, user_email, locale)
            },
            {
              type: "mrkdwn",
              text: NotificationHelpers.field(
                :ip_address, error_log.ip_address || NotificationHelpers.not_available(locale), locale
              )
            }
          ]
        }
      end

      def self.request_block(error_log, locale)
        return nil unless error_log.request_url.present?

        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: NotificationHelpers.field(
              :request_url, "`#{NotificationHelpers.truncate_message(error_log.request_url, 200)}`", locale
            )
          }
        }
      end

      def self.actions_block(error_log, locale)
        {
          type: "actions",
          elements: [
            {
              type: "button",
              text: {
                type: "plain_text",
                text: NotificationHelpers.t("red.notifications.error_alert.view_details", locale),
                emoji: true
              },
              url: NotificationHelpers.dashboard_url(error_log),
              style: "primary"
            }
          ]
        }
      end

      def self.context_block(error_log, locale)
        {
          type: "context",
          elements: [
            {
              type: "mrkdwn",
              text: NotificationHelpers.t("red.notifications.error_alert.error_id", locale, id: error_log.id)
            }
          ]
        }
      end
    end
  end
end
