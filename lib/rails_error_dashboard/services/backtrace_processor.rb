# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm service for backtrace processing
    # Handles truncation and signature generation with no database access.
    class BacktraceProcessor
      # Truncate backtrace to a maximum number of lines and shorten gem paths.
      #
      # Gem paths like:
      #   /home/user/.local/share/mise/installs/ruby/4.0.2/lib/ruby/gems/4.0.0/gems/actionpack-8.1.3/lib/...
      # are shortened to:
      #   gems/actionpack-8.1.3/lib/...
      #
      # This saves significant disk space without losing debugging value (issue #115).
      #
      # @param backtrace [Array<String>, nil] The backtrace lines
      # @param max_lines [Integer] Maximum lines to keep
      # @return [String, nil] Truncated backtrace as a single string
      def self.truncate(backtrace, max_lines: nil)
        return nil if backtrace.nil?

        max_lines ||= RailsErrorDashboard.configuration.max_backtrace_lines

        limited_backtrace = backtrace.first(max_lines).map { |line| shorten_gem_path(line) }
        result = limited_backtrace.join("\n")

        if backtrace.length > max_lines
          truncation_notice = "... (#{backtrace.length - max_lines} more lines truncated)"
          result = result.empty? ? truncation_notice : result + "\n" + truncation_notice
        end

        result
      end

      # Shorten gem/ruby paths to remove user-specific prefixes.
      # Preserves gem name + version for debugging.
      #
      # Examples:
      #   /home/user/.gem/ruby/3.4.0/gems/rack-3.2.6/lib/rack/head.rb:15
      #   → gems/rack-3.2.6/lib/rack/head.rb:15
      #
      #   /home/user/.local/share/mise/installs/ruby/4.0.2/lib/ruby/4.0.0/net/http.rb:1234
      #   → ruby/4.0.0/net/http.rb:1234
      #
      #   /home/user/myapp/app/controllers/users_controller.rb:10
      #   → app/controllers/users_controller.rb:10
      #
      # @param line [String] A single backtrace line
      # @return [String] The line with shortened path
      def self.shorten_gem_path(line)
        # Strip everything before /gems/ (gem code)
        if line.include?("/gems/")
          line.sub(%r{^.*/gems/}, "gems/")
        # Strip everything before /lib/ruby/ (Ruby stdlib)
        elsif line.include?("/lib/ruby/")
          line.sub(%r{^.*/lib/ruby/}, "ruby/")
        # Strip everything before /app/ (application code)
        elsif line.include?("/app/")
          line.sub(%r{^.*/app/}, "app/")
        # Strip everything before /lib/ for app lib code (but not gem/ruby paths already handled)
        elsif line.include?("/lib/")
          line.sub(%r{^.*/lib/}, "lib/")
        else
          line
        end
      end
      # Keep public — used by LogError for cause chain backtrace shortening too.

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
