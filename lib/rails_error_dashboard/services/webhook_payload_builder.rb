# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Build generic webhook payload for error notifications
    #
    # No HTTP calls — accepts error data, returns a Hash ready for JSON serialization.
    #
    # @example
    #   WebhookPayloadBuilder.call(error_log)
    #   # => { event: "error.created", timestamp: "...", error: { ... } }
    class WebhookPayloadBuilder
      # @param error_log [ErrorLog] The error to build a payload for
      # @param locale [String] accepted so the signature matches its siblings
      # @return [Hash] Webhook payload
      #
      # DELIBERATELY NOT LOCALIZED (P4-T3 REQ-2, REQ-6).
      #
      # Every key here, and every value, is consumed by a program the operator
      # wrote — not read by a person. "error.created", the severity string, the
      # ISO8601 timestamps and the field names are an API contract; translating
      # any of them silently breaks whatever is parsing the payload. There is
      # no human-readable chrome in this payload to translate.
      #
      # The locale parameter exists so every builder has the same signature and
      # the dispatcher does not need to special-case this one.
      def self.call(error_log, locale: I18nStore::DEFAULT_LOCALE)
        _locale = locale

        {
          event: "error.created",
          timestamp: Time.current.iso8601,
          error: {
            id: error_log.id,
            application: NotificationHelpers.app_name(error_log),
            type: error_log.error_type,
            message: error_log.message,
            severity: error_log.severity.to_s,
            platform: error_log.platform,
            environment: error_log.environment,
            controller: error_log.controller_name,
            action: error_log.action_name,
            occurrence_count: error_log.occurrence_count,
            first_seen_at: error_log.first_seen_at&.iso8601,
            last_seen_at: error_log.last_seen_at&.iso8601,
            occurred_at: error_log.occurred_at.iso8601,
            resolved: error_log.resolved,
            request: {
              url: error_log.request_url,
              params: NotificationHelpers.parse_request_params(error_log.request_params),
              user_agent: error_log.user_agent,
              ip_address: error_log.ip_address
            },
            user: {
              id: error_log.user_id
            },
            backtrace: NotificationHelpers.extract_backtrace(error_log.backtrace),
            metadata: {
              error_hash: error_log.error_hash,
              dashboard_url: NotificationHelpers.dashboard_url(error_log)
            }
          }
        }
      end
    end
  end
end
