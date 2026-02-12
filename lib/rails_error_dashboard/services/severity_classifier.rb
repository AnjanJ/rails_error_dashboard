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
      ].freeze

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
    end
  end
end
