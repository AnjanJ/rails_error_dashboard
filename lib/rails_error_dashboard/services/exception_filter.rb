# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Determine if an exception should be logged
    #
    # No database access — checks configuration rules against exception data.
    # Used by LogError command to filter exceptions before logging.
    #
    # @example
    #   ExceptionFilter.should_log?(exception) # => true/false
    class ExceptionFilter
      # Check if an exception should be logged (not ignored, not sampled out)
      # @param exception [Exception] The exception to check
      # @return [Boolean] true if the exception should be logged
      def self.should_log?(exception)
        return false if ignored?(exception)
        return false if sampled_out?(exception)
        true
      end

      # Check if exception is in the ignored exceptions list
      # Supports both string class names and regex patterns
      # @param exception [Exception] The exception to check
      # @return [Boolean] true if the exception should be ignored
      def self.ignored?(exception)
        ignored_exceptions = RailsErrorDashboard.configuration.ignored_exceptions
        return false if ignored_exceptions.blank?

        exception_class_name = exception.class.name

        ignored_exceptions.any? do |ignored|
          case ignored
          when String
            exception.is_a?(ignored.constantize)
          when Regexp
            exception_class_name.match?(ignored)
          else
            false
          end
        rescue NameError
          RailsErrorDashboard::Logger.warn("Invalid ignored exception class: #{ignored}")
          false
        end
      end

      # Check if exception should be skipped due to sampling rate
      # Critical errors are ALWAYS logged regardless of sampling
      # @param exception [Exception] The exception to check
      # @return [Boolean] true if the exception should be skipped
      def self.sampled_out?(exception)
        sampling_rate = RailsErrorDashboard.configuration.sampling_rate

        return false if sampling_rate >= 1.0
        return false if critical?(exception)
        return true if sampling_rate <= 0.0

        rand > sampling_rate
      end

      # Check if exception is a critical error type
      # @param exception [Exception] The exception to check
      # @return [Boolean] true if the exception is critical
      def self.critical?(exception)
        SeverityClassifier.critical?(exception.class.name)
      end
    end
  end
end
