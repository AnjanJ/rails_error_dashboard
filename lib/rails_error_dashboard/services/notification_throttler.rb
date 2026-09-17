# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Throttle error notifications to prevent alert fatigue
    #
    # Checks severity minimum, per-error cooldown, and threshold milestones.
    #
    # The cooldown is CLAIMED IN THE DATABASE (error_logs.last_notified_at, see
    # claim!). A per-process Hash cannot do this job: every Puma worker and
    # every job process has its own, so one error reopened by a bad deploy
    # notified once per process, and a restart forgot the cooldown altogether.
    # The Hash survives only as a bounded fallback for the window between
    # upgrading the gem and running its migration, and for callers that pass
    # something other than a persisted row.
    #
    # Thread-safe via Mutex. Fail-open: returns true on any error.
    class NotificationThrottler
      # Severity levels ranked from lowest to highest
      SEVERITY_RANK = { low: 0, medium: 1, high: 2, critical: 3 }.freeze

      # Hard cap on the in-process fallback. Expired entries are swept on every
      # insert; the cap only bites when more than this many distinct errors are
      # inside their cooldown at once, and then the oldest goes first.
      MAX_TRACKED = 1_000

      COOLDOWN_COLUMN = "last_notified_at"

      @last_notification_times = {}
      @mutex = Mutex.new
      @burst_mutex = Mutex.new
      @burst_window_start = nil
      @burst_count = 0

      class << self
        # Take the right to notify about this error, atomically.
        #
        # Call it immediately BEFORE dispatching, and dispatch only on true. It
        # is claim-then-send: a claim followed by a failed send is not handed
        # back, so that error stays quiet until the cooldown ends. The
        # alternative (send, then record) is what let N processes all send.
        #
        # With the column present this is ONE statement and no read:
        #
        #   UPDATE error_logs SET last_notified_at = :now
        #   WHERE id = :id AND (last_notified_at IS NULL OR last_notified_at < :cutoff)
        #
        # Exactly one connection can match the row, on SQLite, PostgreSQL and
        # MySQL alike, so exactly one process notifies per cooldown window.
        #
        # @param error_log [ErrorLog] the row being notified about
        # @param respect_cooldown [Boolean] false for notifications the cooldown
        #   has never applied to (first occurrence, threshold milestones): always
        #   granted, but still stamped, so a reopen soon afterwards is throttled
        # @return [Boolean] true if the caller may notify
        def claim!(error_log, respect_cooldown: true)
          minutes = respect_cooldown ? cooldown_minutes : 0

          if database_claim?(error_log)
            claim_in_database(error_log, minutes)
          else
            claim_in_process(error_log, minutes)
          end
        rescue => e
          # Fail-open: a throttler that cannot decide must not lose a page.
          RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] NotificationThrottler.claim! failed: #{e.class}: #{e.message}")
          true
        end

        # Should we send a notification for this error? Read-only (severity
        # minimum + cooldown): it takes nothing. claim! is what notifies.
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

        # Does this error's environment pass config.notification_environments?
        #
        # nil list → everything notifies (the pre-0.11 behaviour). Accepts an
        # ErrorLog, a bare environment name, or nothing (the process
        # environment) — the storm and baseline paths have no row to hand over.
        # A legacy row with a NULL environment is judged as the process
        # environment, so upgrading never silences an error that was notifying
        # before. Fails open: an allowlist bug must not lose a page.
        #
        # @param subject [ErrorLog, String, nil]
        # @return [Boolean]
        def environment_allowed?(subject = nil)
          allowed = RailsErrorDashboard.configuration.notification_environments
          return true if allowed.nil?

          name = subject.respond_to?(:environment) ? subject.environment : subject
          name = RailsErrorDashboard.configuration.current_environment if name.blank?
          allowed.include?(name.to_s)
        rescue => e
          RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] NotificationThrottler.environment_allowed? failed: #{e.message}")
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

        # May a FIRST-OCCURRENCE notification go out right now?
        #
        # The per-error cooldown cannot bound a bad deploy that produces hundreds
        # of DISTINCT new errors: each is a first occurrence, and first
        # occurrences always notify. This is a fixed window counter:
        #
        #   :notify    within config.notification_burst_limit for this window
        #   :summarize the first one over the limit: send ONE summary instead
        #   :suppress  everything after that, until the window ends
        #
        # Per process, like Gate.issue_creation_allowed?, because there is no
        # store every deployment shares except the database and this is asked on
        # the capture path. Worst case is limit x processes per window.
        #
        # Each call consumes a slot: ask only when about to notify. A limit or
        # window of 0 / nil turns the cap off. Fails open to :notify.
        #
        # @return [Symbol] :notify, :summarize or :suppress
        def burst_decision
          limit = RailsErrorDashboard.configuration.notification_burst_limit.to_i
          window = RailsErrorDashboard.configuration.notification_burst_window_seconds.to_i
          return :notify unless limit.positive? && window.positive?

          now = monotonic_now
          count = @burst_mutex.synchronize do
            if @burst_window_start.nil? || now - @burst_window_start >= window
              @burst_window_start = now
              @burst_count = 0
            end
            @burst_count += 1
          end

          if count <= limit
            :notify
          elsif count == limit + 1
            :summarize
          else
            :suppress
          end
        rescue => e
          RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] NotificationThrottler.burst_decision failed: #{e.class}: #{e.message}")
          :notify
        end

        # Record that a notification was sent for this error, unconditionally.
        # Kept for callers that notify outside LogError; LogError itself uses
        # claim!, which decides and records in one step.
        # @param error_log [ErrorLog] The error that was notified about
        def record_notification(error_log)
          claim!(error_log, respect_cooldown: false)
          nil
        end

        # Clear all in-process throttle state (for testing)
        def clear!
          @mutex.synchronize do
            @last_notification_times.clear
          end
          @burst_mutex.synchronize do
            @burst_window_start = nil
            @burst_count = 0
          end
        end

        private

        def monotonic_now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def cooldown_minutes
          RailsErrorDashboard.configuration.notification_cooldown_minutes.to_i
        end

        # A persisted row AND the column: before the migration has run the
        # UPDATE would raise on every notification.
        def database_claim?(error_log)
          error_log.is_a?(ErrorLog) && error_log.persisted? &&
            ErrorLog.column_names.include?(COOLDOWN_COLUMN)
        end

        def claim_in_database(error_log, minutes)
          now = Time.current
          scope = ErrorLog.where(id: error_log.id)
          if minutes.positive?
            scope = scope.where("#{COOLDOWN_COLUMN} IS NULL OR #{COOLDOWN_COLUMN} < ?", now - minutes.minutes)
          end

          granted = scope.update_all(COOLDOWN_COLUMN => now) == 1
          # No cooldown to lose: a row deleted under us must not silence the page.
          granted || !minutes.positive?
        end

        def claim_in_process(error_log, minutes)
          key = error_log.error_hash
          now = Time.current

          @mutex.synchronize do
            last_time = @last_notification_times[key]
            next false if minutes.positive? && last_time && now <= last_time + minutes.minutes

            remember(key, now)
            true
          end
        end

        # Caller holds @mutex. Delete-and-reinsert keeps the Hash in recency
        # order, so "oldest" is simply the first key.
        def remember(key, now)
          window = cooldown_minutes
          @last_notification_times.delete(key)
          # With no cooldown nothing will ever read the entry back.
          return unless window.positive?

          cutoff = now - window.minutes
          @last_notification_times.delete_if { |_, time| time < cutoff }
          @last_notification_times.shift while @last_notification_times.size >= MAX_TRACKED
          @last_notification_times[key] = now
        end

        # Is the error outside the cooldown window? Read-only.
        # @param error_log [ErrorLog] The error to check
        # @return [Boolean] true if not in cooldown (ok to notify)
        def cooldown_ok?(error_log)
          minutes = cooldown_minutes
          return true unless minutes.positive?

          last_time =
            if database_claim?(error_log)
              # Read the ROW, not the object: claim! stamps it with update_all,
              # so the caller's copy -- and every other process's -- is stale.
              ErrorLog.where(id: error_log.id).pick(COOLDOWN_COLUMN)
            else
              @mutex.synchronize { @last_notification_times[error_log.error_hash] }
            end
          return true if last_time.nil?

          Time.current > (last_time + minutes.minutes)
        end
      end
    end
  end
end
