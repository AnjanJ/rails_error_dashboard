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
      # @return [Hash] Webhook payload
      def self.call(error_log)
        {
          event: "error.created",
          timestamp: Time.current.iso8601,
          error: {
            id: error_log.id,
            type: error_log.error_type,
            message: error_log.message,
            severity: error_log.severity.to_s,
            platform: error_log.platform,
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
