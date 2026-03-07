# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # TracePoint lifecycle manager for detecting swallowed (raised-then-rescued) exceptions.
    #
    # Uses separate TracePoint(:raise) and TracePoint(:rescue) hooks (Ruby 3.3+).
    # Counts raises vs rescues per exception class + location pair. A high rescue ratio
    # indicates exceptions being silently swallowed (e.g., `rescue => e; nil`).
    #
    # This is intentionally SEPARATE from LocalVariableCapturer — that TracePoint aggressively
    # filters to only app-code paths, while this one needs broader visibility to detect
    # swallowed exceptions in gem code too (e.g., Stripe::CardError rescued in a service).
    #
    # Safety contract:
    # - Default OFF (opt-in via config.detect_swallowed_exceptions)
    # - Ruby 3.3+ version gate (TracePoint(:rescue) not available before 3.3)
    # - Thread-local counters (no shared state, no mutex in hot path)
    # - ~500ns per raise/rescue (hash lookup + integer increment)
    # - Zero I/O in callbacks — async flush via Command
    # - Every callback wrapped in rescue => e (never raises)
    # - LRU eviction when thread-local cache exceeds max size
    # - Periodic flush via cheap timestamp check
    class SwallowedExceptionTracker
      RAISE_THREAD_KEY  = :red_swallowed_raises
      RESCUE_THREAD_KEY = :red_swallowed_rescues
      FLUSH_THREAD_KEY  = :red_swallowed_last_flush
      RAISE_LOC_IVAR    = :@_red_raise_loc

      # Flow-control exceptions that are commonly raised/rescued in normal Rails operation.
      # These are NOT bugs — they're control flow. Skipping them reduces noise.
      FLOW_CONTROL_EXCEPTIONS = %w[
        SystemExit
        SignalException
        Interrupt
        Errno::EPIPE
        Errno::ECONNRESET
        Errno::ETIMEDOUT
        IOError
        ActionController::RoutingError
        ActionController::UnknownFormat
        ActionController::InvalidAuthenticityToken
        ActiveRecord::RecordNotFound
        ActionView::MissingTemplate
        AbstractController::ActionNotFound
      ].freeze

      class << self
        # Enable both TracePoints. No-op on Ruby < 3.3 or if already enabled.
        def enable!
          unless RUBY_VERSION >= "3.3"
            RailsErrorDashboard::Logger.debug(
              "[RailsErrorDashboard] SwallowedExceptionTracker requires Ruby 3.3+ (current: #{RUBY_VERSION}). Skipping."
            )
            return false
          end

          return true if enabled?

          @raise_tracepoint = TracePoint.new(:raise) do |tp|
            on_raise(tp)
          rescue => e
            RailsErrorDashboard::Logger.debug(
              "[RailsErrorDashboard] SwallowedExceptionTracker :raise callback error: #{e.class} - #{e.message}"
            )
          end

          @rescue_tracepoint = TracePoint.new(:rescue) do |tp|
            on_rescue(tp)
          rescue => e
            RailsErrorDashboard::Logger.debug(
              "[RailsErrorDashboard] SwallowedExceptionTracker :rescue callback error: #{e.class} - #{e.message}"
            )
          end

          @raise_tracepoint.enable
          @rescue_tracepoint.enable

          at_exit { flush_all_threads! }

          true
        end

        # Disable both TracePoints and flush remaining data
        def disable!
          @raise_tracepoint&.disable
          @rescue_tracepoint&.disable
          @raise_tracepoint = nil
          @rescue_tracepoint = nil
        end

        # Check if currently enabled
        def enabled?
          @raise_tracepoint&.enabled? == true && @rescue_tracepoint&.enabled? == true
        end

        # Force flush the current thread's counters (used by job and tests)
        def flush!
          raises = Thread.current[RAISE_THREAD_KEY]
          rescues = Thread.current[RESCUE_THREAD_KEY]
          return if raises.nil? && rescues.nil?
          return if raises&.empty? && rescues&.empty?

          # Copy and clear atomically (per-thread, no lock needed)
          raise_snapshot = raises&.dup || {}
          rescue_snapshot = rescues&.dup || {}
          raises&.clear
          rescues&.clear
          Thread.current[FLUSH_THREAD_KEY] = Time.now.to_f

          dispatch_flush(raise_snapshot, rescue_snapshot)
        rescue => e
          RailsErrorDashboard::Logger.debug(
            "[RailsErrorDashboard] SwallowedExceptionTracker.flush! failed: #{e.class} - #{e.message}"
          )
        end

        # Read current thread's counters (for testing/inspection)
        def current_raises
          Thread.current[RAISE_THREAD_KEY] || {}
        end

        def current_rescues
          Thread.current[RESCUE_THREAD_KEY] || {}
        end

        # Clear current thread's counters without flushing (for testing)
        def clear!
          Thread.current[RAISE_THREAD_KEY] = nil
          Thread.current[RESCUE_THREAD_KEY] = nil
          Thread.current[FLUSH_THREAD_KEY] = nil
        end

        private

        # TracePoint(:raise) callback
        def on_raise(tp)
          exception = tp.raised_exception

          # 1. Skip system/flow-control exceptions (cheapest check first)
          return if skip_exception?(exception)

          # 2. Build location string
          path = tp.path.to_s
          line = tp.lineno
          location = "#{path}:#{line}"

          # 3. Set location ivar on exception for raise→rescue matching
          exception.instance_variable_set(RAISE_LOC_IVAR, location)

          # 4. Increment raise counter
          class_name = exception.class.name || exception.class.to_s
          key = "#{class_name}|#{location}"

          raises = (Thread.current[RAISE_THREAD_KEY] ||= {})
          raises[key] = (raises[key] || 0) + 1

          # 5. LRU eviction if over capacity
          evict_oldest!(raises) if raises.size > max_cache_size
        end

        # TracePoint(:rescue) callback
        def on_rescue(tp)
          exception = tp.raised_exception

          # 1. Skip system/flow-control exceptions
          return if skip_exception?(exception)

          # 2. Get raise location from ivar (set during :raise)
          raise_loc = if exception.instance_variable_defined?(RAISE_LOC_IVAR)
            exception.instance_variable_get(RAISE_LOC_IVAR)
          end
          return unless raise_loc

          # 3. Build rescue location
          rescue_path = tp.path.to_s
          rescue_line = tp.lineno
          rescue_loc = "#{rescue_path}:#{rescue_line}"

          # 4. Increment rescue counter
          class_name = exception.class.name || exception.class.to_s
          key = "#{class_name}|#{raise_loc}->#{rescue_loc}"

          rescues = (Thread.current[RESCUE_THREAD_KEY] ||= {})
          rescues[key] = (rescues[key] || 0) + 1

          # 5. LRU eviction if over capacity
          evict_oldest!(rescues) if rescues.size > max_cache_size

          # 6. Maybe flush
          maybe_flush!
        end

        # Check if exception should be skipped
        def skip_exception?(exception)
          return true if exception.is_a?(SystemExit)
          return true if exception.is_a?(SignalException)
          return true if exception.is_a?(Interrupt)

          class_name = exception.class.name
          return true if class_name.nil?

          # Check built-in flow-control list
          return true if FLOW_CONTROL_EXCEPTIONS.include?(class_name)

          # Check user-configured ignore list
          ignore_list = RailsErrorDashboard.configuration.swallowed_exception_ignore_classes
          return true if ignore_list&.any? { |klass| class_name == klass.to_s }

          false
        end

        # LRU eviction: delete the oldest key (Ruby hashes maintain insertion order)
        def evict_oldest!(hash)
          oldest_key = hash.each_key.first
          hash.delete(oldest_key) if oldest_key
        end

        # Cheap periodic flush check
        def maybe_flush!
          now = Time.now.to_f
          last_flush = Thread.current[FLUSH_THREAD_KEY] ||= now
          interval = RailsErrorDashboard.configuration.swallowed_exception_flush_interval

          return unless (now - last_flush) >= interval

          flush!
        end

        # Dispatch flush asynchronously via background job (zero I/O in request path).
        # Falls back to synchronous command if job enqueue fails.
        def dispatch_flush(raise_snapshot, rescue_snapshot, sync: false)
          return if raise_snapshot.empty? && rescue_snapshot.empty?

          if sync
            Commands::FlushSwallowedExceptions.call(
              raise_counts: raise_snapshot,
              rescue_counts: rescue_snapshot
            )
          else
            SwallowedExceptionFlushJob.perform_later(raise_snapshot, rescue_snapshot)
          end
        rescue => e
          RailsErrorDashboard::Logger.debug(
            "[RailsErrorDashboard] SwallowedExceptionTracker.dispatch_flush failed: #{e.class} - #{e.message}"
          )
        end

        def max_cache_size
          RailsErrorDashboard.configuration.swallowed_exception_max_cache_size || 1000
        end

        # Flush all threads on shutdown (best-effort)
        def flush_all_threads!
          Thread.list.each do |thread|
            raises = thread[RAISE_THREAD_KEY]
            rescues = thread[RESCUE_THREAD_KEY]
            next if raises.nil? && rescues.nil?
            next if raises&.empty? && rescues&.empty?

            raise_snapshot = raises&.dup || {}
            rescue_snapshot = rescues&.dup || {}
            thread[RAISE_THREAD_KEY] = nil
            thread[RESCUE_THREAD_KEY] = nil
            thread[FLUSH_THREAD_KEY] = nil

            dispatch_flush(raise_snapshot, rescue_snapshot, sync: true)
          end
        rescue => e
          RailsErrorDashboard::Logger.debug(
            "[RailsErrorDashboard] SwallowedExceptionTracker.flush_all_threads! failed: #{e.class} - #{e.message}"
          )
        end
      end
    end
  end
end
