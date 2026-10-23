# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: keep a capture's message and request params within the
    # size RED stores
    #
    # MySQL in strict mode (its default) rejects a TEXT value over 65,535 bytes,
    # and the capture path rescues the failure, so an error with a huge message
    # or a large POST body was silently lost there -- and stored unbounded on
    # every other adapter. Each capture route applies these where it first takes
    # the value, BEFORE the sensitive-data filter, so the filter's regexes and
    # JSON.parse only ever see bounded input on the request thread.
    #
    # The fingerprint hashes the raw message before any of this runs, so a
    # shortened message never changes grouping. Nothing here raises.
    class CaptureLimits
      # Characters of a message kept. The same as CrashCapture keeps; even at
      # 4 bytes a character it fits a TEXT column with room for the marker.
      MESSAGE_LIMIT = 10_000
      # Bytes of request params kept, under a TEXT column's 65,535.
      REQUEST_PARAMS_LIMIT = 64_000
      TRUNCATED_VALUE = "[TRUNCATED]"
      TEXT_MARKER = "… [truncated]"
      # Room for the `,"_truncated":true` the fitted object gains.
      FLAG_BYTES = 20
      # What .message appends, so an already-cut message (the async worker
      # receives one the request thread cut) is left alone, not cut again.
      MESSAGE_MARKER = /… \[\d+ more characters\]\z/
      MESSAGE_MARKER_MAX = 40

      # @param message [String, nil]
      # @return [String, nil] at most MESSAGE_LIMIT characters plus a marker
      #   saying how many were cut; anything that isn't a String as it came
      def self.message(message)
        return message unless message.is_a?(String) && message.length > MESSAGE_LIMIT
        return message if message.length <= MESSAGE_LIMIT + MESSAGE_MARKER_MAX && message.match?(MESSAGE_MARKER)

        "#{message[0, MESSAGE_LIMIT]}… [#{message.length - MESSAGE_LIMIT} more characters]"
      rescue StandardError
        cut_bytes(message, MESSAGE_LIMIT)
      end

      # A JSON object keeps its small values and stays parseable: the largest
      # values are replaced first, one at a time, until the whole fits. Any
      # other text (an array, or not JSON at all) is cut by bytes.
      #
      # @param params [String, nil] request params as a JSON string
      # @return [String, nil] at most REQUEST_PARAMS_LIMIT bytes; anything that
      #   isn't a String as it came
      def self.request_params(params)
        return params unless params.is_a?(String) && params.bytesize > REQUEST_PARAMS_LIMIT

        fit_json_object(params) || cut_bytes(params, REQUEST_PARAMS_LIMIT)
      rescue StandardError
        cut_bytes(params, REQUEST_PARAMS_LIMIT)
      end

      # @return [String, nil] the fitted JSON, or nil when the text is not a
      #   JSON object or dropping values could not make it fit
      def self.fit_json_object(json)
        parsed = JSON.parse(json)
        return nil unless parsed.is_a?(Hash)

        size = parsed.to_json.bytesize
        replacement = TRUNCATED_VALUE.to_json.bytesize
        budget = REQUEST_PARAMS_LIMIT - FLAG_BYTES
        parsed.map { |key, value| [ key, value.to_json.bytesize ] }
              .sort_by { |_key, bytes| -bytes }
              .each do |key, bytes|
                # Largest first, so once a value is no bigger than the
                # placeholder, replacing the rest would only grow the JSON.
                break if size <= budget || bytes <= replacement

                parsed[key] = TRUNCATED_VALUE
                size -= bytes - replacement
              end
        parsed["_truncated"] = true

        fitted = parsed.to_json
        fitted.bytesize <= REQUEST_PARAMS_LIMIT ? fitted : nil
      rescue JSON::ParserError
        nil
      end
      private_class_method :fit_json_object

      # The first bytes of text that fit in limit with the marker, cut on a
      # character boundary: a split character's bytes become "?" and are
      # dropped by the scrub, never left as an invalid sequence.
      #
      # @param text [String]
      # @param limit [Integer] bytes
      # @return [String]
      def self.cut_bytes(text, limit)
        kept = EncodingSanitizer.scrub(text.to_s.byteslice(0, limit - TEXT_MARKER.bytesize))
        "#{kept.chomp(EncodingSanitizer::REPLACEMENT)}#{TEXT_MARKER}"
      end
    end
  end
end
