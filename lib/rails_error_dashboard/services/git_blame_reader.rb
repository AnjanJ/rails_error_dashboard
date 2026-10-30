# frozen_string_literal: true

require "open3"

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
      KILL_GRACE = 1 # seconds a timed-out git gets to exit on TERM, and again on KILL
      READ_CHUNK = 16_384 # bytes
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

        stdout, stderr, status = run_with_deadline(cmd)

        unless status
          @error = "Git blame timeout"
          RailsErrorDashboard::Logger.warn("Git blame timeout for #{file_path}:#{line_number}")
          return nil
        end

        unless status.success?
          @error = "Git blame failed: #{stderr}"
          RailsErrorDashboard::Logger.debug("Git blame failed for #{file_path}:#{line_number} - #{stderr}")
          return nil
        end

        stdout
      rescue StandardError => e
        @error = "Git blame execution error: #{e.message}"
        RailsErrorDashboard::Logger.error("Git blame execution error for #{file_path}:#{line_number} - #{e.message}")
        nil
      end

      # Runs git in its own process group, against a monotonic deadline. Past
      # it, the group ends. Timeout.timeout would interrupt this thread and
      # leave git running in the host's process tree.
      #
      # Not popen3's block form: its cleanup joins the child with no limit, so a
      # git stuck in uninterruptible I/O would hold the request for ever.
      #
      # @return [Array(String, String, Process::Status), nil] nil at the deadline
      def run_with_deadline(cmd)
        deadline = monotonic_now + COMMAND_TIMEOUT
        options = Gem.win_platform? ? {} : { pgroup: true }
        stdin, stdout, stderr, wait_thread = Open3.popen3(*cmd, chdir: Rails.root, **options)
        stdin.close

        output = read_until(deadline, stdout, stderr)
        status = wait_thread.join([ deadline - monotonic_now, 0 ].max)&.value if output
        [ *output, status ] if status
      ensure
        # On no status, not on wait_thread.alive?: a git that has exited can
        # leave a child holding the pipes. An ensure, so that a host's own
        # request timeout raising into this thread ends git too.
        end_git(wait_thread) if wait_thread && !status
        [ stdin, stdout, stderr ].compact.each(&:close)
      end

      # Reads both pipes as they fill: reading one to its end first deadlocks
      # against a git blocked on writing to the other.
      #
      # @return [Array<String>, nil] each pipe's output, or nil at the deadline
      def read_until(deadline, *pipes)
        output = pipes.to_h { |pipe| [ pipe, String.new ] }
        open = pipes.dup

        until open.empty?
          remaining = deadline - monotonic_now
          return nil unless remaining.positive?

          ready, = IO.select(open, nil, nil, remaining)
          return nil unless ready

          ready.each do |pipe|
            chunk = pipe.read_nonblock(READ_CHUNK, exception: false)
            next if chunk == :wait_readable

            chunk ? output[pipe] << chunk : open.delete(pipe)
          end
        end

        output.values.map { |text| text.force_encoding(Encoding.default_external) }
      end

      # TERM, then KILL for whatever is left, to the group git leads: that
      # reaches git and anything it started, and nothing else. The wait thread
      # reaps git. No signal handler is touched.
      def end_git(wait_thread)
        signal_git("TERM", wait_thread.pid)
        wait_thread.join(KILL_GRACE)
        signal_git("KILL", wait_thread.pid)
        wait_thread.join(KILL_GRACE)
      end

      def signal_git(signal, pid)
        Process.kill(signal, Gem.win_platform? ? pid : -pid)
      rescue SystemCallError
        nil # already gone
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
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
