# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    module StormProtection
      # Layer 1: per-fingerprint rate limiting with graceful degradation.
      #
      # Each fingerprint gets a 60-second window. Within the window:
      #   - first N events            → :full  (everything captured)
      #   - past N, every Mth event   → :lite  (row captured, context shed)
      #   - everything else           → :count_only (in-memory count, flushed later)
      #
      # The first event of every window is ALWAYS at least :lite, so a
      # melting-down fingerprint still has a fresh exemplar each minute —
      # deterministic, unlike rand-based sampling.
      #
      # Calm-mode adaptive context sampling rides the same entries: after K
      # full-context captures per fingerprint per day, context is captured
      # only every Mth time (an error firing 1000×/day doesn't need 1000
      # breadcrumb trails). Occurrence rows are unaffected in calm mode.
      #
      # Concurrency: entries are mutable structs in a Concurrent::Map with
      # plain (unlocked) field increments — races can miscount by a handful
      # of events, which is acceptable for rate limiting. No mutex anywhere.
      #
      # Memory: the map is bounded. Once full, unseen fingerprints are NOT
      # tracked and decide as :full — in calm weather that's harmless; in a
      # storm of unique fingerprints the global breaker (Layer 2) takes over.
      class FingerprintBuckets
        WINDOW_SECONDS = 60
        DAY_SECONDS = 86_400

        Entry = Struct.new(:window_start, :window_count, :day_start, :day_full_context_count)

        def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
          @clock = clock
          reset!
        end

        def reset!
          @entries = Concurrent::Map.new
        end

        # Decide capture fidelity for one event of this fingerprint.
        # @return [Symbol] :full, :lite, or :count_only
        def decide(gate_key)
          now = @clock.call
          entry = fetch_entry(gate_key, now)
          return :full unless entry # map full — Layer 2 owns the storm case

          roll_windows(entry, now)
          entry.window_count += 1
          n = entry.window_count

          if n <= full_per_minute
            decide_calm_context(entry)
          elsif n == full_per_minute + 1 || ((n - full_per_minute) % keep_every).zero?
            :lite
          else
            :count_only
          end
        end

        private

        def fetch_entry(gate_key, now)
          existing = @entries[gate_key]
          return existing if existing

          # Bounded: never insert past the cap (size check is approximate
          # under concurrency — a few entries over the cap is fine)
          return nil if @entries.size >= max_tracked

          @entries.compute_if_absent(gate_key) { Entry.new(now, 0, now, 0) }
        end

        def roll_windows(entry, now)
          if now - entry.window_start >= WINDOW_SECONDS
            entry.window_start = now
            entry.window_count = 0
          end
          if now - entry.day_start >= DAY_SECONDS
            entry.day_start = now
            entry.day_full_context_count = 0
          end
        end

        # Under the per-minute cap: full context unless this fingerprint has
        # already produced plenty of full-context captures today.
        def decide_calm_context(entry)
          entry.day_full_context_count += 1
          k = entry.day_full_context_count

          if k <= context_threshold_per_day || (k % context_keep_every).zero?
            :full
          else
            :lite
          end
        end

        def full_per_minute
          RailsErrorDashboard.configuration.storm_fingerprint_full_per_minute.to_i
        end

        def keep_every
          [ RailsErrorDashboard.configuration.storm_occurrence_sample_keep_every.to_i, 1 ].max
        end

        def context_threshold_per_day
          RailsErrorDashboard.configuration.context_sampling_threshold_per_day.to_i
        end

        def context_keep_every
          [ RailsErrorDashboard.configuration.context_sampling_keep_every.to_i, 1 ].max
        end

        def max_tracked
          RailsErrorDashboard.configuration.storm_max_tracked_fingerprints.to_i
        end
      end
    end
  end
end
