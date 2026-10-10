# frozen_string_literal: true

require "cgi"
require "erb"

module RailsErrorDashboard
  module Services
    # Pure algorithm: build the Telegram sendMessage payload for an error.
    #
    # No HTTP calls. Returns { text:, parse_mode:, disable_web_page_preview: };
    # TelegramDelivery adds the chat id, which is configuration, not content.
    #
    # WHY HTML AND NOT MARKDOWNV2: MarkdownV2 reserves eighteen characters,
    # every one of which must be escaped in every value, and a single
    # unescaped "_" in a class name like Net::OpenTimeout_Retry fails the
    # whole message with "can't parse entities". HTML mode needs only <, >
    # and & escaped, which ERB::Util.html_escape does. Telegram allows <b>,
    # <i>, <code>, <pre> and <a href>; nothing else is used here.
    #
    # @example
    #   TelegramPayloadBuilder.call(error_log)
    #   # => { text: "<b>🚨 Error Alert</b>\n...", parse_mode: "HTML", ... }
    class TelegramPayloadBuilder
      # Telegram rejects a text longer than this. The fields below are all
      # bounded (message 500, location 100, the rest short), so a message
      # built here is a few hundred characters; the fallback exists for the
      # one pathological row and sends the same content unformatted rather
      # than losing the notification to a parse error from a cut tag.
      MAX_TEXT_LENGTH = 4096
      MESSAGE_LENGTH = 500

      # @param error_log [ErrorLog]
      # @param locale [String] resolved by the enqueueing thread (P4-T1)
      # @return [Hash] sendMessage payload without chat_id
      def self.call(error_log, locale: I18nStore::DEFAULT_LOCALE)
        unknown = NotificationHelpers.unknown(locale)
        not_available = NotificationHelpers.not_available(locale)

        lines = [
          bold(NotificationHelpers.t("red.notifications.error_alert.heading", locale)),
          # error_type is an exception class name -- verbatim, escaped.
          bold(error_log.error_type),
          code(NotificationHelpers.truncate_message(error_log.message, MESSAGE_LENGTH)),
          "",
          field(:application, NotificationHelpers.app_name(error_log), locale),
          *environment_line(error_log, locale),
          field(:platform, error_log.platform || unknown, locale),
          field(:occurrences, error_log.occurrence_count.to_s, locale),
          field(:controller, error_log.controller_name || not_available, locale),
          field(:action, error_log.action_name || not_available, locale),
          field(:first_seen, NotificationHelpers.format_datetime_or_na(error_log.first_seen_at, locale), locale),
          # Backtrace content is diagnostic output -- never translated.
          field(:location, NotificationHelpers.extract_first_backtrace_line(error_log.backtrace, locale: locale), locale, code: true),
          "",
          link(NotificationHelpers.dashboard_url(error_log),
               NotificationHelpers.t("red.notifications.error_alert.view_in_dashboard", locale))
        ]

        html_payload(lines.join("\n"))
      end

      # "<b>Label:</b> value". The colon and the bold are Telegram markup, not
      # language, so they stay here rather than in each translation (same
      # reasoning as NotificationHelpers.field for Slack).
      def self.field(label, value, locale, code: false)
        rendered = code ? code(value) : escape(value)
        "#{bold("#{NotificationHelpers.label(label, locale)}:")} #{rendered}"
      end

      def self.environment_line(error_log, locale)
        return [] unless error_log.respond_to?(:environment) && error_log.environment.present?

        [ field(:environment, error_log.environment, locale) ]
      end

      def self.bold(text)
        "<b>#{escape(text)}</b>"
      end

      def self.code(text)
        "<code>#{escape(text)}</code>"
      end

      def self.link(url, text)
        %(<a href="#{escape(url)}">#{escape(text)}</a>)
      end

      # Plain String, not a SafeBuffer: these go into JSON, not a view.
      def self.escape(value)
        ERB::Util.html_escape(value.to_s).to_str
      end

      # The payload for an already-formatted HTML text, degrading to plain
      # text when it would not fit.
      def self.html_payload(text)
        if text.length > MAX_TEXT_LENGTH
          plain = CGI.unescapeHTML(text.gsub(/<[^>]+>/, ""))
          return { text: plain[0, MAX_TEXT_LENGTH], disable_web_page_preview: true }
        end

        { text: text, parse_mode: "HTML", disable_web_page_preview: true }
      end
    end
  end
end
