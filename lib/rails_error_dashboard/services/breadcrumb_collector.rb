# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure service: Collect breadcrumbs (request activity trail) for error context
    #
    # Uses a thread-local ring buffer to capture events during a request lifecycle.
    # Thread.current isolation means no mutex/lock is needed.
    #
    # SAFETY RULES (HOST_APP_SAFETY.md):
    # - Every public method wrapped in rescue => e; nil
    # - Never raise, never block, never allocate large objects
    # - Messages truncated to 500 chars, metadata values to 200 chars
    # - Ring buffer has fixed max size (no unbounded growth)
    class BreadcrumbCollector
      THREAD_KEY = :red_breadcrumbs
      MAX_MESSAGE_LENGTH = 500
      MAX_METADATA_VALUE_LENGTH = 200
      MAX_METADATA_KEYS = 10

      # Fixed-size ring buffer — O(1) append, wraps around when full
      class RingBuffer
        def initialize(max_size)
          @max_size = max_size
          @buffer = Array.new(max_size)
          @write_pos = 0
          @count = 0
        end

        def add(entry)
          @buffer[@write_pos] = entry
          @write_pos = (@write_pos + 1) % @max_size
          @count += 1 if @count < @max_size
        end

        def to_a
          return [] if @count == 0

          if @count < @max_size
            @buffer[0...@count]
          else
            # Buffer has wrapped — read from write_pos to end, then start to write_pos
            @buffer[@write_pos...@max_size] + @buffer[0...@write_pos]
          end
        end

        def clear
          @buffer = Array.new(@max_size)
          @write_pos = 0
          @count = 0
        end
      end

      # Initialize a new ring buffer for the current thread (start of request)
      def self.init_buffer
        size = RailsErrorDashboard.configuration.breadcrumb_buffer_size || 40
        Thread.current[THREAD_KEY] = RingBuffer.new(size)
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] BreadcrumbCollector.init_buffer failed: #{e.message}")
        nil
      end

      # Clear the ring buffer (end of request — MUST be called in ensure block)
      def self.clear_buffer
        Thread.current[THREAD_KEY] = nil
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] BreadcrumbCollector.clear_buffer failed: #{e.message}")
        nil
      end

      # Add a breadcrumb to the current buffer
      # @param category [String] Event category (sql, controller, cache, job, mailer, custom)
      # @param message [String] Human-readable description
      # @param duration_ms [Float, nil] Duration in milliseconds
      # @param metadata [Hash, nil] Optional key-value pairs
      def self.add(category, message, duration_ms: nil, metadata: nil)
        buffer = Thread.current[THREAD_KEY]
        return unless buffer

        # Check category filter
        allowed = RailsErrorDashboard.configuration.breadcrumb_categories
        if allowed
          cat_sym = category.to_s.to_sym
          return unless allowed.include?(cat_sym)
        end

        # Build breadcrumb entry with compact keys
        entry = {
          t: (Time.now.to_f * 1000).to_i,
          c: category.to_s,
          m: truncate_message(message)
        }

        entry[:d] = duration_ms if duration_ms
        entry[:meta] = truncate_metadata(metadata) if metadata.is_a?(Hash)

        buffer.add(entry)
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] BreadcrumbCollector.add failed: #{e.message}")
        nil
      end

      # Harvest breadcrumbs from the current buffer and clear it
      # @return [Array<Hash>] Array of breadcrumb hashes (empty if none)
      def self.harvest
        buffer = Thread.current[THREAD_KEY]
        return [] unless buffer

        result = buffer.to_a
        buffer.clear
        result
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] BreadcrumbCollector.harvest failed: #{e.message}")
        []
      end

      # Non-destructive read of current breadcrumbs (does NOT clear the buffer)
      # Used by DiagnosticDumpGenerator for on-demand snapshots.
      # @return [Array<Hash>] Array of breadcrumb hashes (empty if none)
      def self.current_breadcrumbs
        buffer = Thread.current[THREAD_KEY]
        return [] unless buffer
        buffer.to_a
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] BreadcrumbCollector.current_breadcrumbs failed: #{e.message}")
        []
      end

      # Get the current buffer (for inspection)
      # @return [RingBuffer, nil]
      def self.current_buffer
        Thread.current[THREAD_KEY]
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] BreadcrumbCollector.current_buffer failed: #{e.message}")
        nil
      end

      # Filter sensitive data from breadcrumbs before storage
      # Reuses existing SensitiveDataFilter — no new filter logic
      # @param breadcrumbs [Array<Hash>] Raw breadcrumbs
      # @return [Array<Hash>] Filtered breadcrumbs
      def self.filter_sensitive(breadcrumbs)
        return [] unless breadcrumbs.is_a?(Array)
        return breadcrumbs unless RailsErrorDashboard.configuration.filter_sensitive_data

        filter = SensitiveDataFilter.parameter_filter
        return breadcrumbs unless filter

        breadcrumbs.map do |crumb|
          filtered = crumb.dup

          # Filter message (SQL queries, key=value patterns)
          if filtered[:m]
            filtered[:m] = SensitiveDataFilter.send(:filter_message, filter, filtered[:m])
          end

          # Filter metadata values
          if filtered[:meta].is_a?(Hash)
            filtered[:meta] = filter.filter(filtered[:meta])
          end

          filtered
        end
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] BreadcrumbCollector.filter_sensitive failed: #{e.message}")
        breadcrumbs.is_a?(Array) ? breadcrumbs : []
      end

      # Truncate message to MAX_MESSAGE_LENGTH
      def self.truncate_message(message)
        str = message.to_s
        str.length > MAX_MESSAGE_LENGTH ? str[0, MAX_MESSAGE_LENGTH] : str
      rescue => e
        ""
      end
      private_class_method :truncate_message

      # Truncate metadata: limit keys and value lengths
      def self.truncate_metadata(metadata)
        return {} unless metadata.is_a?(Hash)

        result = {}
        metadata.first(MAX_METADATA_KEYS).each do |key, value|
          str_value = value.to_s
          result[key] = str_value.length > MAX_METADATA_VALUE_LENGTH ? str_value[0, MAX_METADATA_VALUE_LENGTH] : str_value
        end
        result
      rescue => e
        {}
      end
      private_class_method :truncate_metadata
    end
  end
end
