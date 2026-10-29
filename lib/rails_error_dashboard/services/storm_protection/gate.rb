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

          # Drain the count buffer if the flush interval has elapsed.
          #
          # Wired to Rails.application.executor.to_complete, so it runs at the
          # end of every request and every job. Without it the buffer is only
          # ever drained by a LATER admit! on this process (see maybe_flush!),
          # and the tail of a burst sits in memory indefinitely: when the
          # errors stop, so does the only thing that would write them out.
          #
          # Interval-gated, so a flood does not turn into one enqueue per
          # request -- the cost per call is a monotonic clock read and a
          # comparison.
          def flush_if_due!
            return unless enabled?

            # Advance the breaker by the clock before flushing. When errors
            # stop, this (end of every request and job) is the only thing left
            # that can move it out of :open, and doing it first means an
            # episode that has just ended is persisted by this very flush.
            breaker.tick!
            maybe_flush!
            nil
          rescue => e
            RailsErrorDashboard::Logger.debug(
              "[RailsErrorDashboard] Gate.flush_if_due! failed: #{e.class} - #{e.message}"
            )
            nil
          end

          # Drain everything still buffered, NOW, whatever the interval says.
          #
          # Wired to at_exit. Everything counted since the last flush lives in
          # this process's memory, so without this every deploy (SIGTERM) drops
          # the tail of whatever was in flight.
          #
          # Writes SYNCHRONOUSLY rather than enqueueing: at process exit a job
          # handed to the queue may never be picked up, and on an in-process
          # adapter it certainly will not. This is the same choice
          # RackAttackTracker#flush_all_threads! makes for the same reason.
          #
          # at_exit, not Signal.trap -- trapping would clobber Puma's USR1/USR2
          # handlers (safety rule 9).
          def drain!
            return unless enabled?
            return unless count_buffer.any? || breaker.episode_snapshot

            snapshot = count_buffer.snapshot!
            episode = breaker.episode_snapshot

            Commands::FlushStormCounts.call(
              entries: snapshot[:entries],
              overflow: snapshot[:overflow],
              episode: serialize_episode(episode),
              batch_id: snapshot[:batch_id]
            )
            breaker.clear_closed_episode!
            nil
          rescue => e
            # A drain at shutdown must never raise into whatever is exiting.
            RailsErrorDashboard::Logger.error(
              "[RailsErrorDashboard] Gate.drain! failed: #{e.class} - #{e.message}"
            )
            nil
          end

          # Test hook + fork hygiene: fresh state, no leftover episodes.
          def reset!
            @breaker = nil
            @count_buffer = nil
            @fingerprint_buckets = nil
            @probe_counter = nil
            @probe_epoch = nil
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
          #
          # Only the gate key is built per event. The exemplar (the redacted,
          # scrubbed copy the count buffer keeps for a fingerprint) is built
          # only when the buffer stores a new entry: for every other event it
          # would be thrown away, and redacting and scrubbing it was most of
          # the storm check's cost.
          def decide(state, exception, context)
            case state
            when :open
              count!(exception, context, gate_identity(exception, context))
              :count_only
            when :half_open
              # Probe: a trickle of :lite captures tells us whether the storm
              # has actually subsided; everything else stays counted. The FIRST
              # event of each half-open period is the probe (then every tenth):
              # a recovering app with a slow trickle must not wait nine errors
              # before we look at one.
              if next_probe_index % 10 == 1
                :lite
              else
                count!(exception, context, gate_identity(exception, context))
                :count_only
              end
            when :shedding
              # Never :full while shedding — context capture is request-thread
              # CPU we can't afford. Buckets still apply their per-fingerprint
              # row sampling underneath.
              identity = gate_identity(exception, context)
              if fingerprint_buckets.decide(gate_key_for(identity)) == :count_only
                count!(exception, context, identity)
                :count_only
              else
                :lite
              end
            else # :closed
              identity = gate_identity(exception, context)
              decision = fingerprint_buckets.decide(gate_key_for(identity))
              count!(exception, context, identity) if decision == :count_only
              decision
            end
          end

          def count!(exception, context, identity)
            count_buffer.record(gate_key_for(identity)) { exemplar(identity, exception, context) }
          end

          # Who this error is, computed once per event in locals: what the
          # gate key needs, plus what the exemplar reuses if the buffer stores
          # a new entry. The identity digest is hashed from the RAW message,
          # and must match what the sync and async paths hash. The custom
          # fingerprint lambda is the user's code, so it runs once, here.
          def gate_identity(exception, context)
            raw_message = exception.message.to_s[0, ErrorHashGenerator::HASH_MESSAGE_LIMIT]
            frame = ErrorHashGenerator.extract_app_frame_from_locations(exception) ||
                    ErrorHashGenerator.extract_app_frame(exception.backtrace)
            {
              raw_message: raw_message,
              first_app_frame: frame,
              opaque_identity: ErrorHashGenerator.opaque_identity(
                error_class: exception.class.name,
                normalized_message: ErrorHashGenerator.normalize_message(raw_message),
                frames: frame,
                controller_name: context[:controller_name]&.to_s,
                action_name: context[:action_name]&.to_s
              ),
              custom_hash: custom_hash_for(exception, context),
              # Only an EXPLICIT environment from the caller. nil means "the
              # worker's own environment", resolved at flush time exactly as
              # LogError resolves it for a full capture.
              environment: context[:environment].to_s.strip.presence&.[](0, 64)
            }
          end

          # The exemplar for one error, identity included: what the count buffer
          # stores for it. The hot path never calls this; it is the whole thing
          # in one call, for callers that want the parts up front.
          def gate_parts(exception, context)
            exemplar(gate_identity(exception, context), exception, context)
          end

          # Cheap in-process bucketing key. Deliberately NOT the canonical
          # error_hash (that needs application_id = DB); the flush job
          # recomputes the canonical hash from the stored parts.
          # Environment is a MATCH dimension (one row per environment), so it
          # is part of the in-process key too: a staging event and a
          # production event of the same error must not share one entry, or
          # the flush job would reconcile both into whichever environment
          # the worker runs in. Scrubbed, as the exemplar's copy is.
          def gate_key_for(identity)
            identity[:gate_key] ||= Digest::SHA256.hexdigest(
              "#{identity[:custom_hash] || identity[:opaque_identity]}|#{EncodingSanitizer.scrub_deep(identity[:environment])}"
            )[0..15]
          end

          # What the count buffer keeps for a fingerprint it hasn't seen:
          # everything below is buffered, JSON-encoded for StormFlushJob and
          # later INSERTed, so no String may keep an invalid byte.
          #
          # The message is redacted before it goes in the buffer, because the
          # buffer is shipped to StormFlushJob -- a durable queue on Sidekiq or
          # Solid Queue. It survives as an exemplar for the minimal ErrorLog row
          # a first-seen fingerprint gets, which FlushStormCounts would redact
          # at INSERT anyway; doing it here means the secret never reaches the
          # queue's backing store at all.
          def exemplar(identity, exception, context)
            EncodingSanitizer.scrub_deep(
              error_class: exception.class.name,
              opaque_identity: identity[:opaque_identity],
              # Scrubbed before redaction: the filter's regexes raise on invalid bytes.
              message: redact(EncodingSanitizer.scrub(identity[:raw_message])),
              first_app_frame: identity[:first_app_frame],
              controller_name: context[:controller_name]&.to_s,
              action_name: context[:action_name]&.to_s,
              custom_hash: identity[:custom_hash],
              environment: identity[:environment],
              # Whose backtrace first_app_frame came from, for the row the flush
              # may build from it. Not part of the identity or the gate key: a
              # client report and a server capture of one error share an entry,
              # which keeps the first event's frame, and so its source.
              capture_source: context[:_capture_source] == "client" ? "client" : "server"
            )
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

          # Memoized ActiveSupport::ParameterFilter, no I/O -- safe on the hot
          # path. Fails closed: if filtering breaks, the exemplar is
          # [FILTERED], never the raw message, so the raw text can't reach the
          # flush job's queued arguments.
          def redact(message)
            return message if message.blank?
            return message unless RailsErrorDashboard.configuration.filter_sensitive_data

            SensitiveDataFilter.filter_attributes({ message: message })[:message] || message
          rescue StandardError
            SensitiveDataFilter::FILTERED_REPLACEMENT
          end

          def probe_counter
            @probe_counter ||= Concurrent::AtomicFixnum.new(0)
          end

          # 1-based index of this event within the current half-open period.
          # The reset is deliberately lock-free: two threads racing on a fresh
          # epoch can at worst both start from a new counter, which admits one
          # extra :lite probe. Nothing is lost and nothing can raise.
          def next_probe_index
            epoch = breaker.half_open_epoch
            if @probe_epoch != epoch
              @probe_epoch = epoch
              @probe_counter = Concurrent::AtomicFixnum.new(0)
            end
            probe_counter.increment
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

            begin
              job = StormFlushJob.perform_later(
                entries: snapshot[:entries],
                overflow: snapshot[:overflow],
                episode: serialize_episode(episode),
                batch_id: snapshot[:batch_id]
              )
              # Active Job swallows ActiveJob::EnqueueError and returns false
              # (and a job that was not enqueued says so) — a failed handoff
              # that never raises.
              unless ApplicationJob.enqueued?(job)
                raise "StormFlushJob was not enqueued: #{ApplicationJob.enqueue_failure_reason(job)}"
              end
            rescue => e
              # The queue is often the very thing that is down during a storm
              # (a SolidQueue enqueue is a DB write). The batch is not gone:
              # put it back so the next interval retries, and leave the
              # closed episode in place so it is persisted by that retry.
              count_buffer.restore(snapshot[:entries], snapshot[:overflow])
              RailsErrorDashboard::Logger.error(
                "[RailsErrorDashboard] Storm flush enqueue failed (batch retained for retry): #{e.class} - #{e.message}"
              )
              return
            end

            breaker.clear_closed_episode!
          rescue => e
            RailsErrorDashboard::Logger.error(
              "[RailsErrorDashboard] Storm flush failed: #{e.class} - #{e.message}"
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
            # A storm on staging should not page whoever is on call for production.
            return unless RailsErrorDashboard::Services::NotificationThrottler.environment_allowed?

            episode = breaker.episode_snapshot
            return unless episode
            return if @storm_notified_episode == episode[:started_at]

            @storm_notified_episode = episode[:started_at]
            StormNotificationJob.perform_later(
              started_at: episode[:started_at].iso8601,
              state: state.to_s,
              locale: ApplicationJob.enqueue_locale
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
