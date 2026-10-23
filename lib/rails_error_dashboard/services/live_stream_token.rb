# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # The token a live-updates subscription carries: one RED stream name, and
    # the time it stops being accepted.
    #
    # Turbo's own signed stream names never expire, and RED's names are
    # constants, so a Turbo token for one would work forever. These are signed
    # with a key derived from secret_key_base under RED's own salt and purpose,
    # so nothing turbo-rails or the host signs can pass for one. An open page
    # renews its tokens through the dashboard (ErrorsController#live_streams),
    # behind the dashboard's own authentication.
    #
    # Both methods return nil rather than raise: a token problem must cost the
    # page its live updates, never the page.
    class LiveStreamToken
      # How long a token is accepted. Short enough that losing dashboard access
      # ends a live feed within minutes; an open page renews at half of it.
      LIFETIME = 10.minutes

      SALT = "rails_error_dashboard/live_updates"
      PURPOSE = "rails_error_dashboard/live_updates"

      # A real token is about 200 bytes. Anything far longer is not one, and
      # is not worth an HMAC.
      MAX_TOKEN_BYTES = 1_024

      # @param stream [String] a name from ErrorBroadcaster.stream_name
      # @return [String, nil]
      def self.issue(stream)
        return nil unless red_stream?(stream)

        expires_at = Time.now.to_i + LIFETIME.to_i
        # The nonce keeps two tokens issued in the same second apart: Action
        # Cable ignores a second subscription with an identical identifier.
        payload = { "s" => stream, "e" => expires_at, "n" => SecureRandom.hex(8) }
        verifier.generate(payload, expires_at: Time.at(expires_at), purpose: PURPOSE)
      rescue StandardError
        nil
      end

      # @param token [Object] whatever the subscription request carried
      # @return [Hash{Symbol => Object}, nil] { stream:, expires_at: } (epoch seconds)
      def self.verify(token)
        # A Hash param makes MessageVerifier raise rather than refuse.
        return nil unless token.is_a?(String) && token.bytesize <= MAX_TOKEN_BYTES

        payload = verifier.verified(token, purpose: PURPOSE)
        return nil unless payload.is_a?(Hash)

        stream = payload["s"]
        expires_at = payload["e"]
        return nil unless red_stream?(stream) && expires_at.is_a?(Integer)
        return nil unless Time.now.to_i < expires_at

        { stream: stream, expires_at: expires_at }
      rescue StandardError
        nil
      end

      # For specs: forget the verifier, so a changed key takes effect.
      def self.reset!
        @verifier = nil
      end

      def self.red_stream?(stream)
        return false unless stream.is_a?(String)

        names = ErrorBroadcaster::STREAMS.values.map { |name| Regexp.escape(name) }
        stream.match?(/\A(?:#{names.join("|")})(?:_app_\d+)?\z/)
      end
      private_class_method :red_stream?

      # Only digest: and serializer: here: Rails 7.0 accepts nothing else.
      def self.verifier
        @verifier ||= ActiveSupport::MessageVerifier.new(
          Rails.application.key_generator.generate_key(SALT), digest: "SHA256", serializer: JSON
        )
      end
      private_class_method :verifier
    end
  end
end
