# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Buffers Rack::Attack events in a thread-local hash and flushes them to the
    # database asynchronously.
    #
    # WHY THIS EXISTS (issue #143): Rack::Attack events were previously only
    # recorded as breadcrumbs. Breadcrumbs are harvested exclusively by LogError,
    # so an event was only ever persisted if an unrelated exception happened to be
    # raised later in the same request. A throttled request returns HTTP 429 and
    # raises nothing, so the event was always discarded when ErrorCatcher cleared
    # the buffer. This tracker persists events independently of error capture.
    #
    # Events are aggregated by (rule, match_type, discriminator, path, method) and
    # counted, rather than stored one row per event — a rate-limit flood is exactly
    # when we must not do one INSERT per request.
    #
    # SAFETY RULES (HOST_APP_SAFETY.md):
    # - Zero I/O in the record path (hash lookup + integer increment)
    # - Never raises — every public method wrapped in rescue
    # - Thread-local state, no mutex needed
    # - LRU eviction bounds memory (rotating-IP attacks cannot grow it unbounded)
    # - Async flush via background job
    class RackAttackTracker
      COUNTS_THREAD_KEY = :red_rack_attack_counts
      FLUSH_THREAD_KEY  = :red_rack_attack_last_flush

      # Field length caps — must match the column limits in the migration so that
      # truncation happens before the value ever reaches the unique upsert index.
      MAX_RULE_LENGTH          = 250
      MAX_DISCRIMINATOR_LENGTH = 191
      MAX_PATH_LENGTH          = 191
      MAX_METHOD_LENGTH        = 10

      # Separator for the composite buffer key. Chosen because it cannot appear in
      # an HTTP method and is vanishingly unlikely in a rule name or path.
      KEY_SEPARATOR = ""

      class << self
        # Record a single Rack::Attack event. Called from the AS::Notifications
        # subscriber on every throttle/blocklist/track match.
        #
        # @param rule [String] matched rule name (env["rack.attack.matched"])
        # @param match_type [String] "throttle" | "blocklist" | "track"
        # @param discriminator [String] rate-limit key (usually IP or user id)
        # @param path [String] request path
        # @param http_method [String] request method
        def record(rule:, match_type:, discriminator: nil, path: nil, http_method: nil)
          return unless enabled?

          key = build_key(
            truncate(rule, MAX_RULE_LENGTH),
            match_type.to_s,
            truncate(discriminator, MAX_DISCRIMINATOR_LENGTH),
            truncate(path, MAX_PATH_LENGTH),
            truncate(http_method, MAX_METHOD_LENGTH)
          )

          counts = (Thread.current[COUNTS_THREAD_KEY] ||= {})
          counts[key] = (counts[key] || 0) + 1

          # LRU eviction — Ruby hashes preserve insertion order, so the first key
          # is the oldest. Bounds memory under rotating-discriminator attacks.
          evict_oldest!(counts) if counts.size > max_cache_size

          maybe_flush!
          nil
        rescue => e
          RailsErrorDashboard::Logger.debug(
            "[RailsErrorDashboard] RackAttackTracker.record failed: #{e.class} - #{e.message}"
          )
          nil
        end

        # Flush buffered counts to the database (async by default).
        # Clears the thread-local buffer before dispatching so a slow/failed
        # flush cannot double-count on the next call.
        def flush!(sync: false)
          counts = Thread.current[COUNTS_THREAD_KEY]
          return if counts.nil? || counts.empty?

          snapshot = counts.dup
          counts.clear
          Thread.current[FLUSH_THREAD_KEY] = Time.now.to_f

          dispatch_flush(snapshot, sync: sync)
          nil
        rescue => e
          RailsErrorDashboard::Logger.debug(
            "[RailsErrorDashboard] RackAttackTracker.flush! failed: #{e.class} - #{e.message}"
          )
          nil
        end

        # Clear thread-local state without persisting. Used by specs and by
        # thread teardown paths.
        def reset!
          Thread.current[COUNTS_THREAD_KEY] = nil
          Thread.current[FLUSH_THREAD_KEY] = nil
          nil
        rescue => e
          nil
        end

        # Current buffered counts (inspection / specs). Non-destructive.
        def buffered_counts
          (Thread.current[COUNTS_THREAD_KEY] || {}).dup
        rescue => e
          {}
        end

        # Decompose a buffer key back into its parts.
        # @return [Array<String>] [rule, match_type, discriminator, path, http_method]
        def parse_key(key)
          key.to_s.split(KEY_SEPARATOR, 5)
        end

        private

        def enabled?
          RailsErrorDashboard.configuration.enable_rack_attack_tracking
        rescue => e
          false
        end

        def build_key(*parts)
          parts.map(&:to_s).join(KEY_SEPARATOR)
        end

        def evict_oldest!(hash)
          oldest_key = hash.each_key.first
          hash.delete(oldest_key) if oldest_key
        end

        # Cheap periodic flush check — a float subtraction, no I/O.
        def maybe_flush!
          now = Time.now.to_f
          last_flush = Thread.current[FLUSH_THREAD_KEY] ||= now
          return unless (now - last_flush) >= flush_interval

          flush!
        end

        # Dispatch asynchronously so the request path never waits on the DB.
        # Falls back to a synchronous write if enqueueing fails (e.g. no queue
        # backend configured) — losing the events would be worse, and this only
        # happens on the flush interval, not per event.
        def dispatch_flush(snapshot, sync: false)
          return if snapshot.empty?

          if sync
            Commands::FlushRackAttackEvents.call(counts: snapshot)
          else
            RackAttackFlushJob.perform_later(snapshot)
          end
        rescue => e
          RailsErrorDashboard::Logger.debug(
            "[RailsErrorDashboard] RackAttackTracker.dispatch_flush enqueue failed, " \
            "falling back to sync: #{e.class} - #{e.message}"
          )
          begin
            Commands::FlushRackAttackEvents.call(counts: snapshot)
          rescue => inner
            RailsErrorDashboard::Logger.debug(
              "[RailsErrorDashboard] RackAttackTracker sync fallback failed: #{inner.class} - #{inner.message}"
            )
          end
        end

        def max_cache_size
          RailsErrorDashboard.configuration.rack_attack_max_cache_size || 1000
        rescue => e
          1000
        end

        def flush_interval
          RailsErrorDashboard.configuration.rack_attack_flush_interval || 60
        rescue => e
          60
        end

        # Truncate to the column limit and strip the key separator. A rule name
        # or path containing KEY_SEPARATOR would otherwise shift every field on
        # parse — silently writing the discriminator into the path column.
        def truncate(str, max)
          s = str.to_s
          s = s.delete(KEY_SEPARATOR) if s.include?(KEY_SEPARATOR)
          s.length > max ? s[0, max] : s
        end
      end
    end
  end
end
