# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    module StormProtection
      # Facade for the storm-protection hot path. One call per capture attempt:
      #
      #   Gate.admit!(exception, context) # => :full | :lite | :count_only
      #
      #   :full       — capture everything (the normal path)
      #   :lite       — capture the error + occurrence row, shed context
      #                 (breadcrumbs / system health / locals / ivars)
      #   :count_only — nothing stored now; counted in memory, reconciled
      #                 onto ErrorLog.occurrence_count by the flush job
      #
      # Safety contract (mirrors SwallowedExceptionTracker):
      # - FAILS OPEN: any internal error → :full. Protection must never be
      #   the thing that loses an error.
      # - Zero I/O on the hot path. The only DB-adjacent work is enqueueing
      #   the flush job at most once per flush interval.
      # - Budget: digest + atomic increment + comparisons (~µs). Benchmarked.
      # - Per-process state; Puma workers each run their own breaker. No
      #   thread-locals — shared atomics, so no Thread.current cleanup needed.
      #
      # IMPORTANT ordering: callers must run ExceptionFilter (ignore list +
      # static sampling) BEFORE this gate — ignored exceptions must never
      # count toward storm state or be reconciled into ErrorLogs.
      class Gate
        class << self
          def admit!(exception, context = {})
            return :full unless enabled?

            state = breaker.record!
            maybe_storm_notification(state)

            decision = decide(state, exception, context)
            maybe_flush!
            decision
          rescue => e
            RailsErrorDashboard::Logger.error(
              "[RailsErrorDashboard] StormProtection failed open: #{e.class} - #{e.message}"
            )
            :full
          end

          # While the breaker is not closed, per-error notifications are
          # suppressed (a single storm notification replaces them).
          def notifications_suppressed?
            enabled? && breaker.state != :closed
          rescue
            false
          end

          # Always-on cap for auto-created issues (a storm of NEW critical
          # fingerprints must not open 500 GitHub/Linear issues). Token
          # bucket: N per rolling window, per process. Each call consumes a
          # token — call only when actually about to create an issue.
          def issue_creation_allowed?
            return true unless enabled?

            now = monotonic_now
            window = RailsErrorDashboard.configuration.auto_issue_rate_limit_window_minutes.to_i * 60
            limit = RailsErrorDashboard.configuration.auto_issue_rate_limit_count.to_i

            @issue_window_start ||= now
            @issue_window_count ||= Concurrent::AtomicFixnum.new(0)

            if now - @issue_window_start >= window
              @issue_window_start = now
              @issue_window_count = Concurrent::AtomicFixnum.new(0)
            end

            @issue_window_count.increment <= limit
          rescue
            true
          end

          def state
            enabled? ? breaker.state : :closed
          rescue
            :closed
          end

          # Exposed for the flush job (episode metadata for storm_events).
          def breaker
            @breaker ||= CircuitBreaker.new
          end

          def count_buffer
            @count_buffer ||= CountBuffer.new
          end

          def fingerprint_buckets
            @fingerprint_buckets ||= FingerprintBuckets.new
          end

          # Test hook + fork hygiene: fresh state, no leftover episodes.
          def reset!
            @breaker = nil
            @count_buffer = nil
            @fingerprint_buckets = nil
            @probe_counter = nil
            @issue_window_start = nil
            @issue_window_count = nil
            @last_flush = nil
            @storm_notified_episode = nil
          end

          private

          def enabled?
            RailsErrorDashboard.configuration.enable_storm_protection
          end

          # All identity computation happens here, once, in locals — no
          # shared mutable caches (thread safety by construction).
          def decide(state, exception, context)
            case state
            when :open
              count!(exception, context)
              :count_only
            when :half_open
              # Probe: a trickle of :lite captures tells us whether the storm
              # has actually subsided; everything else stays counted.
              if (probe_counter.increment % 10).zero?
                :lite
              else
                count!(exception, context)
                :count_only
              end
            when :shedding
              # Never :full while shedding — context capture is request-thread
              # CPU we can't afford. Buckets still apply their per-fingerprint
              # row sampling underneath.
              parts = gate_parts(exception, context)
              if fingerprint_buckets.decide(gate_key(parts)) == :count_only
                count_buffer.record(gate_key(parts), parts)
                :count_only
              else
                :lite
              end
            else # :closed
              parts = gate_parts(exception, context)
              decision = fingerprint_buckets.decide(gate_key(parts))
              count_buffer.record(gate_key(parts), parts) if decision == :count_only
              decision
            end
          end

          def count!(exception, context)
            parts = gate_parts(exception, context)
            count_buffer.record(gate_key(parts), parts)
          end

          # Cheap in-process bucketing key. Deliberately NOT the canonical
          # error_hash (that needs application_id = DB); the flush job
          # recomputes the canonical hash from the stored parts.
          def gate_key(parts)
            parts[:gate_key] ||= parts[:custom_hash] || Digest::SHA256.hexdigest(
              "#{parts[:error_class]}|#{ErrorHashGenerator.normalize_message(parts[:message])}|" \
              "#{parts[:first_app_frame]}|#{parts[:controller_name]}|#{parts[:action_name]}"
            )[0..15]
          end

          def gate_parts(exception, context)
            {
              error_class: exception.class.name,
              message: exception.message.to_s[0, 500],
              first_app_frame: ErrorHashGenerator.extract_app_frame_from_locations(exception) ||
                               ErrorHashGenerator.extract_app_frame(exception.backtrace),
              controller_name: context[:controller_name]&.to_s,
              action_name: context[:action_name]&.to_s,
              custom_hash: custom_hash_for(exception, context)
            }
          end

          # When a custom fingerprint lambda is configured the canonical hash
          # doesn't include application_id, so the gate can compute it exactly
          # — the flush job then reconciles by hash directly.
          def custom_hash_for(exception, context)
            return nil unless RailsErrorDashboard.configuration.custom_fingerprint

            result = RailsErrorDashboard.configuration.custom_fingerprint.call(exception, context)
            return nil unless result.is_a?(String) && !result.empty?

            Digest::SHA256.hexdigest(result)[0..15]
          rescue
            nil
          end

          def probe_counter
            @probe_counter ||= Concurrent::AtomicFixnum.new(0)
          end

          # Piggyback flush (SwallowedExceptionTracker pattern): cheap
          # timestamp check per admit; enqueue at most once per interval.
          def maybe_flush!
            now = monotonic_now
            interval = RailsErrorDashboard.configuration.storm_flush_interval_seconds.to_i
            return if now - (@last_flush ||= now) < interval
            return unless count_buffer.any? || breaker.episode_snapshot

            @last_flush = now
            snapshot = count_buffer.snapshot!
            episode = breaker.episode_snapshot
            breaker.clear_closed_episode!

            StormFlushJob.perform_later(
              entries: snapshot[:entries],
              overflow: snapshot[:overflow],
              episode: serialize_episode(episode)
            )
          rescue => e
            RailsErrorDashboard::Logger.error(
              "[RailsErrorDashboard] Storm flush enqueue failed: #{e.class} - #{e.message}"
            )
          end

          def serialize_episode(episode)
            return nil unless episode

            {
              "started_at" => episode[:started_at]&.iso8601,
              "ended_at" => episode[:ended_at]&.iso8601,
              "peak_rate_per_minute" => episode[:peak_rate_per_minute],
              "reached_open" => episode[:reached_open]
            }
          end

          # One notification per storm episode, on the first transition out
          # of :closed.
          def maybe_storm_notification(state)
            return if state == :closed
            return unless RailsErrorDashboard.configuration.storm_notification

            episode = breaker.episode_snapshot
            return unless episode
            return if @storm_notified_episode == episode[:started_at]

            @storm_notified_episode = episode[:started_at]
            StormNotificationJob.perform_later(
              started_at: episode[:started_at].iso8601,
              state: state.to_s
            )
          rescue => e
            RailsErrorDashboard::Logger.error(
              "[RailsErrorDashboard] Storm notification enqueue failed: #{e.class} - #{e.message}"
            )
          end

          def monotonic_now
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end
        end
      end
    end
  end
end
