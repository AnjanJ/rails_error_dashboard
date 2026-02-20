# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Generate consistent hash for error deduplication
    #
    # No database access — accepts exception data, returns a hash string.
    # Same hash = same error type for grouping purposes.
    #
    # Two entry points:
    # - `.call(exception, ...)` — used by LogError command (exception-based)
    # - `.from_attributes(...)` — used by ErrorLog model callback (attribute-based)
    #
    # @example
    #   ErrorHashGenerator.call(exception, controller_name: "users", action_name: "show", application_id: 1)
    #   # => "a1b2c3d4e5f6g7h8"
    class ErrorHashGenerator
      # Generate hash from an exception object (used by LogError command)
      # @param exception [Exception] The exception to hash
      # @param controller_name [String, nil] Controller context
      # @param action_name [String, nil] Action context
      # @param application_id [Integer, nil] Application for per-app deduplication
      # @param context [Hash] Full error context (passed to custom fingerprint lambda)
      # @return [String] 16-character hex hash
      def self.call(exception, controller_name: nil, action_name: nil, application_id: nil, context: {})
        # Check for custom fingerprint lambda
        custom = try_custom_fingerprint(exception, context)
        return custom if custom

        normalized_message = normalize_message(exception.message)
        file_path = extract_app_frame(exception.backtrace)

        digest_input = [
          exception.class.name,
          normalized_message,
          file_path,
          controller_name,
          action_name,
          application_id.to_s
        ].compact.join("|")

        Digest::SHA256.hexdigest(digest_input)[0..15]
      end

      # Generate hash from error attributes (used by ErrorLog model callback)
      # Uses ErrorNormalizer for smarter normalization and significant frame extraction
      # @param error_type [String] The error class name
      # @param message [String, nil] The error message
      # @param backtrace [String, nil] The backtrace as a string
      # @param controller_name [String, nil] Controller context
      # @param action_name [String, nil] Action context
      # @param application_id [Integer, nil] Application for per-app deduplication
      # @return [String] 16-character hex hash
      def self.from_attributes(error_type:, message: nil, backtrace: nil, controller_name: nil, action_name: nil, application_id: nil)
        normalized_message = ErrorNormalizer.normalize(message)
        significant_frames = ErrorNormalizer.extract_significant_frames(backtrace, count: 3)

        digest_input = [
          error_type,
          normalized_message,
          significant_frames,
          controller_name,
          action_name,
          application_id.to_s
        ].compact.join("|")

        Digest::SHA256.hexdigest(digest_input)[0..15]
      end

      # Normalize dynamic values in error messages for consistent hashing
      # @param message [String, nil] The error message
      # @return [String, nil] Normalized message
      def self.normalize_message(message)
        message
          &.gsub(/0x[0-9a-f]+/i, "HEX")          # Replace hex addresses (before numbers)
          &.gsub(/#<[^>]+>/, "#<OBJ>")           # Replace object inspections
          &.gsub(/\d+/, "N")                     # Replace numbers
          &.gsub(/"[^"]*"/, '""')                # Replace double-quoted strings
          &.gsub(/'[^']*'/, "''")                # Replace single-quoted strings
      end

      # Extract first meaningful app code frame from backtrace
      # @param backtrace [Array<String>, nil] Exception backtrace
      # @return [String, nil] File path of first app code frame
      def self.extract_app_frame(backtrace)
        return nil if backtrace.nil?

        first_app_frame = backtrace.find { |frame|
          !frame.include?("/gems/")
        }

        first_app_frame&.split(":")&.first
      end

      # Try custom fingerprint lambda if configured
      # Returns 16-char hex hash from custom key, or nil to fall back to default
      # @param exception [Exception] The exception
      # @param context [Hash] Error context
      # @return [String, nil] 16-character hex hash or nil
      def self.try_custom_fingerprint(exception, context)
        fingerprint_fn = RailsErrorDashboard.configuration.custom_fingerprint
        return nil unless fingerprint_fn

        result = fingerprint_fn.call(exception, context)
        return nil unless result.is_a?(String) && !result.empty?

        Digest::SHA256.hexdigest(result)[0..15]
      rescue => e
        RailsErrorDashboard::Logger.error(
          "[RailsErrorDashboard] Custom fingerprint lambda failed: #{e.class} - #{e.message}. " \
          "Falling back to default hash."
        )
        nil
      end
      private_class_method :try_custom_fingerprint
    end
  end
end
