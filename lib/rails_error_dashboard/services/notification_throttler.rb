# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Throttle error notifications to prevent alert fatigue
    #
    # Checks severity minimum, per-error cooldown, and threshold milestones.
    # Uses in-memory cache (same pattern as BaselineAlertThrottler).
    # Thread-safe via Mutex. Fail-open: returns true on any error.
    class NotificationThrottler
      # Severity levels ranked from lowest to highest
      SEVERITY_RANK = { low: 0, medium: 1, high: 2, critical: 3 }.freeze

      @last_notification_times = {}
      @mutex = Mutex.new

      class << self
        # Should we send a notification for this error?
        # Checks: severity minimum + cooldown period
        # @param error_log [ErrorLog] The error to check
        # @return [Boolean] true if notification should be sent
        def should_notify?(error_log)
          return false unless severity_meets_minimum?(error_log)

          cooldown_ok?(error_log)
        rescue => e
          # Fail-open: if throttler breaks, allow notification
          RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] NotificationThrottler.should_notify? failed: #{e.message}")
          true
        end

        # Does the error's severity meet the configured minimum?
        # @param error_log [ErrorLog] The error to check
        # @return [Boolean] true if severity is at or above minimum
        def severity_meets_minimum?(error_log)
          config = RailsErrorDashboard.configuration
          minimum = config.notification_minimum_severity || :low
          severity = SeverityClassifier.classify(error_log.error_type)

          (SEVERITY_RANK[severity] || 0) >= (SEVERITY_RANK[minimum] || 0)
        rescue => e
          RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] NotificationThrottler.severity_meets_minimum? failed: #{e.message}")
          true
        end

        # Has the error's occurrence count reached a configured threshold milestone?
        # @param error_log [ErrorLog] The error to check
        # @return [Boolean] true if occurrence_count matches a threshold
        def threshold_reached?(error_log)
          thresholds = RailsErrorDashboard.configuration.notification_threshold_alerts
          return false if thresholds.nil? || thresholds.empty?

          thresholds.include?(error_log.occurrence_count)
        rescue => e
          RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] NotificationThrottler.threshold_reached? failed: #{e.message}")
          false
        end

        # Record that a notification was sent for this error
        # @param error_log [ErrorLog] The error that was notified about
        def record_notification(error_log)
          key = error_log.error_hash

          @mutex.synchronize do
            @last_notification_times[key] = Time.current
          end
        rescue => e
          RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] NotificationThrottler.record_notification failed: #{e.message}")
        end

        # Clear all throttle state (for testing)
        def clear!
          @mutex.synchronize do
            @last_notification_times.clear
          end
        end

        # Remove old entries to prevent memory growth
        # @param max_age_hours [Integer] Remove entries older than this (default: 24)
        def cleanup!(max_age_hours: 24)
          cutoff_time = max_age_hours.hours.ago

          @mutex.synchronize do
            @last_notification_times.delete_if { |_, time| time < cutoff_time }
          end
        end

        private

        # Is the error outside the cooldown window?
        # @param error_log [ErrorLog] The error to check
        # @return [Boolean] true if not in cooldown (ok to notify)
        def cooldown_ok?(error_log)
          cooldown_minutes = RailsErrorDashboard.configuration.notification_cooldown_minutes
          return true if cooldown_minutes.nil? || cooldown_minutes <= 0

          key = error_log.error_hash

          @mutex.synchronize do
            last_time = @last_notification_times[key]
            return true if last_time.nil?

            Time.current > (last_time + cooldown_minutes.minutes)
          end
        end
      end
    end
  end
end
