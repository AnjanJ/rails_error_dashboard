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
      # Concurrency: snapshot! atomically swaps the whole map out via
      # AtomicReference, so flushing never races with recording.
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
          @map_ref = Concurrent::AtomicReference.new(Concurrent::Map.new)
          @overflow = Concurrent::AtomicFixnum.new(0)
        end

        # Record one counted-not-stored event.
        # @param gate_key [String] cheap in-process bucketing key
        # @param parts [Hash] identity parts captured at the gate
        def record(gate_key, parts)
          map = @map_ref.get
          entry = map[gate_key]

          unless entry
            if map.size >= max_tracked
              @overflow.increment
              return
            end
            entry = map.compute_if_absent(gate_key) do
              Entry.new(
                parts[:error_class], parts[:message], parts[:first_app_frame],
                parts[:controller_name], parts[:action_name], parts[:custom_hash],
                Concurrent::AtomicFixnum.new(0), Time.current, Time.current
              )
            end
          end

          entry.count.increment
          entry.last_seen_at = Time.current
        end

        def any?
          @overflow.value.positive? || !@map_ref.get.empty?
        end

        # Atomically swap the buffer out and return serializable entry hashes.
        # @return [Hash] { entries: Array<Hash>, overflow: Integer }
        def snapshot!
          old_map = @map_ref.get_and_set(Concurrent::Map.new)
          overflow = @overflow.value
          @overflow.update { |v| v - overflow }

          entries = []
          old_map.each_pair do |_key, entry|
            entries << {
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

        def max_tracked
          RailsErrorDashboard.configuration.storm_max_tracked_fingerprints.to_i
        end
      end
    end
  end
end
