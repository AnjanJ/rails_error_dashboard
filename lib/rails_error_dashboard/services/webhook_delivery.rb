# frozen_string_literal: true

require "net/http"
require "uri"

module RailsErrorDashboard
  module Services
    # One POST to a custom webhook URL (config.webhook_urls), signed when
    # config.webhook_signing_secret is set.
    #
    # WHY ONE PLACE: three jobs post to webhook_urls (per-error notifications,
    # storm/burst-summary messages, baseline alerts) and each carried its own
    # copy of the HTTP code. The signature must be computed over the exact
    # bytes on the wire, so the body is serialised once here and the same
    # string is both signed and sent. Slack, Discord and PagerDuty keep their
    # own senders: their payloads are not ours to sign.
    #
    # It also applies the contract in docs/WEBHOOKS.md: version on every body,
    # and the event and error headers read from that body. Here rather than in
    # each builder, because a builder that forgot them is how three of the four
    # events ended up with no event header. 1.x may add to the contract, but
    # never rename or remove anything in it.
    #
    # Errors propagate. Every caller already rescues around its send and logs
    # in its own words (the specs pin those messages), so swallowing here would
    # only hide the failure from them.
    class WebhookDelivery
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10
      USER_AGENT = "RailsErrorDashboard/1.0"
      CONTRACT_VERSION = 1

      class << self
        # @param url [String]
        # @param payload [Hash] serialised with #to_json, with version added
        # @param headers [Hash{String => String}] merged over the defaults. The
        #   contract's headers win: they come from the body, so they can't disagree
        # @return [HTTParty::Response, Net::HTTPResponse]
        def post(url, payload, headers: {})
          body = { version: CONTRACT_VERSION }.merge(payload).to_json
          all_headers = { "Content-Type" => "application/json", "User-Agent" => USER_AGENT }
            .merge(headers)
            .merge(contract_headers(payload))
            .merge(signature_headers(body))

          if defined?(HTTParty)
            HTTParty.post(url, body: body, headers: all_headers, timeout: READ_TIMEOUT)
          else
            uri = URI(url)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == "https"
            http.open_timeout = OPEN_TIMEOUT
            http.read_timeout = READ_TIMEOUT
            # request_uri, not path: a webhook URL that carries a query string
            # (a token, a channel id) used to lose it on this branch.
            request = Net::HTTP::Post.new(uri.request_uri, all_headers)
            request.body = body
            http.request(request)
          end
        end

        # The event, and the error when the body is about one.
        def contract_headers(payload)
          event = payload[:event]
          Rails.logger.warn("[RailsErrorDashboard] Webhook body has no event: the contract needs one") if event.blank?

          { "X-Error-Dashboard-Event" => event.presence, "X-Error-Dashboard-ID" => payload.dig(:error, :id)&.to_s }.compact
        end

        # Signature headers for +body+, or {} when no secret is configured.
        def signature_headers(body)
          secret = RailsErrorDashboard.configuration.webhook_signing_secret
          return {} if secret.blank?

          WebhookSigner.headers_for(body, secret: secret)
        end
      end
    end
  end
end
