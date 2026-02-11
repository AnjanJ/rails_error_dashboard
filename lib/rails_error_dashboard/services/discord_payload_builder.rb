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
      # @return [Hash] Discord embed payload
      def self.call(error_log)
        {
          embeds: [ {
            title: "🚨 New Error: #{error_log.error_type}",
            description: NotificationHelpers.truncate_message(error_log.message, 200),
            color: severity_color(error_log),
            fields: [
              {
                name: "Platform",
                value: error_log.platform || "Unknown",
                inline: true
              },
              {
                name: "Occurrences",
                value: error_log.occurrence_count.to_s,
                inline: true
              },
              {
                name: "Controller",
                value: error_log.controller_name || "N/A",
                inline: true
              },
              {
                name: "Action",
                value: error_log.action_name || "N/A",
                inline: true
              },
              {
                name: "First Seen",
                value: NotificationHelpers.format_time(error_log.first_seen_at),
                inline: true
              },
              {
                name: "Location",
                value: NotificationHelpers.extract_first_backtrace_line(error_log.backtrace),
                inline: false
              }
            ],
            footer: {
              text: "Rails Error Dashboard"
            },
            timestamp: error_log.occurred_at.iso8601
          } ]
        }
      end

      # @param error_log [ErrorLog] The error
      # @return [Integer] Discord color integer
      def self.severity_color(error_log)
        SEVERITY_COLORS[error_log.severity] || DEFAULT_COLOR
      end
    end
  end
end
