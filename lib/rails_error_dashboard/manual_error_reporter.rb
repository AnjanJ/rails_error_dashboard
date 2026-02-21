# frozen_string_literal: true

module RailsErrorDashboard
  # ManualErrorReporter: Report errors manually from frontend, mobile apps, or custom sources
  #
  # This class provides a clean API for logging errors that don't originate from Ruby exceptions,
  # such as JavaScript errors from the frontend, mobile app crashes, or manually constructed errors.
  #
  # @example Frontend JavaScript error
  #   RailsErrorDashboard::ManualErrorReporter.report(
  #     error_type: "TypeError",
  #     message: "Cannot read property 'foo' of undefined",
  #     backtrace: ["at handleClick (app.js:42)", "at onClick (button.js:15)"],
  #     platform: "Web",
  #     user_id: current_user&.id,
  #     request_url: request.url,
  #     user_agent: request.user_agent,
  #     metadata: { component: "ShoppingCart", action: "checkout" }
  #   )
  #
  # @example Mobile app crash
  #   RailsErrorDashboard::ManualErrorReporter.report(
  #     error_type: "NSException",
  #     message: "Fatal crash in payment processing",
  #     backtrace: stacktrace_array,
  #     platform: "iOS",
  #     app_version: "2.1.0",
  #     user_id: user_id,
  #     metadata: { device: "iPhone 14", os_version: "17.2" }
  #   )
  class ManualErrorReporter
    # Report a manual error to the dashboard
    #
    # @param error_type [String] The error class/type (e.g., "TypeError", "NetworkError")
    # @param message [String] The error message
    # @param backtrace [Array<String>, String, nil] Stack trace as array of strings or newline-separated string
    # @param platform [String, nil] Platform where error occurred ("Web", "iOS", "Android", "API")
    # @param user_id [String, Integer, nil] ID of the user who experienced the error
    # @param request_url [String, nil] URL where the error occurred
    # @param user_agent [String, nil] User agent string
    # @param ip_address [String, nil] IP address of the requester
    # @param app_version [String, nil] Version of the app where error occurred
    # @param metadata [Hash, nil] Additional custom metadata about the error
    # @param occurred_at [Time, nil] When the error occurred (defaults to Time.current)
    # @param severity [Symbol, nil] Severity level (:critical, :high, :medium, :low)
    # @param source [String, nil] Source identifier (e.g., "frontend", "mobile_app")
    #
    # @return [ErrorLog, nil] The created error log record, or nil if filtered/ignored
    #
    # @example Basic usage
    #   ManualErrorReporter.report(
    #     error_type: "ValidationError",
    #     message: "Email format is invalid",
    #     platform: "Web"
    #   )
    #
    # @example With full context
    #   ManualErrorReporter.report(
    #     error_type: "PaymentError",
    #     message: "Credit card declined",
    #     backtrace: ["checkout.js:123", "payment.js:45"],
    #     platform: "Web",
    #     user_id: current_user.id,
    #     request_url: checkout_url,
    #     user_agent: request.user_agent,
    #     ip_address: request.remote_ip,
    #     app_version: "1.2.3",
    #     metadata: { card_type: "visa", amount: 99.99 },
    #     severity: :high
    #   )
    def self.report(
      error_type:,
      message:,
      backtrace: nil,
      platform: nil,
      user_id: nil,
      request_url: nil,
      user_agent: nil,
      ip_address: nil,
      app_version: nil,
      metadata: nil,
      occurred_at: nil,
      severity: nil,
      source: nil
    )
      # Create a synthetic exception object that quacks like a Ruby exception
      synthetic_exception = SyntheticException.new(
        error_type: error_type,
        message: message,
        backtrace: normalize_backtrace(backtrace)
      )

      # Build context hash for LogError
      context = {
        source: source || "manual",
        user_id: user_id,
        request_url: request_url,
        user_agent: user_agent,
        ip_address: ip_address,
        platform: platform,
        app_version: app_version,
        metadata: metadata,
        occurred_at: occurred_at || Time.current,
        severity: severity
      }.compact # Remove nil values

      # Use the existing LogError command
      Commands::LogError.call(synthetic_exception, context)
    end

    # Normalize backtrace to array of strings
    # @param backtrace [Array<String>, String, nil]
    # @return [Array<String>]
    private_class_method def self.normalize_backtrace(backtrace)
      return [] if backtrace.nil?
      return backtrace if backtrace.is_a?(Array)
      return backtrace.split("\n") if backtrace.is_a?(String)
      []
    end

    # SyntheticException: A fake exception object for manual error reporting
    #
    # This class mimics a Ruby Exception to work with the existing LogError command,
    # but represents errors from non-Ruby sources (frontend, mobile, etc.)
    #
    # @api private
    class SyntheticException
      attr_reader :message, :backtrace

      # @param error_type [String] The error class name
      # @param message [String] The error message
      # @param backtrace [Array<String>] The stack trace
      def initialize(error_type:, message:, backtrace:)
        @error_type = error_type
        @message = message
        @backtrace = backtrace
      end

      # SyntheticExceptions don't have real backtrace_locations (Ruby Thread::Backtrace::Location objects).
      # LogError calls this for backtrace_signature calculation — returning nil is safe.
      def backtrace_locations
        nil
      end

      # SyntheticExceptions don't have a cause chain.
      # LogError calls this for CauseChainExtractor — returning nil skips extraction.
      def cause
        nil
      end

      # Returns a mock class object that represents the error type
      # @return [Object] A class-like object with the error type as its name
      def class
        # Return a simple object that quacks like a class
        # This allows the error type to be stored correctly in the database
        @class ||= MockClass.new(@error_type)
      end

      # MockClass: A simple class-like object for error typing
      # @api private
      class MockClass
        def initialize(error_type)
          @error_type = error_type
        end

        def name
          @error_type
        end

        def to_s
          @error_type
        end
      end

      # Check if this is a specific error type
      # @param klass [Class, String] The class to check against
      # @return [Boolean]
      def is_a?(klass)
        return true if klass == self.class
        return true if klass == SyntheticException
        return true if klass.to_s == @error_type
        false
      end

      # Inspect for debugging
      # @return [String]
      def inspect
        "#<#{@error_type}: #{@message}>"
      end
    end

    # Namespace for dynamically created manual error classes
    # This keeps them separate from real Ruby exceptions
    module ManualErrors
    end
  end
end
