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
        Entry = Struct.new(
          :error_class, :message, :first_app_frame,
          :controller_name, :action_name, :custom_hash,
          :count, :first_seen_at, :last_seen_at
        )

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
          @lock.with_read_lock { add(gate_key, parts, 1, Time.current, Time.current) }
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
                parse_time(entry["last_seen_at"])
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
              "count" => entry.count.value,
              "first_seen_at" => entry.first_seen_at.iso8601,
              "last_seen_at" => entry.last_seen_at.iso8601
            }
          end

          { entries: entries, overflow: overflow }
        end

        private

        # Callers hold the read lock.
        def add(gate_key, parts, count, first_seen_at, last_seen_at)
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
                parts[:controller_name], parts[:action_name], parts[:custom_hash],
                Concurrent::AtomicFixnum.new(0), first_seen_at || Time.current, last_seen_at || Time.current
              )
            end
          end

          entry.count.increment(count)
          entry.last_seen_at = [ entry.last_seen_at, last_seen_at ].compact.max
          entry.first_seen_at = [ entry.first_seen_at, first_seen_at ].compact.min
        end

        def parts_from(entry)
          {
            error_class: entry["error_class"], message: entry["message"],
            first_app_frame: entry["first_app_frame"], controller_name: entry["controller_name"],
            action_name: entry["action_name"], custom_hash: entry["custom_hash"]
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
