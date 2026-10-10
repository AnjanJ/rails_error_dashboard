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
    # BOOT CRASHES: the hook is registered from an engine initializer that
    # runs right after the host's config/initializers (so the configuration
    # is known) and before Rails' :eager_load! finisher. That ordering is the
    # whole point: a Zeitwerk::NameError from eager loading, a SyntaxError in
    # a model, an initializer that raised -- these kill the process before
    # config.after_initialize ever runs, so a hook registered there (as this
    # one was until 0.15) never saw them. A crash captured while
    # Rails.application.initialized? is still false is marked phase "boot",
    # imported with platform "boot_crash", and listed on the Boot Errors page.
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

      BOOT_PHASE = "boot"
      RUNTIME_PHASE = "runtime"
      BOOT_PLATFORM = "boot_crash"
      RUNTIME_PLATFORM = "crash_capture"

      # "expected file /app/app/models/foo.rb to define constant Foo, but didn't"
      ZEITWERK_MESSAGE = /expected file (?<file>.+?) to define constant (?<constant>\S+), but didn't/

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

          # Boot or runtime: a process that died before initialize! finished
          # never served a request, which is a different kind of outage.
          data[:phase] = boot_phase? ? BOOT_PHASE : RUNTIME_PHASE
          data[:boot] = boot_detail(exception) if data[:phase] == BOOT_PHASE

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

        # True while Rails is still running its initializers (eager loading
        # included). Rails.application.initialized? flips only after the last
        # finisher has run. Outside Rails (a plain Ruby script) there is no
        # boot phase to speak of.
        def boot_phase?
          defined?(Rails) && Rails.respond_to?(:application) && Rails.application &&
            !Rails.application.initialized?
        rescue
          false
        end

        # What a boot crash names, for the Boot Errors page: the file and the
        # constant for a Zeitwerk::NameError, else the first backtrace frame
        # under Rails.root (a SyntaxError or an initializer that raised).
        # Paths are made relative to Rails.root so the page reads
        # "app/models/foo.rb", not a deploy directory.
        def boot_detail(exception)
          detail = {}
          root = rails_root_prefix

          if exception.class.name == "Zeitwerk::NameError" && (m = ZEITWERK_MESSAGE.match(exception.message.to_s))
            detail[:file] = relative_path(m[:file], root)
            detail[:constant] = m[:constant]
          elsif (frame = Array(exception.backtrace).find { |f| root && f.to_s.start_with?(root) })
            detail[:file] = relative_path(frame.to_s.split(":in ").first, root)
          end

          detail
        rescue
          {}
        end

        def rails_root_prefix
          return nil unless defined?(Rails) && Rails.respond_to?(:root) && Rails.root

          "#{Rails.root}/"
        rescue
          nil
        end

        def relative_path(path, root)
          path = path.to_s
          root && path.start_with?(root) ? path.delete_prefix(root) : path
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

          boot = data["phase"] == BOOT_PHASE

          # Build environment_info from crash metadata
          env_info = {
            ruby_version: data["ruby_version"],
            rails_version: data["rails_version"],
            pid: data["pid"],
            thread_count: data["thread_count"],
            uptime_seconds: data["uptime_seconds"],
            gc: data["gc"],
            crash_captured_at: data["timestamp"],
            phase: data["phase"],
            boot: (data["boot"] if boot && data["boot"].is_a?(Hash) && data["boot"].any?),
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
            # Boot crashes get their own platform so the Boot Errors page and
            # the index's platform filter can find them.
            platform: boot ? BOOT_PLATFORM : RUNTIME_PLATFORM,
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

          # Through the same find-or-increment as every other capture: a crash
          # that repeats on every restart is one row with a count, not a new
          # row per restart -- and a plain create! collided with the unique
          # group-identity index on the second one, which left the file as
          # .failed and the crash unrecorded.
          if attributes[:error_hash]
            Commands::FindOrIncrementError.call(attributes[:error_hash], attributes)
          else
            ErrorLog.create!(attributes)
          end

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
