# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Shared helper methods for notification payload builders
    #
    # Pure functions: no side effects, no HTTP calls, no database access.
    # Used by all notification payload builders to avoid duplication.
    module NotificationHelpers
      module_function

      # Generate dashboard URL for an error
      # @param error_log [ErrorLog] The error
      # @return [String] Full URL to the error detail page
      def dashboard_url(error_log)
        base_url = RailsErrorDashboard.configuration.dashboard_base_url || "http://localhost:3000"
        "#{base_url}/error_dashboard/errors/#{error_log.id}"
      end

      # Truncate a message to a maximum length
      # @param message [String, nil] The message to truncate
      # @param length [Integer] Maximum length (default 500)
      # @return [String] Truncated message
      def truncate_message(message, length = 500)
        return "" unless message
        message.length > length ? "#{message[0...length]}..." : message
      end

      # Extract backtrace lines as an array
      # @param backtrace [String, Array, nil] Raw backtrace
      # @param limit [Integer] Maximum lines to extract (default 20)
      # @return [Array<String>] Backtrace lines
      def extract_backtrace(backtrace, limit = 20)
        return [] if backtrace.nil?

        lines = backtrace.is_a?(String) ? backtrace.lines : backtrace
        lines.first(limit).map(&:strip)
      end

      # Extract first backtrace line (truncated)
      # @param backtrace [String, Array, nil] Raw backtrace
      # @param length [Integer] Maximum length (default 100)
      # @return [String] First line or "N/A"
      def extract_first_backtrace_line(backtrace, length = 100)
        return "N/A" if backtrace.nil?

        lines = backtrace.is_a?(String) ? backtrace.lines : backtrace
        first_line = lines.first&.strip

        return "N/A" if first_line.nil?
        first_line.length > length ? "#{first_line[0...length]}..." : first_line
      end

      # Platform emoji for Slack/text notifications
      # @param platform [String, nil] Platform name
      # @return [String] Emoji
      def platform_emoji(platform)
        case platform&.downcase
        when "ios" then "📱"
        when "android" then "🤖"
        when "api" then "🔌"
        else "💻"
        end
      end

      # Format time for display
      # @param time [Time, nil] Time to format
      # @return [String] Formatted time or "N/A"
      def format_time(time)
        return "N/A" if time.nil?
        time.strftime("%Y-%m-%d %H:%M:%S UTC")
      end

      # Parse request params JSON safely
      # @param params_json [String, nil] JSON string
      # @return [Hash] Parsed params or empty hash
      def parse_request_params(params_json)
        return {} if params_json.nil?
        JSON.parse(params_json)
      rescue JSON::ParserError
        {}
      end

      # Error source description for PagerDuty
      # @param error_log [ErrorLog] The error
      # @return [String] Source description
      def error_source(error_log)
        if error_log.controller_name && error_log.action_name
          "#{error_log.controller_name}##{error_log.action_name}"
        elsif error_log.request_url
          error_log.request_url
        else
          error_log.platform || "Rails Application"
        end
      end
    end
  end
end
