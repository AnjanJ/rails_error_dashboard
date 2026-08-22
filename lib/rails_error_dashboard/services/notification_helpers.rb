# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Shared helper methods for notification payload builders
    #
    # Pure functions: no side effects, no HTTP calls, no database access.
    # Used by all notification payload builders to avoid duplication.
    module NotificationHelpers
      module_function

      # Translate for a notification payload.
      #
      # Positional locale rather than the ambient one: a payload is built
      # inside a job, where Current.locale is nil at best and an unrelated
      # request's value at worst (P4-T1). Every builder threads the locale it
      # was handed.
      #
      # No escaping — these values go into JSON, not HTML.
      #
      # @return [String] never nil, never raises
      def t(key, locale, **options)
        I18nStore.translate(key, locale: locale, **options)
      end

      # A "*Label:*\nvalue" Slack mrkdwn field.
      #
      # The bold-label-newline-value shape is Slack markup, not language, so it
      # stays here rather than being baked into each translation — a translator
      # editing "*%{label}:*" could break the formatting for every field at
      # once. Only the label itself is translated.
      #
      # @param label [Symbol] a key under red.notifications.error_alert.labels
      def field(label, value, locale)
        "*#{t("red.notifications.error_alert.labels.#{label}", locale)}:*\n#{value}"
      end

      # One label from red.notifications.error_alert.labels.
      #
      # Discord wants a bare field name, Slack wants it wrapped in its mrkdwn
      # bold-and-newline shape — hence this and #field rather than one method.
      #
      # @param label [Symbol]
      def label(label, locale)
        t("red.notifications.error_alert.labels.#{label}", locale)
      end

      # @return [String] the localized "Unknown" placeholder
      def unknown(locale)
        t("red.notifications.shared.unknown", locale)
      end

      # @return [String] the localized "N/A" placeholder
      def not_available(locale)
        t("red.notifications.shared.not_available", locale)
      end

      # A human-readable timestamp for a notification body.
      #
      # Uses the locale's date format and month names rather than strftime's,
      # which are always English (see MailerI18nHelper for the same problem).
      # Falls back to the machine format if anything goes wrong — a wrong-looking
      # timestamp is better than a lost notification.
      #
      # @return [String] "" for nil
      def format_datetime(time, locale)
        return "" if time.nil?

        utc = time.respond_to?(:utc) ? time.utc : time
        pattern = I18nStore.translate("red.time.formats.full", locale: locale)
        # A miss returns humanized key text, which would be a nonsense strftime
        # pattern. Detect it the same way red_time_format does.
        pattern = I18nStore.translate("red.time.formats.full", locale: I18nStore::DEFAULT_LOCALE) unless pattern.include?("%")

        LocalizedTimeFormatter.call(utc, pattern: pattern, locale: locale)
      rescue StandardError
        format_time(time)
      end

      # A localized timestamp, or the localized "N/A" for nil.
      def format_datetime_or_na(time, locale)
        return not_available(locale) if time.nil?

        format_datetime(time, locale)
      end

      # Generate dashboard URL for an error
      # @param error_log [ErrorLog] The error
      # @return [String] Full URL to the error detail page
      def dashboard_url(error_log)
        base_url = (RailsErrorDashboard.configuration.dashboard_base_url || "http://localhost:3000").chomp("/")
        mount_path = RailsErrorDashboard.configuration.engine_mount_path

        # Avoid doubling the mount path when base_url already includes it.
        # e.g., base_url="https://app.com/red" + mount_path="/red" → don't produce "/red/red"
        if mount_path.present? && base_url.end_with?(mount_path.chomp("/"))
          "#{base_url}/errors/#{error_log.id}"
        else
          "#{base_url}#{mount_path}/errors/#{error_log.id}"
        end
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
      #
      # The line itself is diagnostic output and is never translated — only the
      # "N/A" shown in its absence is, and only when a locale is supplied.
      # Callers that pass no locale keep the literal, so existing non-i18n
      # callers are unaffected.
      #
      # @param backtrace [String, Array, nil] Raw backtrace
      # @param length [Integer] Maximum length (default 100)
      # @param locale [String, nil] locale for the placeholder
      # @return [String] First line, or the "N/A" placeholder
      def extract_first_backtrace_line(backtrace, length = 100, locale: nil)
        placeholder = locale ? not_available(locale) : "N/A"
        return placeholder if backtrace.nil?

        lines = backtrace.is_a?(String) ? backtrace.lines : backtrace
        first_line = lines.first&.strip

        return placeholder if first_line.nil?
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

      # Application name for notifications
      # @param error_log [ErrorLog] The error
      # @return [String] Application name or "Unknown"
      def app_name(error_log)
        error_log.application&.name || "Unknown"
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
