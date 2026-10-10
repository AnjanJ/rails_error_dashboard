# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module RailsErrorDashboard
  module Services
    # One sendMessage call to the Telegram Bot API.
    #
    # WHY ONE PLACE: four senders post to Telegram (per-error notifications,
    # storm and burst-summary messages, baseline alerts). The bot token is part
    # of the URL -- https://api.telegram.org/bot<token>/sendMessage -- so any
    # log line that quotes the URL, or an exception message that carries it,
    # would leak the credential. Building the URL and redacting it live here
    # so no caller has to remember either.
    #
    # Transport errors propagate, as in WebhookDelivery: every caller already
    # rescues around its send and logs in its own words. Callers pass the
    # message through .redact before logging it. A non-2xx answer from
    # Telegram is not an exception; it is logged here with Telegram's own
    # description ("Bad Request: chat not found"), which is the line an
    # operator needs when the chat id is wrong.
    class TelegramDelivery
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10
      USER_AGENT = "RailsErrorDashboard/1.0"
      REDACTED = "[FILTERED]"

      class << self
        # Enabled and credentialled: the condition under which a dispatcher
        # fires this channel.
        def configured?(config = RailsErrorDashboard.configuration)
          config.enable_telegram_notifications && credentials?(config)
        end

        # Token and chat id both present. The jobs check this rather than
        # configured?, like the Discord job checks its URL and not the flag:
        # the dispatcher decided to enqueue; the job only needs the means.
        def credentials?(config = RailsErrorDashboard.configuration)
          config.telegram_bot_token.present? && config.telegram_chat_id.present?
        end

        # POST a prepared sendMessage payload ({ text:, parse_mode:, ... }).
        # chat_id is configuration, not content, so it is merged here rather
        # than built into every payload.
        #
        # @return [HTTParty::Response, Net::HTTPResponse, nil] nil when there
        #   are no credentials to send with
        def post(payload, config: RailsErrorDashboard.configuration)
          return nil unless credentials?(config)

          body = payload.merge(chat_id: config.telegram_chat_id).to_json
          headers = { "Content-Type" => "application/json", "User-Agent" => USER_AGENT }
          url = send_message_url(config)

          response =
            if defined?(HTTParty)
              HTTParty.post(url, body: body, headers: headers, timeout: READ_TIMEOUT)
            else
              uri = URI(url)
              http = Net::HTTP.new(uri.host, uri.port)
              http.use_ssl = uri.scheme == "https"
              http.open_timeout = OPEN_TIMEOUT
              http.read_timeout = READ_TIMEOUT
              request = Net::HTTP::Post.new(uri.request_uri, headers)
              request.body = body
              http.request(request)
            end

          log_rejection(response)
          response
        end

        # A plain or HTML-formatted message with nothing else to it (storm and
        # burst summaries). parse_mode: nil sends the text verbatim, which is
        # right for a sentence that may contain a "<" from an app name.
        def send_message(text, parse_mode: nil, config: RailsErrorDashboard.configuration)
          payload = { text: text, disable_web_page_preview: true }
          payload[:parse_mode] = parse_mode if parse_mode

          post(payload, config: config)
        end

        # The bot token replaced wherever it appears in +string+ (an exception
        # message that quotes the URL, a response body that echoes it).
        def redact(string, config: RailsErrorDashboard.configuration)
          token = config.telegram_bot_token.to_s
          text = string.to_s
          return text if token.empty?

          text.gsub(token, REDACTED)
        end

        # The URL with the token replaced, for log lines that need to say
        # where the POST went.
        def redacted_url(config = RailsErrorDashboard.configuration)
          redact(send_message_url(config), config: config)
        end

        private

        def send_message_url(config)
          base = config.telegram_api_base_url.to_s.strip
          base = "https://api.telegram.org" if base.empty?

          "#{base.chomp('/')}/bot#{config.telegram_bot_token}/sendMessage"
        end

        # Telegram answers 4xx with {"ok":false,"error_code":400,"description":"..."}.
        # The description names the real problem (chat not found, bot was
        # blocked, can't parse entities), so it goes in the log verbatim; the
        # body never contains the token, but it is redacted anyway.
        def log_rejection(response)
          code = response.code.to_i
          return if (200..299).cover?(code)

          description = begin
            JSON.parse(response.body.to_s)["description"]
          rescue JSON::ParserError, TypeError
            nil
          end

          Rails.logger.error(
            "[RailsErrorDashboard] Telegram API rejected the message (HTTP #{code}): " \
            "#{redact(description || response.body.to_s[0, 200])}"
          )
        rescue => e
          Rails.logger.error("[RailsErrorDashboard] Telegram API response could not be read: #{e.class}")
        end
      end
    end
  end
end
