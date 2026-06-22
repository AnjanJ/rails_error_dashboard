# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    module StormProtection
      # Per-process circuit breaker for the error capture path.
      #
      # Counts capture attempts in fixed 10-second buckets and transitions
      # between states based on the completed bucket's rate:
      #
      #   :closed    — normal operation, per-fingerprint buckets decide fidelity
      #   :shedding  — elevated rate: context shed, notifications suppressed
      #   :open      — storm: count-only mode, zero per-event I/O
      #   :half_open — post-cooldown probe: small sample admitted, watching rate
      #
      # Hysteresis: opens FAST (a single hot bucket, or mid-bucket fast-trip),
      # closes SLOW (two consecutive calm buckets) to prevent flapping.
      #
      # Concurrency: the hot path is one AtomicFixnum increment plus a float
      # comparison. The mutex is taken only on bucket roll (once per 10s) and
      # for state transitions — never per event.
      class CircuitBreaker
        BUCKET_SECONDS = 10
        CALM_BUCKETS_TO_CLOSE = 2

        attr_reader :state

        # @param clock [#call] returns monotonic seconds; injectable for tests
        def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
          @clock = clock
          @mutex = Mutex.new
          reset!
        end

        def reset!
          @mutex.synchronize do
            @state = :closed
            @bucket_start = @clock.call
            @bucket_count = Concurrent::AtomicFixnum.new(0)
            @calm_buckets = 0
            @opened_at = nil
            @episode = nil
          end
        end

        # Count one capture attempt and return the state that should govern it.
        # Called on EVERY capture — must stay allocation-free on the fast path.
        def record!
          now = @clock.call
          roll!(now) if now - @bucket_start >= BUCKET_SECONDS

          count = @bucket_count.increment

          # Fast-trip: don't wait for the bucket to complete if it's already
          # over the open threshold — at 50k errors/min a full 10s bucket
          # would let ~8k events through before reacting.
          if count >= open_threshold * BUCKET_SECONDS && @state != :open
            trip_open!(now, count)
          end

          @state
        end

        # Episode metadata for the honesty layer (storm_events row).
        # @return [Hash, nil] nil when no episode is active or recently closed
        def episode_snapshot
          @mutex.synchronize { @episode&.dup }
        end

        # Forget a closed episode once it has been persisted by the flush job.
        def clear_closed_episode!
          @mutex.synchronize do
            @episode = nil if @episode && @episode[:ended_at]
          end
        end

        private

        def roll!(now)
          @mutex.synchronize do
            elapsed = now - @bucket_start
            return if elapsed < BUCKET_SECONDS # another thread already rolled

            rate = @bucket_count.value / elapsed.to_f
            @bucket_start = now
            @bucket_count = Concurrent::AtomicFixnum.new(0)
            transition!(rate, now)
          end
        end

        # Transition table — runs inside @mutex, once per bucket roll.
        # track_peak runs AFTER the case: a transition out of :closed creates
        # the episode, and the triggering bucket's rate must be its first peak.
        def transition!(rate, now)
          case @state
          when :closed
            if rate >= open_threshold
              open!(now)
            elsif rate >= shedding_threshold
              enter!(:shedding, now)
            end
          when :shedding
            if rate >= open_threshold
              open!(now)
            elsif rate < shedding_threshold / 2.0
              calm_step!(now)
            else
              @calm_buckets = 0
            end
          when :open
            if now - @opened_at >= cooldown_seconds && rate < shedding_threshold
              @state = :half_open
              @calm_buckets = 0
            end
          when :half_open
            if rate >= shedding_threshold
              open!(now)
            else
              calm_step!(now)
            end
          end

          track_peak(rate)
        end

        def calm_step!(now)
          @calm_buckets += 1
          close!(now) if @calm_buckets >= CALM_BUCKETS_TO_CLOSE
        end

        def enter!(new_state, _now)
          begin_episode! if @state == :closed
          @state = new_state
          @calm_buckets = 0
        end

        def open!(now)
          begin_episode! if @state == :closed
          @state = :open
          @opened_at = now
          @calm_buckets = 0
          @episode[:reached_open] = true if @episode
        end

        # Mid-bucket fast trip — takes the mutex (rare: at most once per storm onset).
        def trip_open!(now, count)
          @mutex.synchronize do
            return if @state == :open

            begin_episode! if @state == :closed
            track_peak(count / [ now - @bucket_start, 1.0 ].max)
            @state = :open
            @opened_at = now
            @calm_buckets = 0
            @episode[:reached_open] = true if @episode
          end
        end

        def close!(_now)
          @state = :closed
          @calm_buckets = 0
          @episode[:ended_at] = Time.current if @episode
        end

        def begin_episode!
          @episode = {
            started_at: Time.current,
            ended_at: nil,
            peak_rate_per_minute: 0,
            reached_open: false
          }
        end

        def track_peak(rate_per_second)
          return unless @episode

          per_minute = (rate_per_second * 60).round
          @episode[:peak_rate_per_minute] = per_minute if per_minute > @episode[:peak_rate_per_minute]
        end

        def shedding_threshold
          RailsErrorDashboard.configuration.storm_shedding_threshold_per_second.to_f
        end

        def open_threshold
          RailsErrorDashboard.configuration.storm_open_threshold_per_second.to_f
        end

        def cooldown_seconds
          RailsErrorDashboard.configuration.storm_cooldown_seconds.to_i
        end
      end
    end
  end
end
