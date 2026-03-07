# frozen_string_literal: true

require "json"
require "tmpdir"
require "timeout"

module RailsErrorDashboard
  module Services
    # Last-resort crash capture via Ruby's `at_exit` hook.
    #
    # When the Rails process dies from an unhandled exception, the error never
    # reaches the error subscriber or middleware. This service registers an
    # `at_exit` hook that captures `$!` (the fatal exception) and writes it to
    # disk as JSON. On the next boot, `import!` reads crash files and creates
    # ErrorLog records with severity "fatal".
    #
    # Safety contract:
    # - Default OFF (opt-in via config.enable_crash_capture)
    # - Writes to tmpfile, NOT the database (connection pool may be closed)
    # - Timeout: 1 second max for file write, then give up
    # - Skips clean exits (SystemExit.success?, SignalException)
    # - Every operation wrapped in rescue (crash capture must never itself crash)
    # - Zero runtime overhead — hook only fires during process shutdown
    class CrashCapture
      FILE_PREFIX = "red_crash_"

      class << self
        # Enable crash capture. Registers the `at_exit` hook and records boot time.
        # @return [true]
        def enable!
          return true if enabled?

          @boot_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @enabled = true

          at_exit { capture!($!) }

          true
        end

        # Disable crash capture. The `at_exit` hook remains registered but will
        # no-op because `@enabled` is false.
        def disable!
          @enabled = false
        end

        # @return [Boolean] whether crash capture is enabled
        def enabled?
          @enabled == true
        end

        # Capture a fatal exception to disk. Called from the `at_exit` hook.
        # @param exception [Exception, nil] the fatal exception ($!)
        def capture!(exception)
          return unless @enabled
          return unless exception
          return if exception.is_a?(SystemExit) && exception.success?
          return if exception.is_a?(SignalException)

          crash_data = build_crash_data(exception)
          path = crash_file_path

          Timeout.timeout(1) do
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, JSON.generate(crash_data))
          end
        rescue => e
          # Crash capture must NEVER itself crash the exit.
          # Best-effort stderr warning (may not be visible).
          $stderr.puts "[RailsErrorDashboard] CrashCapture.capture! failed: #{e.class} - #{e.message}" rescue nil
        end

        # Import crash files from disk into the database. Called during boot
        # (config.after_initialize) BEFORE enable! so old crashes are processed first.
        def import!
          dir = crash_capture_dir
          return unless Dir.exist?(dir)

          pattern = File.join(dir, "#{FILE_PREFIX}*.json")
          Dir.glob(pattern).each do |file|
            import_crash_file(file)
          end
        rescue => e
          RailsErrorDashboard::Logger.debug(
            "[RailsErrorDashboard] CrashCapture.import! failed: #{e.class} - #{e.message}"
          )
        end

        # Reset internal state (for testing)
        def reset!
          @enabled = false
          @boot_time = nil
        end

        private

        def build_crash_data(exception)
          data = {
            exception_class: exception.class.name,
            message: exception.message.to_s[0, 10_000],
            backtrace: exception.backtrace&.first(50),
            timestamp: Time.now.utc.iso8601,
            pid: Process.pid,
            ruby_version: RUBY_VERSION,
            thread_count: Thread.list.count
          }

          # Rails version (may not be available during crash)
          data[:rails_version] = Rails.version if defined?(Rails) && Rails.respond_to?(:version)

          # Uptime
          if @boot_time
            data[:uptime_seconds] = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @boot_time).round(1)
          end

          # GC stats (safe, read-only, <1ms)
          data[:gc] = GC.stat rescue nil

          # Cause chain (up to 5 causes)
          data[:cause_chain] = extract_cause_chain(exception)

          data
        end

        def extract_cause_chain(exception)
          causes = []
          current = exception.cause
          5.times do
            break unless current
            causes << {
              exception_class: current.class.name,
              message: current.message.to_s[0, 2_000]
            }
            current = current.cause
          end
          causes
        end

        def crash_file_path
          File.join(crash_capture_dir, "#{FILE_PREFIX}#{Process.pid}.json")
        end

        def crash_capture_dir
          RailsErrorDashboard.configuration.crash_capture_path || Dir.tmpdir
        end

        def import_crash_file(file)
          raw = File.read(file)
          data = JSON.parse(raw)

          # Build attributes for ErrorLog
          backtrace = data["backtrace"]
          backtrace_text = backtrace.is_a?(Array) ? backtrace.join("\n") : backtrace.to_s

          cause_chain = data["cause_chain"]
          cause_json = cause_chain.is_a?(Array) && cause_chain.any? ? cause_chain.to_json : nil

          # Build environment_info from crash metadata
          env_info = {
            ruby_version: data["ruby_version"],
            rails_version: data["rails_version"],
            pid: data["pid"],
            thread_count: data["thread_count"],
            uptime_seconds: data["uptime_seconds"],
            gc: data["gc"],
            crash_captured_at: data["timestamp"],
            source: "crash_capture"
          }.compact

          # Resolve application (same as LogError does)
          app_name = RailsErrorDashboard.configuration.application_name ||
                     (defined?(Rails) && Rails.application ? Rails.application.class.module_parent_name : "Unknown")
          application = Commands::FindOrCreateApplication.call(app_name)

          occurred_at = parse_timestamp(data["timestamp"])

          attributes = {
            application_id: application.id,
            error_type: data["exception_class"] || "UnknownCrash",
            message: data["message"] || "Process crash captured via at_exit hook",
            backtrace: backtrace_text,
            occurred_at: occurred_at,
            platform: "crash_capture",
            resolved: false
          }

          # Add optional columns if they exist on the model
          if ErrorLog.column_names.include?("environment_info")
            attributes[:environment_info] = env_info.to_json
          end

          if ErrorLog.column_names.include?("exception_cause") && cause_json
            attributes[:exception_cause] = cause_json
          end

          if ErrorLog.column_names.include?("error_hash")
            attributes[:error_hash] = Services::ErrorHashGenerator.from_attributes(
              error_type: attributes[:error_type],
              message: attributes[:message],
              backtrace: backtrace_text,
              application_id: application.id
            )
          end

          if ErrorLog.column_names.include?("first_seen_at")
            attributes[:first_seen_at] = occurred_at
          end

          if ErrorLog.column_names.include?("last_seen_at")
            attributes[:last_seen_at] = occurred_at
          end

          ErrorLog.create!(attributes)

          # Delete file after successful import
          File.delete(file)
        rescue => e
          RailsErrorDashboard::Logger.debug(
            "[RailsErrorDashboard] CrashCapture.import_crash_file failed for #{file}: #{e.class} - #{e.message}"
          )
          # Rename to .failed to prevent infinite reimport while preserving data for debugging
          File.rename(file, "#{file}.failed") rescue nil
        end

        def parse_timestamp(ts)
          return Time.current unless ts
          Time.parse(ts).utc
        rescue
          Time.current
        end
      end
    end
  end
end
