# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Determine if an exception should be logged
    #
    # No database access — checks configuration rules against exception data.
    # Used by LogError command to filter exceptions before logging.
    #
    # @example
    #   ExceptionFilter.should_log?(exception) # => true/false
    class ExceptionFilter
      # Distinct errors remembered for first-seen admission (see sampled_out?).
      # Eviction only costs one extra admitted sample, so there is no overflow
      # accounting here.
      MAX_SEEN = 1_000

      @seen = {}
      @seen_mutex = Mutex.new

      # Check if an exception should be logged (not ignored, not sampled out)
      # @param exception [Exception] The exception to check
      # @return [Boolean] true if the exception should be logged
      def self.should_log?(exception)
        return false if ignored?(exception)
        return false if sampled_out?(exception)
        true
      end

      # Check if exception is in the ignored exceptions list
      # Supports both string class names and regex patterns
      # @param exception [Exception] The exception to check
      # @return [Boolean] true if the exception should be ignored
      def self.ignored?(exception)
        ignored_exceptions = RailsErrorDashboard.configuration.ignored_exceptions
        return false if ignored_exceptions.blank?

        exception_class_name = exception.class.name

        ignored_exceptions.any? do |ignored|
          case ignored
          when String
            exception.is_a?(ignored.constantize)
          when Regexp
            exception_class_name.match?(ignored)
          else
            false
          end
        rescue NameError
          RailsErrorDashboard::Logger.warn("Invalid ignored exception class: #{ignored}")
          false
        end
      end

      # Check if exception should be skipped due to sampling rate
      # Critical errors are ALWAYS logged regardless of sampling
      # @param exception [Exception] The exception to check
      # @return [Boolean] true if the exception should be skipped
      #
      # The FIRST event of each error in this process is always admitted.
      # Sampling is a dice roll taken before anything is known about the error,
      # so at a rate of 0.01 an error that happens three times is usually never
      # recorded at all. Sampling is there to cut volume; it must not hide that
      # an error exists. A rate of 0.0 stays a hard off switch.
      def self.sampled_out?(exception)
        sampling_rate = RailsErrorDashboard.configuration.sampling_rate

        return false if sampling_rate >= 1.0
        return false if critical?(exception)
        return true if sampling_rate <= 0.0
        return false if first_sighting?(exception)

        rand > sampling_rate
      end

      # True exactly once per process for each (exception class, first
      # application frame). Coarser than the real fingerprint on purpose: the
      # fingerprint needs the application id (a query) and this runs before the
      # storm gate. Two errors raised from one line share a "first".
      #
      # Per process, so N workers admit N firsts. Bounded at MAX_SEEN, least
      # recently seen evicted first. Any failure means "not seen": admit.
      def self.first_sighting?(exception)
        key = seen_key(exception)

        @seen_mutex.synchronize do
          seen_before = !@seen.delete(key).nil?
          @seen.shift while @seen.size >= MAX_SEEN
          @seen[key] = true
          !seen_before
        end
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] ExceptionFilter.first_sighting? failed: #{e.class}: #{e.message}")
        true
      end

      # "ClassName|first application frame". The first backtrace line that is
      # not inside a gem or the Ruby core; the first line when there is no such
      # frame; nothing when the exception was never raised.
      def self.seen_key(exception)
        backtrace = exception.backtrace || []
        frame = backtrace.find { |line| !line.include?("/gems/") && !line.start_with?("<internal:") } || backtrace.first

        "#{exception.class.name}|#{frame.to_s.sub(/:in .*\z/, "")}"
      end

      def self.seen_size
        @seen_mutex.synchronize { @seen.size }
      end

      # Forget every sighting (specs, and after a fork).
      def self.reset_seen!
        @seen_mutex.synchronize { @seen.clear }
      end

      # Check if exception is a critical error type
      # @param exception [Exception] The exception to check
      # @return [Boolean] true if the exception is critical
      def self.critical?(exception)
        SeverityClassifier.critical?(exception.class.name)
      end
    end
  end
end
