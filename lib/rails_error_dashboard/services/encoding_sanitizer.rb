# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: make every String in a value safe to store, serialize and render
    #
    # Exception messages, backtrace lines, request URLs, user agents and params can
    # carry bytes that are not valid UTF-8 (a binary upload echoed in a message, a
    # Latin-1 query string, a NUL from a fuzzer). Left alone they raise at the
    # worst possible moments: ActiveJob JSON-encoding the async payload in the
    # host's request thread, the PostgreSQL INSERT, or `blank?` while rendering the
    # error's own page.
    #
    # Invalid sequences become "?" and NUL bytes are removed (PostgreSQL text
    # columns reject them). Strings tagged ASCII-8BIT (or any other encoding) are
    # re-tagged UTF-8 and then scrubbed — not transcoded, because a binary tag
    # says nothing about what the bytes mean and transcoding would raise.
    #
    # The common case costs one `valid_encoding?` scan and returns the SAME
    # object. Nothing here raises, and the caller's objects are never mutated.
    #
    # @example
    #   EncodingSanitizer.scrub("caf\xC3 \xFF".b)          # => "caf? ?"
    #   EncodingSanitizer.scrub_deep({ url: "/?q=\xFF" })   # => { url: "/?q=?" }
    class EncodingSanitizer
      REPLACEMENT = "?"
      UNREADABLE = "[unreadable]"
      TOO_DEEP = "[truncated: nested too deep]"
      MAX_DEPTH = 10
      NUL = "\0"

      # @param str [Object] anything; only Strings are touched
      # @return [Object] the same object when already clean, otherwise a clean copy
      def self.scrub(str)
        return str unless String === str

        s = str.encoding == Encoding::UTF_8 ? str : str.dup.force_encoding(Encoding::UTF_8)
        return s if s.valid_encoding? && !s.include?(NUL)

        s = s.scrub(REPLACEMENT) unless s.valid_encoding?
        s.delete(NUL)
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] EncodingSanitizer.scrub failed: #{e.class}")
        UNREADABLE
      end

      # Recursively scrub Strings inside Hashes (keys and values) and Arrays.
      # Anything else is returned untouched. A container nested deeper than
      # MAX_DEPTH is replaced by a placeholder rather than passed through: an
      # unscrubbed subtree would defeat the point, and a self-referencing one
      # would never end.
      #
      # @param obj [Object]
      # @return [Object]
      def self.scrub_deep(obj, depth = 0)
        case obj
        when String
          scrub(obj)
        when Hash
          return TOO_DEEP if depth >= MAX_DEPTH

          # Build into an empty copy of the same class so a
          # HashWithIndifferentAccess stays one.
          obj.each_with_object(obj.class.new) do |(key, value), result|
            result[scrub_deep(key, depth + 1)] = scrub_deep(value, depth + 1)
          end
        when Array
          return TOO_DEEP if depth >= MAX_DEPTH

          obj.map { |value| scrub_deep(value, depth + 1) }
        else
          obj
        end
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] EncodingSanitizer.scrub_deep failed: #{e.class}")
        String === obj ? UNREADABLE : obj
      end
    end
  end
end
