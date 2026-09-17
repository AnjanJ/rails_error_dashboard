# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Generate consistent hash for error deduplication
    #
    # No database access — accepts exception data, returns a hash string.
    # Same hash = same error type for grouping purposes.
    #
    # Two entry points:
    # - `.call(exception, ...)` — used by LogError command (exception-based)
    # - `.from_attributes(...)` — used by ErrorLog model callback (attribute-based)
    #
    # @example
    #   ErrorHashGenerator.call(exception, controller_name: "users", action_name: "show", application_id: 1)
    #   # => "a1b2c3d4e5f6g7h8"
    class ErrorHashGenerator
      # Generate hash from an exception object (used by LogError command)
      # @param exception [Exception] The exception to hash
      # @param controller_name [String, nil] Controller context
      # @param action_name [String, nil] Action context
      # @param application_id [Integer, nil] Application for per-app deduplication
      # @param context [Hash] Full error context (passed to custom fingerprint lambda)
      # @return [String] 16-character hex hash
      def self.call(exception, controller_name: nil, action_name: nil, application_id: nil, context: {})
        # Check for custom fingerprint lambda
        custom = try_custom_fingerprint(exception, context)
        return custom if custom

        complete(
          opaque_identity(
            error_class: exception.class.name,
            normalized_message: normalize_message(exception.message),
            frames: extract_app_frame_from_locations(exception) || extract_app_frame(exception.backtrace),
            controller_name: controller_name,
            action_name: action_name
          ),
          application_id
        )
      end

      # The half of the fingerprint that needs no database.
      #
      # WHY THE HASH IS TWO-STAGE: capture identity has to be computed from the
      # RAW message (redacting first would re-group every error whose message
      # contains a filtered key), but the async and storm paths compute it on
      # the request thread and hand it to a worker over a queue. Shipping the
      # raw message to do that put secrets in the queue's backing store, its
      # backups and any job-argument logging -- the error row was redacted, the
      # payload was not.
      #
      # Hashing the identity parts here makes the value that crosses the queue
      # opaque and irreversible, so no message text needs to travel for
      # grouping to work. The worker calls .complete with application_id, which
      # it can resolve because it is allowed to touch the database.
      #
      # application_id is NOT part of this digest: resolving it means
      # Application.find_or_create_by_name, a write, and the capture path
      # promises no I/O on the request thread.
      #
      # @return [String] 16-character hex digest of the non-application parts
      def self.opaque_identity(error_class:, normalized_message:, frames:, controller_name: nil, action_name: nil)
        digest_input = [
          error_class,
          normalized_message,
          frames,
          controller_name,
          action_name
        ].compact.join("|")

        Digest::SHA256.hexdigest(digest_input)[0..15]
      end

      # Combine an opaque identity with the application to get the canonical
      # error_hash. Every path -- sync capture, async worker, storm flush --
      # finishes here, so a fingerprint is the same value however it travelled.
      #
      # @param opaque [String] from .opaque_identity (or a custom fingerprint)
      # @param application_id [Integer, nil]
      # @return [String] 16-character hex hash
      def self.complete(opaque, application_id)
        Digest::SHA256.hexdigest("#{opaque}|#{application_id}")[0..15]
      end

      # Generate hash from error attributes (used by ErrorLog model callback)
      # Uses ErrorNormalizer for smarter normalization and significant frame extraction
      # @param error_type [String] The error class name
      # @param message [String, nil] The error message
      # @param backtrace [String, nil] The backtrace as a string
      # @param controller_name [String, nil] Controller context
      # @param action_name [String, nil] Action context
      # @param application_id [Integer, nil] Application for per-app deduplication
      # @return [String] 16-character hex hash
      def self.from_attributes(error_type:, message: nil, backtrace: nil, controller_name: nil, action_name: nil, application_id: nil)
        # Deliberately a DIFFERENT recipe from .call: ErrorNormalizer's smarter
        # normalization and three significant frames, rather than a prefix of
        # the message and one app frame. The two entry points have always
        # produced different hashes for the same error; unifying them would
        # re-group every existing row. They share only the two-stage shape.
        complete(
          opaque_identity(
            error_class: error_type,
            normalized_message: ErrorNormalizer.normalize(message),
            frames: ErrorNormalizer.extract_significant_frames(backtrace, count: 3),
            controller_name: controller_name,
            action_name: action_name
          ),
          application_id
        )
      end

      # Only this many leading characters of the RAW message take part in the
      # hash. The storm gate stores a bounded exemplar (it must stay cheap and
      # memory-bounded per fingerprint), so the full path has to hash the same
      # prefix or a long-message error would change identity the moment the
      # breaker changed state. Truncation happens BEFORE normalization so both
      # paths see byte-identical input.
      HASH_MESSAGE_LIMIT = 500

      # Normalize dynamic values in error messages for consistent hashing
      # @param message [String, nil] The error message
      # @return [String, nil] Normalized message
      def self.normalize_message(message)
        # Slice, THEN scrub, then match: every path (sync, async, storm gate)
        # goes through here, so they all hash the same text. gsub raises on a
        # string with invalid bytes; a valid message is returned by scrub as-is,
        # so no existing fingerprint changes.
        prefix = message&.[](0, HASH_MESSAGE_LIMIT)

        EncodingSanitizer.scrub(prefix)
          &.gsub(/0x[0-9a-f]+/i, "HEX")          # Replace hex addresses (before numbers)
          &.gsub(/#<[^>]+>/, "#<OBJ>")           # Replace object inspections
          &.gsub(/\d+/, "N")                     # Replace numbers
          &.gsub(/"[^"]*"/, '""')                # Replace double-quoted strings
          &.gsub(/'[^']*'/, "''")                # Replace single-quoted strings
      end

      # Extract first meaningful app code frame using backtrace_locations
      # More reliable than string parsing — uses Location#absolute_path directly.
      # @param exception [Exception] The exception with backtrace_locations
      # @return [String, nil] File path of first app code frame, or nil
      def self.extract_app_frame_from_locations(exception)
        locations = exception.backtrace_locations
        return nil if locations.nil? || locations.empty?

        first_app_location = locations.find { |loc|
          path = loc.absolute_path || loc.path
          !path&.include?("/gems/")
        }

        first_app_location && (first_app_location.absolute_path || first_app_location.path)
      rescue => e
        RailsErrorDashboard::Logger.debug(
          "[RailsErrorDashboard] extract_app_frame_from_locations failed: #{e.message}"
        )
        nil
      end

      # Extract first meaningful app code frame from backtrace
      # @param backtrace [Array<String>, nil] Exception backtrace
      # @return [String, nil] File path of first app code frame
      def self.extract_app_frame(backtrace)
        return nil if backtrace.nil?

        first_app_frame = backtrace.find { |frame|
          !frame.include?("/gems/")
        }

        # split raises on a frame with invalid bytes (a method name can hold any).
        EncodingSanitizer.scrub(first_app_frame)&.split(":")&.first
      end

      # Try custom fingerprint lambda if configured
      # Returns 16-char hex hash from custom key, or nil to fall back to default
      # @param exception [Exception] The exception
      # @param context [Hash] Error context
      # @return [String, nil] 16-character hex hash or nil
      def self.try_custom_fingerprint(exception, context)
        fingerprint_fn = RailsErrorDashboard.configuration.custom_fingerprint
        return nil unless fingerprint_fn

        result = fingerprint_fn.call(exception, context)
        return nil unless result.is_a?(String) && !result.empty?

        Digest::SHA256.hexdigest(result)[0..15]
      rescue => e
        RailsErrorDashboard::Logger.error(
          "[RailsErrorDashboard] Custom fingerprint lambda failed: #{e.class} - #{e.message}. " \
          "Falling back to default hash."
        )
        nil
      end
      private_class_method :try_custom_fingerprint
    end
  end
end
