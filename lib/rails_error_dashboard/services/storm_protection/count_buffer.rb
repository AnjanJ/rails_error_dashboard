# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    module StormProtection
      # In-memory accumulator for events that are counted but not stored
      # per-event (Layer 1 overflow and the breaker's count-only mode).
      #
      # Stores exact counts plus just enough identity to reconcile onto the
      # right ErrorLog at flush time: the flush command recomputes the
      # canonical error_hash from these parts (with application resolved in
      # the background job, where DB access is allowed) and issues a single
      # `occurrence_count = occurrence_count + N` UPDATE per fingerprint.
      # Fingerprints first seen during count-only mode get a minimal ErrorLog
      # created from the stored exemplar. Counting is exact — no extrapolation.
      #
      # Memory: bounded map; beyond the cap events land in a single overflow
      # counter (still exact in total, anonymous in identity).
      #
      # Concurrency: a read/write lock. Every record holds the READ lock for
      # the few instructions between reading the map reference and bumping
      # the entry's counter; snapshot! takes the WRITE lock only to swap the
      # map out. So once the swap returns no writer can still be holding the
      # old map, and the old map is quiescent while it is serialized outside
      # the lock. AtomicReference alone was not enough: a writer that read the
      # old reference just before the swap would increment a map nobody would
      # ever read again, and the "exact" count lost an event.
      class CountBuffer
        # How finely shed events are timestamped.
        #
        # 15 minutes, not an hour: every UTC offset in use divides into 15
        # minutes -- including +05:30 (Kolkata) and +05:45 (Kathmandu) -- so a
        # local midnight always falls on a bucket EDGE and a day's total is
        # exact. An hourly bucket straddles those boundaries and could only
        # ever report them approximately.
        BUCKET_SECONDS = 900

        Entry = Struct.new(
          :error_class, :message, :first_app_frame,
          :controller_name, :action_name, :custom_hash, :environment,
          :opaque_identity, :count, :first_seen_at, :last_seen_at, :buckets
        )

        # The bucket an instant belongs to, as an epoch second.
        def self.bucket_for(time)
          (time.to_i / BUCKET_SECONDS) * BUCKET_SECONDS
        end

        def initialize
          reset!
        end

        def reset!
          @lock = Concurrent::ReadWriteLock.new
          @map_ref = Concurrent::AtomicReference.new(Concurrent::Map.new)
          @overflow = Concurrent::AtomicFixnum.new(0)
        end

        # Record one counted-not-stored event.
        # @param gate_key [String] cheap in-process bucketing key
        # @param parts [Hash] identity parts captured at the gate
        def record(gate_key, parts)
          now = Time.current
          @lock.with_read_lock do
            add(gate_key, parts, 1, now, now, { self.class.bucket_for(now) => 1 })
          end
        end

        # Put a snapshot BACK when its handoff failed (the flush job could not
        # be enqueued). Counts merge into whatever accumulated since the swap;
        # first_seen_at keeps the earliest of the two; beyond the map cap the
        # events land in the overflow bucket — exact in total, as always.
        # @param entries [Array<Hash>] entries from #snapshot!
        # @param overflow [Integer] overflow from #snapshot!
        def restore(entries, overflow = 0)
          @lock.with_read_lock do
            Array(entries).each do |entry|
              entry = entry.with_indifferent_access if entry.respond_to?(:with_indifferent_access)
              next unless entry.is_a?(Hash)

              add(
                entry["gate_key"],
                parts_from(entry),
                entry["count"].to_i,
                parse_time(entry["first_seen_at"]),
                parse_time(entry["last_seen_at"]),
                buckets_from(entry)
              )
            end
            @overflow.increment(overflow.to_i) if overflow.to_i.positive?
          end
        end

        def any?
          @overflow.value.positive? || !@map_ref.get.empty?
        end

        # Atomically swap the buffer out and return serializable entry hashes.
        # @return [Hash] { entries: Array<Hash>, overflow: Integer }
        def snapshot!
          old_map, overflow = @lock.with_write_lock do
            taken = @overflow.value
            @overflow.update { |v| v - taken }
            [ @map_ref.get_and_set(Concurrent::Map.new), taken ]
          end

          entries = []
          old_map.each_pair do |key, entry|
            entries << {
              "gate_key" => key,
              "error_class" => entry.error_class,
              "message" => entry.message,
              "first_app_frame" => entry.first_app_frame,
              "controller_name" => entry.controller_name,
              "action_name" => entry.action_name,
              "custom_hash" => entry.custom_hash,
              "environment" => entry.environment,
              # The fingerprint, hashed from the RAW message at the gate.
              # "message" above is REDACTED before it is buffered, so the flush
              # job CANNOT recompute this -- it has to travel, or a storm count
              # lands on a different row than the full capture path would.
              "opaque_identity" => entry.opaque_identity,
              "count" => entry.count.value,
              "first_seen_at" => entry.first_seen_at.iso8601,
              "last_seen_at" => entry.last_seen_at.iso8601,
              # { epoch_second => count }. This is the timing evidence: the
              # flush job reconciles each bucket separately, because a total
              # plus last_seen_at cannot say how many events fell on either
              # side of a day boundary.
              "buckets" => entry.buckets.each_pair.to_h { |at, n| [ at.to_s, n.value ] }
            }
          end

          # A unique identity for THIS swap of the buffer.
          #
          # The batch digest is built from the entries and their counts, which
          # makes a replay recognisable -- but it also makes two SEPARATE
          # batches indistinguishable when they happen to carry identical
          # counts for the same fingerprints (timestamps are second-granular,
          # so a storm flushing twice inside one second collides). The second
          # batch would then be dropped as a replay, losing real counts.
          #
          # Minted here because this is the moment a batch comes into
          # existence: every entry in it was removed from the buffer by this
          # swap and appears in no other batch. A retry of the same batch
          # carries the same id, which is exactly what the ledger must catch.
          { entries: entries, overflow: overflow, batch_id: SecureRandom.uuid }
        end

        private

        # Callers hold the read lock.
        def add(gate_key, parts, count, first_seen_at, last_seen_at, buckets = nil)
          return if count <= 0

          map = @map_ref.get
          entry = map[gate_key]

          unless entry
            if map.size >= max_tracked
              @overflow.increment(count)
              return
            end
            entry = map.compute_if_absent(gate_key) do
              Entry.new(
                parts[:error_class], parts[:message], parts[:first_app_frame],
                parts[:controller_name], parts[:action_name], parts[:custom_hash], parts[:environment],
                parts[:opaque_identity],
                Concurrent::AtomicFixnum.new(0), first_seen_at || Time.current, last_seen_at || Time.current,
                Concurrent::Map.new
              )
            end
          end

          entry.count.increment(count)
          entry.last_seen_at = [ entry.last_seen_at, last_seen_at ].compact.max
          entry.first_seen_at = [ entry.first_seen_at, first_seen_at ].compact.min

          # Per-bucket tallies use the same AtomicFixnum-inside-a-Concurrent::Map
          # shape as the total above, so they are safe under the READ lock and
          # the write lock's scope is not widened (it still covers only the
          # snapshot swap).
          add_buckets(entry, count, last_seen_at, buckets)
        end

        # Distribute `count` across buckets. A live record supplies exactly one
        # bucket; a restore supplies the map it was snapshotted with. The
        # fallback keeps a caller that supplies none from losing the timing
        # entirely -- it lands on last_seen_at's bucket, which is what the old
        # behaviour did for every event.
        def add_buckets(entry, count, last_seen_at, buckets)
          pairs =
            if buckets.is_a?(Hash) && buckets.any?
              buckets
            else
              { self.class.bucket_for(last_seen_at || Time.current) => count }
            end

          pairs.each do |at, n|
            n = n.to_i
            next unless n.positive?

            entry.buckets.compute_if_absent(at.to_i) { Concurrent::AtomicFixnum.new(0) }.increment(n)
          end
        end

        def buckets_from(entry)
          raw = entry["buckets"]
          return nil unless raw.is_a?(Hash)

          raw.to_h { |at, n| [ at.to_i, n.to_i ] }
        end

        def parts_from(entry)
          {
            error_class: entry["error_class"], message: entry["message"],
            first_app_frame: entry["first_app_frame"], controller_name: entry["controller_name"],
            action_name: entry["action_name"], custom_hash: entry["custom_hash"],
            environment: entry["environment"], opaque_identity: entry["opaque_identity"]
          }
        end

        def parse_time(value)
          return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
          return nil if value.blank?

          Time.zone.parse(value.to_s)
        rescue ArgumentError
          nil
        end

        def max_tracked
          RailsErrorDashboard.configuration.storm_max_tracked_fingerprints.to_i
        end
      end
    end
  end
end
