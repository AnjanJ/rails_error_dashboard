# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Classify error severity based on error type
    #
    # No database access — accepts an error_type string, returns a severity symbol.
    # Checks custom severity rules from configuration first, then falls back
    # to built-in classification based on error type constants.
    class SeverityClassifier
      CRITICAL_ERROR_TYPES = %w[
        SecurityError
        NoMemoryError
        SystemStackError
        SignalException
        ActiveRecord::StatementInvalid
        LoadError
        SyntaxError
        ActiveRecord::ConnectionNotEstablished
        Redis::ConnectionError
        OpenSSL::SSL::SSLError
        Zeitwerk::NameError
        RailsErrorDashboard::TestError
      ].freeze
      # RailsErrorDashboard::TestError is the Settings page's Send Test Error.
      # The button promises delivery to every channel, and PagerDuty only
      # takes critical errors, so the test error is one.

      HIGH_SEVERITY_ERROR_TYPES = %w[
        ActiveRecord::RecordNotFound
        ArgumentError
        TypeError
        NoMethodError
        NameError
        ZeroDivisionError
        FloatDomainError
        IndexError
        KeyError
        RangeError
      ].freeze

      MEDIUM_SEVERITY_ERROR_TYPES = %w[
        ActiveRecord::RecordInvalid
        Timeout::Error
        Net::ReadTimeout
        Net::OpenTimeout
        ActiveRecord::RecordNotUnique
        JSON::ParserError
        CSV::MalformedCSVError
        Errno::ECONNREFUSED
      ].freeze

      # Classify the severity of an error type
      # @param error_type [String] The error class name
      # @return [Symbol] :critical, :high, :medium, or :low
      def self.classify(error_type)
        # Check custom severity rules first
        custom_severity = RailsErrorDashboard.configuration.custom_severity_rules[error_type]
        return custom_severity.to_sym if custom_severity.present?

        # Fall back to default classification
        return :critical if CRITICAL_ERROR_TYPES.include?(error_type)
        return :high if HIGH_SEVERITY_ERROR_TYPES.include?(error_type)
        return :medium if MEDIUM_SEVERITY_ERROR_TYPES.include?(error_type)

        :low
      end

      # Check if an error type is critical
      # @param error_type [String] The error class name
      # @return [Boolean]
      def self.critical?(error_type)
        classify(error_type) == :critical
      end

      BUILT_IN_TYPES = {
        critical: CRITICAL_ERROR_TYPES,
        high: HIGH_SEVERITY_ERROR_TYPES,
        medium: MEDIUM_SEVERITY_ERROR_TYPES
      }.freeze

      # The error types that classify as +severity+, for a SQL IN filter: the
      # built-in list for that level, minus any type a custom rule moves
      # elsewhere, plus any type a custom rule moves here. Filtering on the
      # bare constants showed CustomPaymentError => :critical under "low" and
      # a demoted built-in type still under "critical", while every badge on
      # the page said otherwise.
      #
      # :low has no list of its own (it is "everything else"); callers use
      # `where.not(error_type: categorized_error_types)` for it.
      #
      # @param severity [Symbol, String] :critical, :high or :medium
      # @return [Array<String>]
      def self.error_types_for(severity)
        level = severity.to_sym
        rules = custom_rules
        built_in = BUILT_IN_TYPES.fetch(level, [])

        (built_in - rules.keys) + rules.select { |_type, sev| sev == level }.keys
      end

      # Every error type that classifies as something other than :low, so
      # "low" is `where.not(error_type: categorized_error_types)`.
      # @return [Array<String>]
      def self.categorized_error_types
        rules = custom_rules
        built_in = BUILT_IN_TYPES.values.flatten
        promoted = rules.reject { |_type, sev| sev == :low }.keys
        demoted  = rules.select { |_type, sev| sev == :low }.keys

        (built_in - demoted) | promoted
      end

      # custom_severity_rules with String keys and Symbol values, whatever the
      # initializer used.
      def self.custom_rules
        (RailsErrorDashboard.configuration.custom_severity_rules || {})
          .to_h { |type, sev| [ type.to_s, sev.to_s.to_sym ] }
      rescue StandardError
        {}
      end
    end
  end
end
