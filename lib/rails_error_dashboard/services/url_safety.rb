# frozen_string_literal: true

require "uri"

module RailsErrorDashboard
  module Services
    # Pure algorithm: decide whether a string is safe to use as a link target
    #
    # A URL that ends up in an `href` must be absolute http(s). Rails' `link_to`
    # and ERB escaping stop attribute breakout, but neither rejects a scheme such
    # as `javascript:` — that has to be an allowlist, and it has to be the same
    # rule where the value is written and where it is rendered.
    #
    # The value is judged exactly as given (no stripping), so what passes here is
    # byte-for-byte what the caller goes on to store or render.
    #
    # @example
    #   UrlSafety.http_url?("https://github.com/a/b/issues/1") # => true
    #   UrlSafety.http_url?("javascript:alert(1)")             # => false
    class UrlSafety
      # Browsers strip TAB/CR/LF from inside a URL before resolving the scheme,
      # so "java\tscript:" is live. No legitimate URL contains these or a space.
      UNSAFE_CHARACTERS = /[[:cntrl:][:space:]]/

      # @param value [String, nil]
      # @return [Boolean] true only for an absolute http:// or https:// URL with a host
      def self.http_url?(value)
        return false unless value.is_a?(String)
        return false if value.empty? || value.match?(UNSAFE_CHARACTERS)

        uri = URI.parse(value)
        # URI::HTTPS is a subclass of URI::HTTP
        uri.is_a?(URI::HTTP) && uri.host.present?
      rescue URI::InvalidURIError, ArgumentError, EncodingError
        # ArgumentError/EncodingError: a string with invalid bytes cannot be matched
        false
      end
    end
  end
end
