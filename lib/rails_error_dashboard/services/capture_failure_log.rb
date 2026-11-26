# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # The log line a failed capture writes (hardening-1-0-rc2, REQ-54 to
    # REQ-57; spike S2, .shipkit/research/silent-failures-spike.md).
    #
    # A capture-path failure writes one summary line at error, at most once a
    # minute per process for each key, the call site and the failure's class.
    # The line names the site, the failure's class, the reported exception's
    # class and how many failures with that key it suppressed since the last
    # line. It carries no message, context, param, URL or backtrace: a store
    # error's message can quote the row (PostgreSQL's "Failing row contains"),
    # and the context holds the request.
    #
    # The detail, what the site printed in 1.0.0-rc.1, goes to debug for every
    # failure, and only when enable_internal_logging is on with log_level
    # :debug. The caller builds it in a block, so the common case pays nothing
    # for it. At log_level :silent nothing is written.
    #
    # Never raises: it runs inside the rescue blocks of the capture path.
    class CaptureFailureLog
      INTERVAL_SECONDS = 60
      MAX_KEYS = 100

      # @param clock [#call] monotonic seconds; tests inject their own
      def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @clock = clock
        @mutex = Mutex.new
        @keys = {}
      end

      # @param site [String] RED's call site, such as "Commands::LogError#capture"
      # @param failure [Exception, String] what failed: the rescued exception,
      #   or the name of a condition with none
      # @param reported [Exception, nil] the exception being captured, if any
      # @param job_id [String, nil] the id of the RED job that failed, if any
      # @yieldreturn [Array<String>, String, nil] the detail lines
      # @return [nil]
      def report(site, failure, reported = nil, job_id: nil, &detail)
        summarize(site, failure, reported, job_id) if RailsErrorDashboard::Logger.enabled?(:error)
        write_detail(detail) if detail && RailsErrorDashboard::Logger.enabled?(:debug)
        nil
      rescue StandardError
        nil
      end

      def reset!
        @mutex.synchronize { @keys.clear }
        nil
      end

      class << self
        def report(...) = INSTANCE.report(...)

        def reset! = INSTANCE.reset!
      end

      private

      def summarize(site, failure, reported, job_id)
        failure_name = name_of(failure)
        site = site.to_s[0, 200]
        suppressed = admit([ site, failure_name ])
        return unless suppressed

        line = +"Capture failure in #{site}: #{failure_name}"
        line << ", reporting #{name_of(reported)}" if reported
        line << ", job #{job_id}" if job_id
        line << " (#{suppressed} suppressed since the last line; detail at log_level :debug with enable_internal_logging)"
        RailsErrorDashboard::Logger.error(line)
      end

      # The suppressed count to write with a line now, or nil to suppress this
      # one. The lock covers only the table, never the log write.
      def admit(key)
        @mutex.synchronize do
          now = @clock.call
          entry = @keys[key]
          if entry && now - entry[0] < INTERVAL_SECONDS
            entry[1] += 1
            next nil
          end

          suppressed = entry ? entry[1] : 0
          @keys.delete(key)
          @keys.shift while @keys.size >= MAX_KEYS
          @keys[key] = [ now, 0 ]
          suppressed
        end
      end

      def write_detail(detail)
        Array(detail.call).each { |line| RailsErrorDashboard::Logger.debug(line) if line }
      rescue StandardError
        nil
      end

      # A class name, never a message.
      def name_of(value)
        case value
        when Exception then value.class.name || "an anonymous exception class"
        when Module then value.name || "an anonymous class"
        when String then value[0, 200]
        else value.class.name.to_s
        end
      end

      INSTANCE = new
      private_constant :INSTANCE
    end
  end
end
