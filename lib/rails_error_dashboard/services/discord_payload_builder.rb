# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Build Discord embed payload for error notifications
    #
    # No HTTP calls — accepts error data, returns a Hash ready for JSON serialization.
    #
    # @example
    #   DiscordPayloadBuilder.call(error_log)
    #   # => { embeds: [...] }
    class DiscordPayloadBuilder
      SEVERITY_COLORS = {
        critical: 16711680,  # Red
        high: 16744192,      # Orange
        medium: 16776960    # Yellow
      }.freeze
      DEFAULT_COLOR = 8421504 # Gray

      # @param error_log [ErrorLog] The error to build a payload for
      # @param locale [String] resolved by the enqueueing thread (P4-T1)
      # @return [Hash] Discord embed payload
      #
      # Field *names* are human-readable and localized; "inline", "color" and
      # "timestamp" are Discord embed schema and stay as they are. The footer
      # is the product name, which is not translated.
      def self.call(error_log, locale: I18nStore::DEFAULT_LOCALE)
        unknown = NotificationHelpers.unknown(locale)
        not_available = NotificationHelpers.not_available(locale)

        {
          embeds: [ {
            # error_type is an exception class name — verbatim.
            title: NotificationHelpers.t(
              "red.notifications.error_alert.discord_title", locale, error_type: error_log.error_type
            ),
            description: NotificationHelpers.truncate_message(error_log.message, 200),
            color: severity_color(error_log),
            fields: [
              {
                name: NotificationHelpers.label(:application, locale),
                value: NotificationHelpers.app_name(error_log),
                inline: true
              },
              {
                name: NotificationHelpers.label(:platform, locale),
                value: error_log.platform || unknown,
                inline: true
              },
              *environment_fields(error_log, locale),
              {
                name: NotificationHelpers.label(:occurrences, locale),
                value: error_log.occurrence_count.to_s,
                inline: true
              },
              {
                name: NotificationHelpers.label(:controller, locale),
                value: error_log.controller_name || not_available,
                inline: true
              },
              {
                name: NotificationHelpers.label(:action, locale),
                value: error_log.action_name || not_available,
                inline: true
              },
              {
                name: NotificationHelpers.label(:first_seen, locale),
                value: NotificationHelpers.format_datetime_or_na(error_log.first_seen_at, locale),
                inline: true
              },
              {
                # Backtrace content is diagnostic output — never translated.
                name: NotificationHelpers.label(:location, locale),
                value: NotificationHelpers.extract_first_backtrace_line(error_log.backtrace, locale: locale),
                inline: false
              }
            ],
            footer: {
              text: NotificationHelpers.t("red.notifications.shared.product_name", locale)
            },
            timestamp: error_log.occurred_at.iso8601
          } ]
        }
      end

      # @param error_log [ErrorLog] The error
      # @return [Integer] Discord color integer
      # One field when the error carries an environment, none for a legacy row.
      def self.environment_fields(error_log, locale)
        return [] unless error_log.respond_to?(:environment) && error_log.environment.present?

        [ { name: NotificationHelpers.label(:environment, locale), value: error_log.environment, inline: true } ]
      end

      def self.severity_color(error_log)
        SEVERITY_COLORS[error_log.severity] || DEFAULT_COLOR
      end
    end
  end
end
