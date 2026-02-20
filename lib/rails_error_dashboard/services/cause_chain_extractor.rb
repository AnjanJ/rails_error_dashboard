# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Extract the exception cause chain from an exception.
    #
    # Ruby exceptions can have a `cause` (set automatically by `raise` inside a `rescue`).
    # This service walks the chain recursively with a depth limit to prevent
    # infinite loops from circular cause references.
    #
    # Returns a JSON string of cause entries, or nil if no cause exists.
    #
    # @example
    #   CauseChainExtractor.call(exception)
    #   # => '[{"class_name":"OriginalError","message":"connection refused","backtrace":["app/models/user.rb:10"]}]'
    class CauseChainExtractor
      MAX_DEPTH = 5
      MAX_MESSAGE_LENGTH = 1000
      MAX_BACKTRACE_LINES = 20

      # @param exception [Exception] The exception to extract cause chain from
      # @return [String, nil] JSON string of cause chain, or nil if no cause
      def self.call(exception)
        return nil unless exception.respond_to?(:cause) && exception.cause

        chain = []
        current = exception.cause
        seen = Set.new
        depth = 0

        while current && depth < MAX_DEPTH
          # Guard against circular cause references
          break if seen.include?(current.object_id)
          seen.add(current.object_id)

          chain << {
            class_name: current.class.name,
            message: current.message&.to_s&.slice(0, MAX_MESSAGE_LENGTH),
            backtrace: truncate_backtrace(current.backtrace)
          }

          current = current.respond_to?(:cause) ? current.cause : nil
          depth += 1
        end

        chain.empty? ? nil : chain.to_json
      rescue => e
        # SAFETY: Never let cause chain extraction break error logging
        RailsErrorDashboard::Logger.debug(
          "[RailsErrorDashboard] CauseChainExtractor failed: #{e.class} - #{e.message}"
        )
        nil
      end

      def self.truncate_backtrace(backtrace)
        return nil unless backtrace.is_a?(Array)
        backtrace.first(MAX_BACKTRACE_LINES)
      end
      private_class_method :truncate_backtrace
    end
  end
end
