# frozen_string_literal: true

require "coverage"

module RailsErrorDashboard
  module Services
    # Diagnostic-mode code path coverage using Ruby's Coverage API.
    #
    # Operator enables coverage via dashboard button, reproduces the error,
    # views source code with executed-line overlay, then disables.
    # Zero overhead when off. Uses oneshot_lines mode (each line fires once).
    #
    # SAFETY:
    # - Coverage is process-global (not thread-local) — data blends across threads
    # - oneshot_lines mode has near-zero ongoing overhead
    # - peek_result is read-only, does not mutate state
    # - Every method rescue-wrapped (never raises)
    # - Ruby 3.2+ required for Coverage.setup with oneshot_lines
    class CoverageTracker
      @active = false
      @we_started = false
      @mutex = Mutex.new

      class << self
        # Check if the current Ruby version supports Coverage with oneshot_lines
        def supported?
          RUBY_VERSION >= "3.2"
        end

        # Start coverage collection in oneshot_lines mode
        # @return [Boolean] true if successfully enabled
        def enable!
          return false unless supported?
          return true if @active

          @mutex.synchronize do
            return true if @active

            Coverage.setup(oneshot_lines: true)
            Coverage.resume
            @we_started = true
            @active = true
          end

          true
        rescue => e
          # Coverage.setup raises RuntimeError if another session is active (e.g. SimpleCov).
          # In that case, we piggyback on the existing session for peek_result.
          if e.is_a?(RuntimeError) && coverage_running?
            @mutex.synchronize do
              @we_started = false
              @active = true
            end
            true
          else
            Rails.logger.error("[RailsErrorDashboard] CoverageTracker.enable! failed: #{e.class}: #{e.message}")
            @active = false
            false
          end
        end

        # Stop coverage collection and clear all data
        def disable!
          return unless @active

          @mutex.synchronize do
            return unless @active
            # Only call Coverage.result if WE started the session
            # Don't kill another tool's coverage (e.g. SimpleCov)
            if @we_started
              begin
                Coverage.result
              rescue RuntimeError
                # Already stopped
              end
            end
            @active = false
            @we_started = false
          end
        rescue => e
          Rails.logger.error("[RailsErrorDashboard] CoverageTracker.disable! failed: #{e.class}: #{e.message}")
          @active = false
          @we_started = false
        end

        # Whether coverage is currently being collected
        def active?
          @active
        end

        # Get executed line numbers for a specific file
        # @param file_path [String] absolute path to the source file
        # @return [Hash{Integer => Boolean}] line_number => executed?, or nil if inactive
        def peek(file_path)
          return nil if file_path.nil?
          return nil unless @active

          result = Coverage.peek_result
          file_data = result[file_path]
          return {} unless file_data

          # Coverage result format varies by mode:
          # - oneshot_lines: { oneshot_lines: [nil, 0, nil, 1, ...] }
          # - lines (SimpleCov): { lines: [0, 1, nil, 2, ...] } or just [0, 1, nil, 2, ...]
          # where index = line_number - 1, nil = not executable, 0 = not hit, N>0 = hit
          lines_data = if file_data.is_a?(Hash)
            file_data[:oneshot_lines] || file_data[:lines]
          elsif file_data.is_a?(Array)
            file_data
          end
          return {} unless lines_data.is_a?(Array)

          executed = {}
          lines_data.each_with_index do |val, idx|
            next if val.nil? # not an executable line

            line_number = idx + 1
            executed[line_number] = val > 0
          end

          executed
        rescue => e
          Rails.logger.error("[RailsErrorDashboard] CoverageTracker.peek failed: #{e.class}: #{e.message}")
          {}
        end

        private

        # Check if Coverage is currently running (e.g. via SimpleCov)
        def coverage_running?
          Coverage.peek_result
          true
        rescue RuntimeError
          false
        end
      end
    end
  end
end
