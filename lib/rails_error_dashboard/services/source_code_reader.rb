# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Reads source code files from disk with security validation
    # and context lines around a target line number
    #
    # @example
    #   reader = SourceCodeReader.new("/path/to/app/models/user.rb", 42)
    #   lines = reader.read_lines(context: 5)
    #   # Returns array of hashes with line numbers and content
    class SourceCodeReader
      MAX_FILE_SIZE = 10 * 1024 * 1024 # 10 MB
      MAX_CONTEXT_LINES = 50

      # The files a Ruby backtrace can point to: Ruby source and view templates.
      # A frame's path is whatever the stored backtrace says, and the files
      # beside the code (config/*.yml, logs, dotfiles) are where secrets live.
      RUBY_EXTENSIONS = %w[.rb .rake .ru].freeze
      # Templates only under an app/ directory (app/views, app/components, an
      # engine's app/): elsewhere .erb is configuration, as in config/database.yml.erb.
      TEMPLATE_EXTENSIONS = %w[.erb .haml .slim .builder .jbuilder].freeze
      NOT_AVAILABLE = "File not found or not readable"

      attr_reader :file_path, :line_number, :error

      # Initialize a new source code reader
      #
      # @param file_path [String] Path to the source file
      # @param line_number [Integer] Target line number
      def initialize(file_path, line_number)
        @file_path = file_path
        @line_number = line_number.to_i
        @error = nil
      end

      # Read source code lines with context around the target line
      #
      # @param context [Integer] Number of lines before and after target line
      # @return [Array<Hash>, nil] Array of line data hashes or nil if unavailable
      def read_lines(context: 5)
        context = [ [ context, MAX_CONTEXT_LINES ].min, 1 ].max

        # Validate and resolve path
        absolute_path = resolve_absolute_path
        unless absolute_path
          @error = NOT_AVAILABLE if file_path.present?
          return nil
        end

        # Validate path is safe
        unless validate_path!(absolute_path)
          @error = "Invalid or unsafe file path"
          return nil
        end

        # Check file exists and is readable
        unless File.exist?(absolute_path) && File.readable?(absolute_path)
          @error = NOT_AVAILABLE
          return nil
        end

        # Check file size
        file_size = File.size(absolute_path)
        if file_size > MAX_FILE_SIZE
          @error = "File too large (#{file_size} bytes, max #{MAX_FILE_SIZE})"
          return nil
        end

        # Check if file is binary
        if binary_file?(absolute_path)
          @error = "Binary file cannot be displayed"
          return nil
        end

        # Read the specific lines
        read_specific_lines(absolute_path, line_number - context, line_number + context)
      rescue StandardError => e
        @error = "Error reading file: #{e.message}"
        RailsErrorDashboard::Logger.error("SourceCodeReader error for #{file_path}:#{line_number} - #{e.message}")
        nil
      end

      # Check if file exists on disk
      #
      # @return [Boolean]
      def file_exists?
        absolute_path = resolve_absolute_path
        return false unless absolute_path

        File.exist?(absolute_path) && File.readable?(absolute_path)
      rescue StandardError
        false
      end

      private

      # Resolve file path to absolute path within Rails.root
      #
      # @return [String, nil] Absolute path or nil if invalid
      def resolve_absolute_path
        return nil if file_path.blank?

        # Handle relative paths from backtrace
        if file_path.start_with?(File.join(Rails.root, ""))
          # Already absolute
          file_path
        elsif file_path.start_with?("/")
          # Absolute but from a different root (an earlier deploy)
          map_outside_path
        else
          # Relative path
          File.join(Rails.root, file_path)
        end
      end

      # A frame recorded before a deploy names the same app-relative file under
      # this root. Each trailing part of its path is tried, longest first, so the
      # earliest segment that fits wins. The basename alone is never tried: that
      # would match a file only by name. validate_path! still judges the result.
      #
      # @return [String, nil] Path of the existing file, or nil
      def map_outside_path
        segments = file_path.split("/").reject(&:empty?)
        return nil if segments.intersect?(%w[. ..])

        (0...segments.size - 1)
          .map { |start| File.join(Rails.root, *segments[start..]) }
          .find { |candidate| File.file?(candidate) }
      end

      # Validate path is safe to read (security check)
      #
      # @param path [String] Absolute path to validate
      # @return [Boolean]
      # @raise [SecurityError] if path is unsafe
      def validate_path!(path)
        # Normalize path
        normalized = File.expand_path(path)
        root_prefix = File.join(File.expand_path(Rails.root), "")

        # Must be within Rails.root. The trailing separator matters: without it
        # a root of /app also admitted /app-old.
        unless normalized.start_with?(root_prefix)
          RailsErrorDashboard::Logger.warn("Path outside Rails.root: #{normalized}")
          return false
        end

        # Source files only, and nothing under a dot directory (.git, .bundle)
        segments = normalized.delete_prefix(root_prefix).split("/")
        extension = File.extname(normalized).downcase
        source = RUBY_EXTENSIONS.include?(extension) ||
          (TEMPLATE_EXTENSIONS.include?(extension) && segments[0...-1].include?("app"))
        hidden = segments.any? { |segment| segment.start_with?(".") }
        if !source || hidden
          RailsErrorDashboard::Logger.warn("Not a source file: #{normalized}")
          return false
        end

        # Prevent directory traversal
        if path.include?("..") || normalized.include?("..")
          RailsErrorDashboard::Logger.warn("Directory traversal attempt: #{path}")
          return false
        end

        # Check against sensitive file patterns
        sensitive_patterns = [
          /\.env/i,
          /secrets\.yml$/i,
          /credentials\.yml/i,
          /database\.yml$/i,
          /master\.key$/i,
          /private_key/i,
          /\.pem$/i,
          /\.key$/i
        ]

        if sensitive_patterns.any? { |pattern| normalized.match?(pattern) }
          RailsErrorDashboard::Logger.warn("Attempt to read sensitive file: #{normalized}")
          return false
        end

        # Only show app code if configured
        if RailsErrorDashboard.configuration.only_show_app_code_source
          # Block gem/vendor code
          blocked_patterns = [
            %r{/gems/},
            %r{/vendor/bundle/},
            %r{/vendor/ruby/},
            %r{/.bundle/}
          ]

          if blocked_patterns.any? { |pattern| normalized.match?(pattern) }
            RailsErrorDashboard::Logger.debug("Skipping gem/vendor code: #{normalized}")
            return false
          end
        end

        true
      end

      # Read specific lines from file
      #
      # @param file_path [String] Path to file
      # @param start_line [Integer] First line to read (1-indexed)
      # @param end_line [Integer] Last line to read (1-indexed)
      # @return [Array<Hash>] Array of line data
      def read_specific_lines(file_path, start_line, end_line)
        start_line = [ start_line, 1 ].max
        lines = []

        File.open(file_path, "r") do |file|
          file.each_line.with_index(1) do |line, line_num|
            break if line_num > end_line

            next if line_num < start_line

            lines << {
              number: line_num,
              content: line.chomp,
              highlight: line_num == @line_number
            }
          end
        end

        lines
      rescue StandardError => e
        RailsErrorDashboard::Logger.error("Error reading specific lines from #{file_path}: #{e.message}")
        []
      end

      # Check if file is binary
      #
      # @param file_path [String] Path to file
      # @return [Boolean]
      def binary_file?(file_path)
        # Read first 8KB to check for null bytes
        sample_size = 8192
        File.open(file_path, "rb") do |file|
          sample = file.read(sample_size)
          return false if sample.nil? || sample.empty?

          # Binary files typically contain null bytes
          sample.include?("\x00")
        end
      rescue StandardError
        false # If we can't determine, assume text
      end
    end
  end
end
