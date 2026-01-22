# frozen_string_literal: true

require "open3"
require "timeout"

module RailsErrorDashboard
  module Services
    # Reads git blame information for specific file lines
    # Executes git blame command and parses porcelain output
    #
    # @example
    #   reader = GitBlameReader.new("/path/to/file.rb", 42)
    #   blame = reader.read_blame
    #   # => { author: "John Doe", email: "john@example.com", date: Time, sha: "abc123", line: "code" }
    class GitBlameReader
      COMMAND_TIMEOUT = 5 # seconds
      PORCELAIN_FIELDS = %w[
        author
        author-mail
        author-time
        author-tz
        committer
        committer-mail
        committer-time
        committer-tz
        summary
        filename
      ].freeze

      attr_reader :file_path, :line_number, :error

      # Initialize a new git blame reader
      #
      # @param file_path [String] Path to the source file
      # @param line_number [Integer] Target line number
      def initialize(file_path, line_number)
        @file_path = file_path
        @line_number = line_number.to_i
        @error = nil
      end

      # Read git blame information for the target line
      #
      # @return [Hash, nil] Blame data hash or nil if unavailable
      def read_blame
        unless git_available?
          @error = "Git not available"
          return nil
        end

        unless File.exist?(file_path)
          @error = "File not found"
          return nil
        end

        # Execute git blame command
        output = execute_git_blame
        return nil unless output

        # Parse porcelain format output
        parse_blame_output(output)
      rescue StandardError => e
        @error = "Error reading git blame: #{e.message}"
        RailsErrorDashboard::Logger.error("GitBlameReader error for #{file_path}:#{line_number} - #{e.message}")
        nil
      end

      # Check if git is available on the system
      #
      # @return [Boolean]
      def git_available?
        @git_available ||= begin
          _stdout, _stderr, status = Open3.capture3("git", "--version")
          status.success?
        rescue StandardError
          false
        end
      end

      private

      # Execute git blame command for the specific line
      #
      # @return [String, nil] Command output or nil if failed
      def execute_git_blame
        # Build command array (prevents command injection)
        cmd = [
          "git",
          "blame",
          "-L", "#{line_number},#{line_number}",
          "--porcelain",
          "--", # Separator
          file_path
        ]

        # Execute with timeout
        stdout, stderr, status = Timeout.timeout(COMMAND_TIMEOUT) do
          Open3.capture3(*cmd, chdir: Rails.root)
        end

        unless status.success?
          @error = "Git blame failed: #{stderr}"
          RailsErrorDashboard::Logger.debug("Git blame failed for #{file_path}:#{line_number} - #{stderr}")
          return nil
        end

        stdout
      rescue Timeout::Error
        @error = "Git blame timeout"
        RailsErrorDashboard::Logger.warn("Git blame timeout for #{file_path}:#{line_number}")
        nil
      rescue StandardError => e
        @error = "Git blame execution error: #{e.message}"
        RailsErrorDashboard::Logger.error("Git blame execution error for #{file_path}:#{line_number} - #{e.message}")
        nil
      end

      # Parse git blame porcelain format output
      #
      # Git blame --porcelain format:
      # <sha> <line_number> <final_line_number> <num_lines>
      # author <author_name>
      # author-mail <<author_email>>
      # author-time <unix_timestamp>
      # author-tz <timezone>
      # committer <committer_name>
      # committer-mail <<committer_email>>
      # committer-time <unix_timestamp>
      # committer-tz <timezone>
      # summary <commit_message_summary>
      # filename <filename>
      # <TAB><line_content>
      #
      # @param output [String] Git blame porcelain output
      # @return [Hash, nil] Parsed blame data
      def parse_blame_output(output)
        return nil if output.blank?

        lines = output.split("\n")
        return nil if lines.empty?

        # First line contains commit SHA and line info
        first_line = lines[0]
        match = first_line.match(/^([0-9a-f]+)\s+(\d+)\s+(\d+)/)
        unless match
          @error = "Incomplete git blame data"
          return nil
        end

        sha = match[1]
        data = { sha: sha }

        # Parse subsequent lines
        lines[1..].each do |line|
          # Check for field: value lines
          PORCELAIN_FIELDS.each do |field|
            if line.start_with?("#{field} ")
              value = line.sub("#{field} ", "")

              case field
              when "author"
                data[:author] = value
              when "author-mail"
                # Remove < and > brackets
                data[:email] = value.gsub(/[<>]/, "")
              when "author-time"
                # Convert Unix timestamp to Time object
                data[:date] = Time.at(value.to_i)
              when "summary"
                data[:commit_message] = value
              end
            end
          end

          # Line content starts with tab
          if line.start_with?("\t")
            data[:line] = line.sub("\t", "")
          end
        end

        # Validate required fields
        if data[:author].present? && data[:sha].present?
          data
        else
          @error = "Incomplete git blame data"
          nil
        end
      rescue StandardError => e
        @error = "Error parsing git blame output: #{e.message}"
        RailsErrorDashboard::Logger.error("Git blame parsing error: #{e.message}")
        nil
      end
    end
  end
end
