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
      # @return [Hash] PagerDuty Events API v2 payload
      def self.call(error_log, routing_key:)
        {
          routing_key: routing_key,
          event_action: "trigger",
          payload: {
            summary: "Critical Error: #{error_log.error_type} in #{error_log.platform}",
            severity: "critical",
            source: NotificationHelpers.error_source(error_log),
            component: error_log.controller_name || "Unknown",
            group: error_log.error_type,
            class: error_log.error_type,
            custom_details: {
              message: error_log.message,
              controller: error_log.controller_name,
              action: error_log.action_name,
              platform: error_log.platform,
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
              text: "View in Error Dashboard"
            }
          ],
          client: "Rails Error Dashboard",
          client_url: NotificationHelpers.dashboard_url(error_log)
        }
      end
    end
  end
end
