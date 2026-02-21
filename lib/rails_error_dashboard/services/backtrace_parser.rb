# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Service: Parse and categorize backtrace frames
    # Filters out framework noise to show only relevant application code
    class BacktraceParser
      # Match both formats:
      # /path/file.rb:123:in `method'
      # /path/file.rb:123:in 'ClassName#method'
      FRAME_PATTERN = %r{^(.+):(\d+)(?::in [`'](.+)['`])?$}

      def self.parse(backtrace_string)
        new(backtrace_string).parse
      end

      # Convert Thread::Backtrace::Location objects to frame hashes
      # Uses structured data directly — no regex needed.
      # @param locations [Array<Thread::Backtrace::Location>, nil] Backtrace locations
      # @return [Array<Hash>] Parsed frames with same structure as .parse
      def self.from_locations(locations)
        return [] if locations.nil? || locations.empty?

        new(nil).send(:convert_locations, locations)
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] BacktraceParser.from_locations failed: #{e.message}")
        []
      end

      def initialize(backtrace_string)
        @backtrace_string = backtrace_string
      end

      def parse
        return [] if @backtrace_string.blank?

        lines = @backtrace_string.split("\n")
        lines.map.with_index do |line, index|
          parse_frame(line.strip, index)
        end.compact
      end

      private

      def convert_locations(locations)
        locations.map.with_index do |loc, index|
          file_path = loc.absolute_path || loc.path
          line_number = loc.lineno
          method_name = loc.label || "(unknown)"

          {
            index: index,
            file_path: file_path,
            line_number: line_number,
            method_name: method_name,
            category: categorize_frame(file_path),
            full_line: loc.to_s,
            short_path: shorten_path(file_path)
          }
        end
      end

      def parse_frame(line, index)
        match = line.match(FRAME_PATTERN)
        return nil unless match

        file_path = match[1]
        line_number = match[2].to_i
        method_name = match[3] || "(unknown)"

        {
          index: index,
          file_path: file_path,
          line_number: line_number,
          method_name: method_name,
          category: categorize_frame(file_path),
          full_line: line,
          short_path: shorten_path(file_path)
        }
      end

      def categorize_frame(file_path)
        # Application code (highest priority)
        return :app if app_code?(file_path)

        # Gem code (dependencies)
        return :gem if gem_code?(file_path)

        # Rails framework
        return :framework if rails_code?(file_path)

        # Ruby core/stdlib
        :ruby_core
      end

      def app_code?(file_path)
        # Match /app/, /lib/ directories in the application
        file_path.include?("/app/") ||
          (file_path.include?("/lib/") && !file_path.include?("/gems/") && !file_path.include?("/ruby/"))
      end

      def gem_code?(file_path)
        file_path.include?("/gems/") ||
          file_path.include?("/bundler/gems/") ||
          file_path.include?("/vendor/bundle/")
      end

      def rails_code?(file_path)
        file_path.include?("/railties-") ||
          file_path.include?("/actionpack-") ||
          file_path.include?("/actionview-") ||
          file_path.include?("/activerecord-") ||
          file_path.include?("/activesupport-") ||
          file_path.include?("/actioncable-") ||
          file_path.include?("/activejob-") ||
          file_path.include?("/actionmailer-") ||
          file_path.include?("/activestorage-") ||
          file_path.include?("/actionmailbox-") ||
          file_path.include?("/actiontext-") ||
          file_path.include?("/rails-")
      end

      def shorten_path(file_path)
        # Remove gem version numbers and long paths
        # /Users/.../.gem/ruby/3.4.0/gems/activerecord-8.0.4/lib/... → activerecord/.../file.rb
        if file_path.include?("/gems/")
          parts = file_path.split("/gems/").last
          gem_and_path = parts.split("/", 2)
          gem_name = gem_and_path.first.split("-").first # Remove version
          path_in_gem = gem_and_path.last
          "#{gem_name}/#{path_in_gem}"
        # /path/to/app/controllers/... → app/controllers/...
        elsif file_path.include?("/app/")
          file_path.split("/app/").last.prepend("app/")
        elsif file_path.include?("/lib/") && !file_path.include?("/ruby/")
          file_path.split("/lib/").last.prepend("lib/")
        else
          # Just show filename for Ruby core
          File.basename(file_path)
        end
      end
    end
  end
end
