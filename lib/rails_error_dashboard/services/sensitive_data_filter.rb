# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Filter sensitive data from error attributes before storage
    #
    # On by default. Redacts passwords, tokens, credit cards, SSNs, etc. using
    # built-in defaults + Rails' filter_parameters + custom patterns.
    # Set filter_sensitive_data = false to store raw data (you own your database).
    #
    # Fails closed: a step that breaks stores FILTERED_REPLACEMENT for its field,
    # never the raw value it was meant to clean. Free-text redaction is
    # best-effort: it recognises the shapes in filter_message, not every secret.
    class SensitiveDataFilter
      FILTERED_REPLACEMENT = "[FILTERED]"

      # The fields filter_attributes cleans.
      FILTERED_FIELDS = %i[request_params request_url message exception_cause].freeze

      # Default patterns that ALWAYS apply when filtering is enabled.
      # These cover data that has no debugging value and should never be stored.
      DEFAULT_SENSITIVE_PATTERNS = [
        # Passwords
        :password, :password_confirmation, :passphrase, :passwd,
        # API keys & tokens
        :token, :access_token, :refresh_token, :auth_token, :api_token,
        :api_key, :api_secret, :secret, :secret_key, :private_key,
        # Financial
        :credit_card, :card_number, :cc_number, :cvv, :cvc, :csv,
        # Personal identifiers
        :ssn, :social_security,
        # Session & auth
        :session_id, :session_key, :cookie,
        # 2FA / OTP
        :otp, :totp, :pin
      ].freeze

      # Regex to detect credit card numbers in free text (4 groups of 4 digits)
      CREDIT_CARD_REGEX = /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/

      # More free-text shapes. Each runs on untrusted text on the capture path,
      # so each is linear: a word-boundary or quote anchor, and no nested
      # quantifiers. The key decides, through the same filter as everything
      # else, so filter_parameters, custom patterns and procs all apply.
      #   key: value     (value bare, "double" or 'single' quoted)
      KEY_COLON_VALUE = /\b(\w+)(:[ \t]*)("[^"\n]*"|'[^'\n]*'|[^\s,;)\]}]+)/
      #   "key": "value" or "key": value -- JSON, including JSON::ParserError text
      JSON_PAIR = /"(\w+)"(\s*:\s*)("(?:[^"\\\n]|\\.)*"|[^\s,}\]]+)/
      #   Bearer <token>
      BEARER_TOKEN = /\b(Bearer)\s+[A-Za-z0-9\-._~+\/]+=*/i
      #   ?key=value pairs, for a query string Rack can't parse
      QUERY_PAIR = /([?&;])([^&;=#\s]+)=([^&;#\s]*)/

      # Filter sensitive data from error attributes hash
      # @param attributes [Hash] Error attributes to filter
      # @return [Hash] Filtered attributes (original if filtering is disabled;
      #   FILTERED_REPLACEMENT in every filtered field if filtering can't run)
      def self.filter_attributes(attributes)
        return attributes unless RailsErrorDashboard.configuration.filter_sensitive_data

        filter = parameter_filter
        return withhold(attributes) unless filter

        filtered = attributes.dup
        filtered[:request_params] = filter_json_string(filter, filtered[:request_params])
        filtered[:request_url] = filter_url(filter, filtered[:request_url])
        filtered[:message] = filter_message(filter, filtered[:message])
        filtered[:exception_cause] = filter_cause_chain(filter, filtered[:exception_cause])
        filtered
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] SensitiveDataFilter failed: #{e.message}")
        withhold(attributes)
      end

      # Fail closed: when filtering can't run at all, store none of what it was
      # meant to clean. Absent and nil fields stay as they are.
      # @param attributes [Hash]
      # @return [Hash]
      def self.withhold(attributes)
        return {} unless attributes.is_a?(Hash)

        FILTERED_FIELDS.each_with_object(attributes.dup) do |key, withheld|
          withheld[key] = FILTERED_REPLACEMENT unless withheld[key].nil?
        end
      end
      private_class_method :withhold

      SESSION_DIGEST_PREFIX = "h1:"
      SESSION_DIGEST_FORMAT = /\Ah1:\h{32}\z/

      # Keyed digest of a session ID, for storage.
      #
      # A session ID is a bearer credential, and the only thing the dashboard does
      # with it is equality ("these occurrences were one session"). An HMAC keeps
      # that and is useless for replay; keying it with secret_key_base means a
      # guessed ID cannot be confirmed offline either. The prefix tells a digest
      # from a raw Rails session ID (itself 32 hex characters), which makes
      # digesting idempotent and leaves room for an "h2:".
      #
      # Rotating secret_key_base breaks correlation across the rotation.
      #
      # @param raw [#to_s, nil] raw session ID, or an existing digest
      # @return [String, nil] "h1:" + 32 hex characters; nil for blank input or on
      #   any failure (never the raw value, never an exception)
      def self.digest_session_id(raw)
        value = raw.to_s
        return nil if value.empty?
        # Exact shape only: a raw value that merely starts with "h1:" is digested.
        return value if value.match?(SESSION_DIGEST_FORMAT)

        SESSION_DIGEST_PREFIX + OpenSSL::HMAC.hexdigest("SHA256", session_digest_key, value)[0, 32]
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] Session ID digest failed: #{e.class}")
        nil
      end

      # What to write to error_occurrences.session_id: the digest while filtering
      # is on, the raw value when the operator has turned filtering off.
      def self.storable_session_id(raw)
        return digest_session_id(raw) if RailsErrorDashboard.configuration.filter_sensitive_data

        raw.nil? ? nil : raw.to_s
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] Session ID handling failed: #{e.class}")
        nil
      end

      def self.session_digest_key
        key = Rails.application.secret_key_base if defined?(Rails) && Rails.application.respond_to?(:secret_key_base)
        key.to_s.empty? ? "rails_error_dashboard" : key.to_s
      rescue StandardError
        "rails_error_dashboard"
      end

      # @return [ActiveSupport::ParameterFilter, nil]
      def self.parameter_filter
        @parameter_filter ||= build_parameter_filter
      end

      # Clear cached filter (for testing or config changes)
      def self.reset!
        @parameter_filter = nil
      end

      # Filter a JSON string by parsing, filtering the hash, and re-serializing
      # @param filter [ActiveSupport::ParameterFilter] The filter instance
      # @param json_string [String, nil] JSON string to filter
      # @return [String, nil] Filtered JSON string
      def self.filter_json_string(filter, json_string)
        return json_string if json_string.nil? || json_string.empty?

        parsed = JSON.parse(json_string)
        # ParameterFilter takes a Hash; an array (or a bare value) is wrapped
        # so it is filtered too, nested hashes included.
        filtered = parsed.is_a?(Hash) ? filter.filter(parsed) : filter.filter("params" => parsed)["params"]
        filtered.to_json
      rescue JSON::ParserError
        # Not JSON -- a caller's own serialisation, a cut body. An input shape,
        # not a filter failure: the same rules as a message.
        filter_message(filter, json_string)
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] filter_json_string failed: #{e.message}")
        FILTERED_REPLACEMENT
      end
      private_class_method :filter_json_string

      # Filter query string parameters in a URL
      # @param filter [ActiveSupport::ParameterFilter] The filter instance
      # @param url [String, nil] URL to filter
      # @return [String, nil] URL with filtered query parameters
      def self.filter_url(filter, url)
        return url if url.nil? || !url.include?("?")

        path, query = url.split("?", 2)
        return url if query.nil? || query.empty?

        params = Rack::Utils.parse_query(query)
        filtered_params = filter.filter(params)
        filtered_query = Rack::Utils.build_query(filtered_params)
        "#{path}?#{filtered_query}"
      rescue => e
        # Rack refuses the query (a stray %, a bad escape): redact it pair by
        # pair instead of keeping the URL as it came.
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] filter_url failed: #{e.message}")
        redact_query(filter, url)
      end
      private_class_method :filter_url

      # @return [String] the URL with each sensitive pair's value replaced
      def self.redact_query(filter, url)
        url.gsub(QUERY_PAIR) do
          separator, key, value = Regexp.last_match(1), Regexp.last_match(2), Regexp.last_match(3)
          name = begin
            URI.decode_www_form_component(key)
          rescue ArgumentError
            key
          end
          "#{separator}#{key}=#{sensitive_key?(filter, name) ? FILTERED_REPLACEMENT : value}"
        end
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] redact_query failed: #{e.message}")
        FILTERED_REPLACEMENT
      end
      private_class_method :redact_query

      # Filter key=value patterns in a message string
      # @param filter [ActiveSupport::ParameterFilter] The filter instance
      # @param message [String, nil] Message to filter
      # @return [String, nil] Message with filtered values
      def self.filter_message(filter, message)
        return message if message.nil? || message.empty?

        # Extract key=value patterns and filter them
        result = message.gsub(/(\w+)=(\S+)/) do |_match|
          key = Regexp.last_match(1)
          value = Regexp.last_match(2)
          filtered = filter.filter(key => value)
          "#{key}=#{filtered[key]}"
        end

        result = result.gsub(JSON_PAIR) do
          key, separator = Regexp.last_match(1), Regexp.last_match(2)
          sensitive_key?(filter, key) ? %("#{key}"#{separator}"#{FILTERED_REPLACEMENT}") : Regexp.last_match(0)
        end

        result = result.gsub(KEY_COLON_VALUE) do
          key, separator = Regexp.last_match(1), Regexp.last_match(2)
          sensitive_key?(filter, key) ? "#{key}#{separator}#{FILTERED_REPLACEMENT}" : Regexp.last_match(0)
        end

        result = result.gsub(BEARER_TOKEN) { "#{Regexp.last_match(1)} #{FILTERED_REPLACEMENT}" }

        # Scrub credit card numbers from free text
        result.gsub(CREDIT_CARD_REGEX, FILTERED_REPLACEMENT)
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] filter_message failed: #{e.message}")
        FILTERED_REPLACEMENT
      end
      private_class_method :filter_message

      # Whether the filter would redact a value under this key.
      def self.sensitive_key?(filter, key)
        filter.filter(key => "")[key] == FILTERED_REPLACEMENT
      end
      private_class_method :sensitive_key?

      # Filter messages within a cause chain JSON string
      # @param filter [ActiveSupport::ParameterFilter] The filter instance
      # @param cause_json [String, nil] JSON cause chain to filter
      # @return [String, nil] Filtered cause chain JSON
      def self.filter_cause_chain(filter, cause_json)
        return cause_json if cause_json.nil? || cause_json.empty?

        chain = JSON.parse(cause_json)
        return filter_message(filter, cause_json) unless chain.is_a?(Array)

        filtered_chain = chain.map do |cause|
          cause = cause.dup
          cause["message"] = filter_message(filter, cause["message"]) if cause["message"]
          cause
        end

        filtered_chain.to_json
      rescue JSON::ParserError
        # Not JSON: an input shape, not a filter failure.
        filter_message(filter, cause_json)
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] filter_cause_chain failed: #{e.message}")
        FILTERED_REPLACEMENT
      end
      private_class_method :filter_cause_chain

      # Build an ActiveSupport::ParameterFilter from Rails config + custom patterns
      # @return [ActiveSupport::ParameterFilter, nil]
      def self.build_parameter_filter
        # Always start with default patterns (passwords, tokens, credit cards, etc.)
        patterns = DEFAULT_SENSITIVE_PATTERNS.dup

        # Rails' built-in filter_parameters
        if defined?(Rails) && Rails.application&.config&.respond_to?(:filter_parameters)
          patterns.concat(Array(Rails.application.config.filter_parameters))
        end

        # Custom patterns from gem config
        custom = RailsErrorDashboard.configuration.sensitive_data_patterns
        patterns.concat(Array(custom)) if custom

        patterns.uniq!

        ActiveSupport::ParameterFilter.new(patterns)
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] build_parameter_filter failed: #{e.message}")
        nil
      end
      private_class_method :build_parameter_filter
    end
  end
end
