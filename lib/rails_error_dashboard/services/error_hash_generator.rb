# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Generate consistent hash for error deduplication
    #
    # No database access — accepts exception data, returns a hash string.
    # Same hash = same error type for grouping purposes.
    #
    # @example
    #   ErrorHashGenerator.call(exception, controller_name: "users", action_name: "show", application_id: 1)
    #   # => "a1b2c3d4e5f6g7h8"
    class ErrorHashGenerator
      # @param exception [Exception] The exception to hash
      # @param controller_name [String, nil] Controller context
      # @param action_name [String, nil] Action context
      # @param application_id [Integer, nil] Application for per-app deduplication
      # @return [String] 16-character hex hash
      def self.call(exception, controller_name: nil, action_name: nil, application_id: nil)
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
    end
  end
end
