# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Filter sensitive data from error attributes before storage
    #
    # On by default. Redacts passwords, tokens, credit cards, SSNs, etc. using
    # built-in defaults + Rails' filter_parameters + custom patterns.
    # Set filter_sensitive_data = false to store raw data (you own your database).
    class SensitiveDataFilter
      FILTERED_REPLACEMENT = "[FILTERED]"

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

      # Filter sensitive data from error attributes hash
      # @param attributes [Hash] Error attributes to filter
      # @return [Hash] Filtered attributes (or original if filtering disabled/fails)
      def self.filter_attributes(attributes)
        return attributes unless RailsErrorDashboard.configuration.filter_sensitive_data

        filter = parameter_filter
        return attributes unless filter

        filtered = attributes.dup
        filtered[:request_params] = filter_json_string(filter, filtered[:request_params])
        filtered[:request_url] = filter_url(filter, filtered[:request_url])
        filtered[:message] = filter_message(filter, filtered[:message])
        filtered[:exception_cause] = filter_cause_chain(filter, filtered[:exception_cause])
        filtered
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] SensitiveDataFilter failed: #{e.message}")
        attributes
      end

      # Build and cache the ParameterFilter instance
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
        filtered = filter.filter(parsed)
        filtered.to_json
      rescue JSON::ParserError
        json_string
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] filter_json_string failed: #{e.message}")
        json_string
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
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] filter_url failed: #{e.message}")
        url
      end
      private_class_method :filter_url

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

        # Scrub credit card numbers from free text
        result.gsub(CREDIT_CARD_REGEX, FILTERED_REPLACEMENT)
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] filter_message failed: #{e.message}")
        message
      end
      private_class_method :filter_message

      # Filter messages within a cause chain JSON string
      # @param filter [ActiveSupport::ParameterFilter] The filter instance
      # @param cause_json [String, nil] JSON cause chain to filter
      # @return [String, nil] Filtered cause chain JSON
      def self.filter_cause_chain(filter, cause_json)
        return cause_json if cause_json.nil? || cause_json.empty?

        chain = JSON.parse(cause_json)
        return cause_json unless chain.is_a?(Array)

        filtered_chain = chain.map do |cause|
          cause = cause.dup
          cause["message"] = filter_message(filter, cause["message"]) if cause["message"]
          cause
        end

        filtered_chain.to_json
      rescue JSON::ParserError
        cause_json
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] filter_cause_chain failed: #{e.message}")
        cause_json
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
