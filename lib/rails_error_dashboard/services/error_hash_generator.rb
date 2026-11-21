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

      # Frames under Ruby's own library directory are never the app's (REQ-2).
      RUBY_LIB_DIR = "#{RbConfig::CONFIG["rubylibdir"]}/".freeze

      # A string backtrace line: "path:line:in 'label'" (Ruby 3.4+) or
      # "path:line:in `label'" (Ruby 3.3). The label part may be missing.
      BACKTRACE_LINE = /\A(.+?):(\d+)(?::in [`'](.*)')?\z/

      # The prefixes Location#label adds and #base_label drops.
      LABEL_PREFIX = /\A(?:(?:block(?: \(\d+ levels\))?|rescue|ensure) in )+/

      # Both identities of one exception, before the application is added.
      #
      # v2 is the recipe from 1.0.0-rc.2 on (stable for all of 1.x): the error
      # class, the normalised message, the first app frame as
      # "<path relative to Rails.root>#<method>", NameError#name, and the
      # controller and action. v1 is rc.1's recipe, kept so a group created
      # before the upgrade is still found (removed in 2.0). A custom
      # fingerprint replaces both, exactly as in rc.1.
      #
      # @param exception [Exception]
      # @param context [Hash] the capture context, passed to custom_fingerprint
      # @param controller_name [String, nil] defaults to context[:controller_name]
      # @param action_name [String, nil] defaults to context[:action_name]
      # @return [Hash] { v2:, v1:, custom: }: v2 and v1 are opaque (complete
      #   them with .complete); custom is already the complete hash, and when
      #   it is present v2 and v1 are nil
      def self.identities(exception, context = {}, controller_name: context[:controller_name], action_name: context[:action_name])
        custom = try_custom_fingerprint(exception, context)
        return { v2: nil, v1: nil, custom: custom } if custom

        normalized = normalize_message(exception.message)
        controller_name = controller_name&.to_s
        action_name = action_name&.to_s

        {
          v2: v2_identity(exception, normalized_message: normalized, controller_name: controller_name, action_name: action_name),
          v1: opaque_identity(
            error_class: exception.class.name,
            normalized_message: normalized,
            frames: extract_app_frame_from_locations(exception) || extract_app_frame(exception.backtrace),
            controller_name: controller_name,
            action_name: action_name
          ),
          custom: nil
        }
      end

      # The v2 identity alone, opaque. The storm gate computes it per event
      # and v1 only for a new buffer entry. It does not consult
      # custom_fingerprint: the caller does that first.
      #
      # @param normalized_message [String, nil] normalize_message's result, if
      #   the caller already has it
      def self.v2_identity(exception, normalized_message: nil, controller_name: nil, action_name: nil)
        Digest::SHA256.hexdigest([
          exception.class.name,
          normalized_message || normalize_message(exception.message),
          app_frame_v2(exception),
          name_part(exception),
          controller_name&.to_s,
          action_name&.to_s
        ].compact.join("|"))[0..15]
      end

      # The first app frame as "<path relative to Rails.root>#<method>"
      # (REQ-1, REQ-3), or nil when there is none. Skips gem frames,
      # "<internal:" frames, frames under Ruby's library directory, and a frame
      # whose next kept frame has the same path and line: a C method reported
      # at its caller's line (REQ-2). If every kept frame matches the next, the
      # last one is used.
      def self.app_frame_v2(exception)
        locations = safe_locations(exception)
        if locations
          index = first_app_location_index(locations)
          return nil unless index

          path = locations[index].absolute_path || locations[index].path
          label = locations[index].base_label
        else
          # A backtrace set from strings: parsed to the same [path, line,
          # base_label], so it follows the same rules. Rare, so parsed whole.
          frames = Array(exception.backtrace).map { |line| parse_backtrace_line(line) }
          index = first_app_index(frames.size) { |i| frames[i] }
          return nil unless index

          path, _line, label = frames[index]
        end

        relative = relative_to_root(path)
        label ? "#{relative}##{label}" : relative
      end

      # The storm gate's per-event key (design.md, the gate amendment of
      # 2026-11-21): v2's parts, with the first kept frame's absolute
      # "path:line" in place of v2's frame. It skips what REQ-2 skips but
      # doesn't walk same-line frames, so it costs what rc.1's identity did.
      # It is at least as fine as v2: two events whose first kept frame
      # matches end that walk on the same method. Not a digest; the gate
      # hashes it into its key.
      def self.gate_source(exception, normalized_message:, controller_name: nil, action_name: nil)
        [
          exception.class.name,
          normalized_message,
          first_kept_frame(exception),
          name_part(exception),
          controller_name,
          action_name
        ].map(&:to_s).join("|")
      end

      def self.first_kept_frame(exception)
        locations = safe_locations(exception)
        if locations
          locations.each do |location|
            path = location.absolute_path || location.path
            return "#{path}:#{location.lineno}" unless foreign_frame?(path)
          end
          return nil
        end

        Array(exception.backtrace).each do |line|
          path, lineno, = parse_backtrace_line(line)
          return "#{path}:#{lineno}" unless foreign_frame?(path)
        end
        nil
      end

      def self.parse_backtrace_line(line)
        match = BACKTRACE_LINE.match(EncodingSanitizer.scrub(line.to_s))
        match ? [ match[1], match[2].to_i, base_label_of(match[3]) ] : [ nil, nil, nil ]
      end

      def self.safe_locations(exception)
        locations = exception.backtrace_locations
        locations.nil? || locations.empty? ? nil : locations
      rescue StandardError
        nil
      end

      # first_app_index for backtrace_locations, written out: no block and
      # no array per frame, since the gate runs it per event. Consecutive
      # frames usually share a file, so a path is classified only when it
      # differs from the last one classified.
      def self.first_app_location_index(locations)
        previous = nil
        previous_path = previous_line = nil
        checked_path = false # never equal to a path, nil included
        foreign = false
        index = 0
        size = locations.size
        while index < size
          location = locations[index]
          path = location.absolute_path || location.path
          unless path == checked_path
            foreign = foreign_frame?(path)
            checked_path = path
          end
          unless foreign
            line = location.lineno
            return previous if previous && (path != previous_path || line != previous_line)

            previous = index
            previous_path = path
            previous_line = line
          end
          index += 1
        end
        previous
      end

      # The index of the first app frame among `size` frames, the block giving
      # each one's [path, line]. A plain loop, and the label is read only for
      # the frame chosen: the storm gate runs this per event, and a deep stack
      # of one-line recursion walks every frame (REQ-2's same-line rule).
      def self.first_app_index(size)
        previous = nil
        previous_path = previous_line = nil
        index = 0
        while index < size
          path, line = yield(index)
          unless foreign_frame?(path)
            return previous if previous && (path != previous_path || line != previous_line)

            previous = index
            previous_path = path
            previous_line = line
          end
          index += 1
        end
        previous
      end

      def self.foreign_frame?(path)
        path.nil? || path.include?("/gems/") || path.start_with?("<internal:") || path.start_with?(RUBY_LIB_DIR)
      end

      # What Location#base_label gives for a label: no "block in", "rescue in"
      # or "ensure in" prefix, and no "Class#" or "Class." owner (Ruby 3.4+).
      def self.base_label_of(label)
        return nil if label.nil? || label.empty?

        base = label.sub(LABEL_PREFIX, "")
        return base if base.start_with?("<")

        base.split(/[#.]/).last || base
      end

      # A path under Rails.root, or under its real path (a symlinked "current"
      # and the "releases/<timestamp>" it points to), loses that prefix. Any
      # other path stays as it is.
      def self.relative_to_root(path)
        prefix = root_prefixes.find { |candidate| path.start_with?(candidate) }
        prefix ? path[prefix.length..] : path
      end

      # Rails.root and its real path, longest first, each ending in "/". The
      # real path is a filesystem call, so it is cached per Rails.root value.
      def self.root_prefixes
        root = defined?(Rails) && Rails.respond_to?(:root) && Rails.root ? Rails.root.to_s : nil
        return [] if root.nil? || root.empty?

        cached = @root_prefixes
        return cached[1] if cached && cached[0] == root

        real = begin
          File.realpath(root)
        rescue StandardError
          root
        end
        prefixes = [ root, real ].uniq.map { |dir| dir.end_with?("/") ? dir : "#{dir}/" }.sort_by { -_1.length }
        @root_prefixes = [ root, prefixes.freeze ].freeze
        prefixes
      end

      # "name:<NameError#name>" with digits replaced, as in the message (REQ-4).
      def self.name_part(exception)
        return nil unless exception.is_a?(NameError)

        name = exception.name
        return nil if name.nil?

        "name:#{EncodingSanitizer.scrub(name.to_s).gsub(/\d+/, "N")}"
      rescue StandardError
        nil
      end
      private_class_method :app_frame_v2, :parse_backtrace_line, :safe_locations, :first_app_index, :first_kept_frame,
                           :first_app_location_index, :foreign_frame?,
                           :base_label_of, :relative_to_root, :root_prefixes, :name_part

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
