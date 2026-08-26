# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Build PagerDuty Events API v2 payload
    #
    # No HTTP calls — accepts error data and routing key, returns a Hash.
    #
    # @example
    #   PagerdutyPayloadBuilder.call(error_log, routing_key: "abc123")
    #   # => { routing_key: "...", event_action: "trigger", ... }
    class PagerdutyPayloadBuilder
      # @param error_log [ErrorLog] The error to build a payload for
      # @param routing_key [String] PagerDuty integration key
      # @param locale [String] resolved by the enqueueing thread (P4-T1)
      # @return [Hash] PagerDuty Events API v2 payload
      #
      # ONLY "summary" AND THE LINK TEXT ARE LOCALIZED.
      #
      # event_action ("trigger") and severity ("critical") are PagerDuty API
      # enums, not adjectives — PagerDuty rejects any other value, so a
      # translated "critical" would drop the incident rather than localize it.
      # The custom_details keys are consumed by whatever the operator has wired
      # downstream, and "client" is RED's product name.
      def self.call(error_log, routing_key:, locale: I18nStore::DEFAULT_LOCALE)
        {
          routing_key: routing_key,
          event_action: "trigger",
          payload: {
            summary: NotificationHelpers.t(
              "red.notifications.error_alert.pagerduty_summary",
              locale,
              application: NotificationHelpers.app_name(error_log),
              error_type: error_log.error_type,
              platform: error_log.platform
            ),
            # API enum, not an adjective. Never translated.
            severity: "critical",
            source: NotificationHelpers.error_source(error_log),
            component: error_log.controller_name || NotificationHelpers.unknown(locale),
            group: error_log.error_type,
            class: error_log.error_type,
            custom_details: {
              application: NotificationHelpers.app_name(error_log),
              message: error_log.message,
              controller: error_log.controller_name,
              action: error_log.action_name,
              platform: error_log.platform,
              environment: error_log.environment,
              occurrences: error_log.occurrence_count,
              first_seen_at: error_log.first_seen_at&.iso8601,
              last_seen_at: error_log.last_seen_at&.iso8601,
              request_url: error_log.request_url,
              backtrace: NotificationHelpers.extract_backtrace(error_log.backtrace, 10),
              error_id: error_log.id
            }
          },
          links: [
            {
              href: NotificationHelpers.dashboard_url(error_log),
              text: NotificationHelpers.t("red.notifications.error_alert.view_in_dashboard", locale)
            }
          ],
          # Product name — not translated.
          client: NotificationHelpers.t("red.notifications.shared.product_name", locale),
          client_url: NotificationHelpers.dashboard_url(error_log)
        }
      end
    end
  end
end
