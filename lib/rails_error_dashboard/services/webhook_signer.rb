# frozen_string_literal: true

require "openssl"

module RailsErrorDashboard
  module Services
    # HMAC-SHA256 signatures for OUTBOUND webhooks (the ones RED sends to
    # config.webhook_urls). Inbound verification for GitHub/GitLab/Codeberg/
    # Linear lives in WebhooksController and is unrelated.
    #
    # Scheme, chosen to match what Stripe, Svix and GitHub receivers already
    # know how to check:
    #
    #   X-Error-Dashboard-Timestamp:     1718000000            (Unix seconds)
    #   X-Error-Dashboard-Signature-256: sha256=<hex>
    #
    #   hex = HMAC_SHA256(secret, "#{timestamp}.#{raw_body}")
    #
    # The timestamp is part of the signed string, not just a header, so a
    # captured request cannot be replayed later with a fresh timestamp. The
    # receiver verifies the digest over the RAW body it received (before
    # parsing JSON) and rejects timestamps outside its tolerance window.
    #
    # Pure functions, no I/O, nothing here can raise on well-typed input.
    class WebhookSigner
      TIMESTAMP_HEADER = "X-Error-Dashboard-Timestamp"
      SIGNATURE_HEADER = "X-Error-Dashboard-Signature-256"
      PREFIX = "sha256="

      # Default replay window for verifiers, in seconds. Five minutes is the
      # value Stripe and Svix document; it absorbs clock skew without leaving
      # a captured request useful for long.
      DEFAULT_TOLERANCE = 300

      class << self
        # Headers to merge into the outbound request.
        #
        # @param body [String] the exact bytes being sent
        # @param secret [String]
        # @param timestamp [Integer] Unix seconds; defaults to now
        # @return [Hash{String => String}]
        def headers_for(body, secret:, timestamp: Time.now.to_i)
          ts = timestamp.to_i
          {
            TIMESTAMP_HEADER => ts.to_s,
            SIGNATURE_HEADER => PREFIX + digest(body, secret: secret, timestamp: ts)
          }
        end

        # @return [String] lowercase hex HMAC over "#{timestamp}.#{body}"
        def digest(body, secret:, timestamp:)
          OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, "#{timestamp.to_i}.#{body}")
        end

        # Receiver-side check, offered so a Ruby receiver (and this gem's own
        # specs and docs) need not re-derive the scheme.
        #
        # @param body [String] raw request body
        # @param timestamp [String, Integer] value of X-Error-Dashboard-Timestamp
        # @param signature [String] value of X-Error-Dashboard-Signature-256
        # @param secret [String]
        # @param tolerance [Integer, nil] max age in seconds; nil skips the window check
        # @param now [Integer] injectable clock for tests
        # @return [Boolean]
        def valid?(body, timestamp:, signature:, secret:, tolerance: DEFAULT_TOLERANCE, now: Time.now.to_i)
          return false if secret.to_s.empty? || signature.to_s.empty?

          ts = Integer(timestamp.to_s, 10)
          return false if tolerance && (now - ts).abs > tolerance

          expected = PREFIX + digest(body, secret: secret, timestamp: ts)
          ActiveSupport::SecurityUtils.secure_compare(expected, signature.to_s)
        rescue ArgumentError, TypeError
          # A timestamp that is not an integer is a bad signature, not an error.
          false
        end
      end
    end
  end
end
