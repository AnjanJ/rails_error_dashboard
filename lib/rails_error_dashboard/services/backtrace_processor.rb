# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm service for backtrace processing
    # Handles truncation and signature generation with no database access.
    class BacktraceProcessor
      # Truncate backtrace to a maximum number of lines
      # @param backtrace [Array<String>, nil] The backtrace lines
      # @param max_lines [Integer] Maximum lines to keep
      # @return [String, nil] Truncated backtrace as a single string
      def self.truncate(backtrace, max_lines: nil)
        return nil if backtrace.nil?

        max_lines ||= RailsErrorDashboard.configuration.max_backtrace_lines

        limited_backtrace = backtrace.first(max_lines)
        result = limited_backtrace.join("\n")

        if backtrace.length > max_lines
          truncation_notice = "... (#{backtrace.length - max_lines} more lines truncated)"
          result = result.empty? ? truncation_notice : result + "\n" + truncation_notice
        end

        result
      end

      # Calculate a signature hash from backtrace for fuzzy similarity matching
      # Extracts file paths and method names, ignoring line numbers,
      # then produces an order-independent SHA256 digest.
      # @param backtrace [String, Array<String>, nil] The backtrace
      # @param locations [Array<Thread::Backtrace::Location>, nil] Optional structured locations
      # @return [String, nil] 16-character hex signature
      def self.calculate_signature(backtrace, locations: nil)
        # Try structured locations first (more reliable, no regex)
        if locations && !locations.empty?
          return signature_from_locations(locations)
        end

        return nil if backtrace.blank?

        lines = backtrace.is_a?(String) ? backtrace.split("\n") : backtrace
        frames = lines.first(20).map do |line|
          if line =~ %r{([^/]+\.rb):.*?in `(.+)'$}
            "#{Regexp.last_match(1)}:#{Regexp.last_match(2)}"
          elsif line =~ %r{([^/]+\.rb)}
            Regexp.last_match(1)
          end
        end.compact.uniq

        return nil if frames.empty?

        file_paths = frames.map { |frame| frame.split(":").first }.sort
        Digest::SHA256.hexdigest(file_paths.join("|"))[0..15]
      end

      # Calculate signature directly from Location objects
      # @param locations [Array<Thread::Backtrace::Location>] Backtrace locations
      # @return [String, nil] 16-character hex signature
      def self.signature_from_locations(locations)
        frames = locations.first(20).map do |loc|
          path = loc.absolute_path || loc.path
          next nil unless path&.end_with?(".rb")
          file_name = File.basename(path)
          method_name = loc.label
          method_name ? "#{file_name}:#{method_name}" : file_name
        end.compact.uniq

        return nil if frames.empty?

        file_paths = frames.map { |frame| frame.split(":").first }.sort
        Digest::SHA256.hexdigest(file_paths.join("|"))[0..15]
      rescue => e
        RailsErrorDashboard::Logger.debug(
          "[RailsErrorDashboard] signature_from_locations failed: #{e.message}"
        )
        nil
      end
      private_class_method :signature_from_locations
    end
  end
end
