# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Counts the HOST app's missing translations in a thread-local buffer and
    # writes them out at the end of the request or job that produced them.
    #
    # WHY A BUFFER: a missing key in a partial rendered inside a loop misses
    # once per iteration, on every request, for every user. Counting is a hash
    # increment; the database sees one upsert per (locale, key) per thread per
    # flush interval, however many times the key missed. Same shape as
    # RackAttackTracker, for the same reason.
    #
    # Misses are fed in by MissingTranslationHandler, which wraps
    # I18n.exception_handler. RED's own dashboard strings never arrive here:
    # I18nStore resolves them in a private backend that never reaches the
    # global handler.
    #
    # SAFETY RULES (HOST_APP_SAFETY.md):
    # - Zero I/O in the record path: a hash lookup, an increment, and (for a
    #   key seen for the first time on this thread) one caller_locations scan
    # - Never raises: every public method rescues
    # - Thread-local state, no mutex
    # - Bounded: at most MAX_BUFFERED_KEYS entries per thread; further new keys
    #   are counted in an overflow bucket rather than dropped silently
    # - The buffer drains only off the request path (executor to_complete,
    #   after the response body is closed) and at process exit
    class MissingTranslationTracker
      COUNTS_THREAD_KEY = :red_missing_translation_counts

      # Monotonic time at which the buffer became non-empty -- the deadline
      # clock, seeded when the first miss lands so a buffer that receives one
      # miss and then goes quiet is still written out (see RackAttackTracker).
      DEADLINE_THREAD_KEY = :red_missing_translation_deadline_at

      # Column limits from the migration. Truncation happens here so a value
      # never reaches the unique upsert index longer than the column allows.
      MAX_LOCALE_LENGTH = 35
      MAX_KEY_LENGTH    = 191
      MAX_SOURCE_LENGTH = 250

      # Distinct (locale, key) pairs one thread will hold before new keys go
      # to the overflow bucket. A real app has a few dozen missing keys, not
      # hundreds; the cap exists for the pathological case (a key built from
      # user input) so memory stays bounded.
      MAX_BUFFERED_KEYS = 500

      # Max age of buffered misses before the end-of-request drain writes
      # them. The upper bound on how stale the dashboard page can be, not a
      # per-request cost: a flood still collapses to one write per thread per
      # interval.
      FLUSH_INTERVAL = 5

      OVERFLOW_KEY    = "__overflow__"
      OVERFLOW_LOCALE = "*"

      # Composite buffer key separator (ASCII unit separator): cannot appear in
      # a locale and will not appear in a sane translation key.
      KEY_SEPARATOR = "\x1F"

      # Frames whose path matches none of these are the host's own code. The
      # first such frame is recorded as the miss's source.
      FOREIGN_FRAME = %r{/gems/|/ruby/\d|<internal:|/rails_error_dashboard/(lib|app)/}

      class << self
        # Record one miss. Called by MissingTranslationHandler on every
        # I18n::MissingTranslation that reaches the global handler.
        #
        # @param locale [String, Symbol]
        # @param key [String] the full dotted key as I18n normalised it
        # @param source [String, nil] call site; resolved from the stack when nil
        #   and the key is new to this thread's buffer
        def record(locale:, key:, source: nil)
          return unless enabled?

          buffer_key = build_key(truncate(locale, MAX_LOCALE_LENGTH), truncate(key, MAX_KEY_LENGTH))
          counts = (Thread.current[COUNTS_THREAD_KEY] ||= {})

          # Seed the deadline the moment the buffer goes from empty to
          # non-empty, so "never older than FLUSH_INTERVAL" holds for a buffer
          # that receives exactly one miss.
          Thread.current[DEADLINE_THREAD_KEY] ||= monotonic_now if counts.empty?

          entry = counts[buffer_key]
          if entry
            entry[0] += 1
          elsif counts.size >= MAX_BUFFERED_KEYS
            # Bounded memory: the count is kept, the key is not.
            overflow = (counts[overflow_key] ||= [ 0, nil ])
            overflow[0] += 1
          else
            # The stack is read once per new key per thread, not per miss.
            counts[buffer_key] = [ 1, truncate(source || host_call_site, MAX_SOURCE_LENGTH) ]
          end

          nil
        rescue => e
          RailsErrorDashboard::Logger.debug(
            "[RailsErrorDashboard] MissingTranslationTracker.record failed: #{e.class} - #{e.message}"
          )
          nil
        end

        # Write this thread's buffer out, synchronously. Clears the buffer
        # first so a failed write cannot double-count on the next flush.
        def flush!
          counts = Thread.current[COUNTS_THREAD_KEY]
          return if counts.nil? || counts.empty?

          snapshot = counts.dup
          counts.clear
          Thread.current[DEADLINE_THREAD_KEY] = nil

          Commands::FlushMissingTranslations.call(counts: snapshot)
          nil
        rescue => e
          RailsErrorDashboard::Logger.debug(
            "[RailsErrorDashboard] MissingTranslationTracker.flush! failed: #{e.class} - #{e.message}"
          )
          nil
        end

        # Drain this thread's buffer at the end of a request or job, if it has
        # been waiting at least FLUSH_INTERVAL. Registered on
        # Rails.application.executor.to_complete, which fires after the
        # response body is closed -- the client already has its bytes, so this
        # never delays a request. Interval-gated so a flood is one write per
        # thread per interval rather than one per request.
        def flush_if_due!
          return unless enabled?
          return unless flush_due?

          flush!
        rescue => e
          RailsErrorDashboard::Logger.debug(
            "[RailsErrorDashboard] MissingTranslationTracker.flush_if_due! failed: #{e.class} - #{e.message}"
          )
          nil
        end

        # Flush every live thread's buffer, not just the caller's. At process
        # exit the buffers sit on the Puma threads that served the requests,
        # and the exiting thread's own buffer is empty. Rescued per thread so
        # one failing write does not strand the rest.
        def flush_all_threads!
          Thread.list.each do |thread|
            begin
              counts = thread[COUNTS_THREAD_KEY]
              next if counts.nil? || counts.empty?

              snapshot = counts.dup
              counts.clear
              thread[DEADLINE_THREAD_KEY] = nil

              Commands::FlushMissingTranslations.call(counts: snapshot)
            rescue => e
              RailsErrorDashboard::Logger.debug(
                "[RailsErrorDashboard] MissingTranslationTracker.flush_all_threads! skipped a thread: #{e.class} - #{e.message}"
              )
            end
          end
          nil
        rescue => e
          RailsErrorDashboard::Logger.debug(
            "[RailsErrorDashboard] MissingTranslationTracker.flush_all_threads! failed: #{e.class} - #{e.message}"
          )
          nil
        end

        # Clear thread-local state without persisting (specs, thread teardown).
        def reset!
          Thread.current[COUNTS_THREAD_KEY] = nil
          Thread.current[DEADLINE_THREAD_KEY] = nil
          nil
        rescue => e
          nil
        end

        # Non-destructive copy of this thread's buffer: { buffer_key => [count, source] }.
        def buffered_counts
          (Thread.current[COUNTS_THREAD_KEY] || {}).transform_values(&:dup)
        rescue => e
          {}
        end

        # @return [Array<String>] [locale, translation_key]
        def parse_key(buffer_key)
          parts = buffer_key.to_s.split(KEY_SEPARATOR, 2)
          parts.fill("", parts.length, 2 - parts.length)
        end

        def overflow_key
          @overflow_key ||= build_key(OVERFLOW_LOCALE, OVERFLOW_KEY)
        end

        # True when the buffer has been waiting at least FLUSH_INTERVAL.
        # Monotonic clock: a wall-clock step backwards would defer the flush
        # indefinitely.
        def flush_due?
          deadline = Thread.current[DEADLINE_THREAD_KEY]
          return false if deadline.nil?

          (monotonic_now - deadline) >= FLUSH_INTERVAL
        rescue => e
          false
        end

        private

        def enabled?
          RailsErrorDashboard.configuration.enable_missing_translation_tracking
        rescue => e
          false
        end

        def build_key(*parts)
          parts.map(&:to_s).join(KEY_SEPARATOR)
        end

        def monotonic_now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        # The first stack frame that belongs to the host app, relative to
        # Rails.root when it is under it: "app/views/users/show.html.erb:12".
        # Compiled templates keep the template path and line, so a view miss
        # points at the ERB line, not at ActionView.
        def host_call_site
          root = defined?(Rails) && Rails.respond_to?(:root) && Rails.root ? "#{Rails.root}/" : nil

          # Start at 1 (this method's caller) and let FOREIGN_FRAME skip RED's
          # own frames, the i18n gem and ActionView; counting frames by hand
          # would break the first time the call chain changed length.
          caller_locations(1, 40)&.each do |frame|
            path = frame.path.to_s
            next if path.empty? || path.match?(FOREIGN_FRAME)

            path = path.delete_prefix(root) if root
            return "#{path}:#{frame.lineno}"
          end
          nil
        rescue => e
          nil
        end

        # Truncate to the column limit and strip the separator, so a key that
        # somehow contained it cannot shift the locale into the key column.
        def truncate(value, max)
          s = value.to_s
          s = s.delete(KEY_SEPARATOR) if s.include?(KEY_SEPARATOR)
          s.length > max ? s[0, max] : s
        end
      end
    end
  end
end
