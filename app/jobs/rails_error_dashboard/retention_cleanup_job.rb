# frozen_string_literal: true

module RailsErrorDashboard
  # Background job to enforce the retention_days and occurrence_retention_days
  # configuration. Deletes error logs (and their associated records) not seen
  # for retention_days, then the occurrences of the errors still live that are
  # older than occurrence_retention_days. Uses batch deletion (in_batches +
  # delete_all) for performance on large tables.
  #
  # Schedule this job daily via your preferred scheduler (SolidQueue, Sidekiq, cron).
  #
  # @example Schedule in initializer
  #   RailsErrorDashboard.configure do |config|
  #     config.retention_days = 90
  #   end
  class RetentionCleanupJob < ApplicationJob
    queue_as :default

    # The errors retention applies to: "not seen for retention_days", not
    # "first seen retention_days ago". occurred_at is stamped when a group is
    # created and never moves, so expiring by it deleted errors that were still
    # happening today -- with their comments and triage history -- the day
    # they turned N days old.
    #
    # Equivalent to COALESCE(last_seen_at, occurred_at) < cutoff (the NULL arm
    # covers rows from before last_seen_at existed), but written so that each
    # arm can use its own index; wrapping the columns in COALESCE would force a
    # full scan of the largest table on every run.
    #
    # Public because the rake task previews the same selection before it asks
    # for confirmation.
    def self.expired_scope(cutoff)
      ErrorLog.where(
        "last_seen_at < :cutoff OR (last_seen_at IS NULL AND occurred_at < :cutoff)", cutoff: cutoff
      )
    end

    # Deletes error logs and everything that references them: dependents first,
    # all in batches. Occurrences, comments and cascade patterns hold foreign
    # keys to the log, so deleting the logs first fails, and one unbounded
    # DELETE would lock the table. Public because rails_error_dashboard:cleanup_resolved
    # deletes the same way.
    #
    # @param scope [ActiveRecord::Relation] the ErrorLog rows to delete
    # @return [Integer] number of error logs deleted
    def self.delete_with_dependents(scope)
      ids = scope.select(:id)

      # Each occurrence's stored context. Named here for the same reason as the
      # event counts below: delete_all fires no :dependent callback.
      if ErrorOccurrenceContext.table_exists?
        ErrorOccurrenceContext.where(error_log_id: ids).in_batches(of: 1000).delete_all
      end
      ErrorOccurrence.where(error_log_id: ids).in_batches(of: 1000).delete_all
      # Hour buckets for storm-shed events. Listed explicitly because delete_all
      # does not fire the has_many :dependent callback on ErrorLog -- without
      # this line the buckets outlive the group they describe, forever.
      EventCount.where(error_log_id: ids).in_batches(of: 1000).delete_all if EventCount.table_exists?
      ErrorComment.where(error_log_id: ids).in_batches(of: 1000).delete_all
      CascadePattern.where(parent_error_id: ids)
                    .or(CascadePattern.where(child_error_id: ids))
                    .in_batches(of: 1000).delete_all

      deleted = 0
      scope.in_batches(of: 1000) { |batch| deleted += batch.delete_all }
      deleted
    end

    # The occurrences occurrence retention deletes. After the job has expired
    # old errors, every row left here belongs to an error that is still live.
    # The (occurred_at, error_log_id) index covers the condition. Public
    # because the rake task previews the same selection.
    def self.expired_occurrences(cutoff)
      ErrorOccurrence.where("occurred_at < ?", cutoff)
    end

    # Deletes the occurrences older than +cutoff+ and their stored contexts,
    # 1,000 at a time. Before a batch goes, its events are added to their
    # groups' EventCount buckets, in the same transaction, so every window
    # count the dashboard shows still includes them: only the per-event detail
    # (user, request, release, context) is lost. The group row isn't touched,
    # so its occurrence_count and first and last seen stay as they were.
    #
    # A batch whose buckets can't be written is rolled back, buckets and all,
    # and the pass stops there: deleting it would drop its events from every
    # window. A transient store error raises out of here, like any other.
    #
    # @param cutoff [Time]
    # @return [Integer] number of occurrences deleted
    def self.delete_old_occurrences(cutoff)
      with_contexts = ErrorOccurrenceContext.table_exists?
      deleted = 0

      expired_occurrences(cutoff).in_batches(of: 1000) do |batch|
        rows = batch.pluck(:id, :error_log_id, :occurred_at)
        events = Hash.new(0)
        rows.each { |_id, error_log_id, occurred_at| events[[ error_log_id, EventCount.bucket_for(occurred_at) ]] += 1 }

        # requires_new: inside a caller's transaction a plain one only joins
        # it, and the Rollback below would undo nothing.
        removed = ErrorOccurrence.transaction(requires_new: true) do
          written = events.all? do |(error_log_id, bucket_at), count|
            EventCount.accumulate(error_log_id: error_log_id, bucket_at: bucket_at, count: count) == :written
          end
          raise ActiveRecord::Rollback unless written

          ids = rows.map(&:first)
          ErrorOccurrenceContext.where(error_occurrence_id: ids).delete_all if with_contexts
          ErrorOccurrence.where(id: ids).delete_all
        end

        unless removed
          RailsErrorDashboard::Logger.error(
            "[RailsErrorDashboard] Occurrence retention stopped after #{deleted} occurrences: " \
            "their event count buckets couldn't be written, so no more were deleted"
          )
          break
        end
        deleted += removed
      end

      deleted
    end

    # The number of occurrences the last #perform deleted.
    attr_reader :occurrences_deleted

    # @return [Integer] number of errors deleted
    def perform
      config = RailsErrorDashboard.configuration
      deleted_count = config.retention_days.present? ? expire_errors(config.retention_days) : 0
      # After the errors, so only live errors' occurrences are left to delete.
      # It runs whatever happened above: each pass has its own rescue.
      @occurrences_deleted = expire_occurrences(config.occurrence_retention_days)
      deleted_count
    end

    private

    def expire_errors(retention_days)
      cutoff = retention_days.days.ago

      # Rack Attack events live in their own table and expire independently of
      # errors — clean them up BEFORE the early return below, which fires
      # whenever no error logs happen to be expired.
      cleanup_rack_attack_events(cutoff)
      cleanup_missing_translations(cutoff)
      cleanup_storm_flush_batches(cutoff)
      cleanup_diagnostic_dumps(cutoff)
      cleanup_swallowed_exceptions(cutoff)
      cleanup_event_timing_gaps(cutoff)

      expired_scope = self.class.expired_scope(cutoff)
      return 0 if expired_scope.none?

      deleted_count = self.class.delete_with_dependents(expired_scope)

      # delete_all skips callbacks, and the stat cards are cached.
      Services::AnalyticsCacheManager.clear if deleted_count > 0

      if deleted_count > 0
        RailsErrorDashboard::Logger.info(
          "[RailsErrorDashboard] Retention cleanup: deleted #{deleted_count} errors older than #{retention_days} days"
        )
      end

      deleted_count
    rescue => e
      RailsErrorDashboard::Logger.error("[RailsErrorDashboard] Retention cleanup failed: #{e.class} - #{e.message}")
      0
    end

    def expire_occurrences(days)
      return 0 if days.blank?

      deleted = self.class.delete_old_occurrences(days.days.ago)
      if deleted > 0
        # The counts are unchanged, but affected users and the occurrence
        # lists aren't, and the stat cards are cached.
        Services::AnalyticsCacheManager.clear
        RailsErrorDashboard::Logger.info(
          "[RailsErrorDashboard] Retention cleanup: deleted #{deleted} occurrences older than #{days} days"
        )
      end
      deleted
    rescue => e
      RailsErrorDashboard::Logger.error("[RailsErrorDashboard] Occurrence retention failed: #{e.class} - #{e.message}")
      0
    end

    # Expire the storm batch ledger. Its only job is to make a replayed batch
    # a no-op, and a replay arrives within the job's retry window (minutes),
    # so rows well past the retention cutoff protect nothing. Own rescue, like
    # the rack-attack cleanup: a failure here must never block error cleanup.
    def cleanup_storm_flush_batches(cutoff)
      return unless RailsErrorDashboard.configuration.enable_storm_protection
      return unless StormFlushBatch.table_exists?

      deleted = 0
      StormFlushBatch.where("applied_at < ?", cutoff).in_batches(of: 1000) do |batch|
        deleted += batch.delete_all
      end

      if deleted > 0
        RailsErrorDashboard::Logger.info(
          "[RailsErrorDashboard] Retention cleanup: deleted #{deleted} storm flush batch records"
        )
      end
    rescue => e
      RailsErrorDashboard::Logger.debug(
        "[RailsErrorDashboard] Storm flush batch retention cleanup failed: #{e.class} - #{e.message}"
      )
    end

    # Diagnostic dumps and swallowed-exception aggregates are written
    # independently of error logs and nothing else ever deletes them, so they
    # grew without bound. Not gated on their feature flags: rows written while
    # a feature was on must still expire after it is switched off. Own rescue
    # each, like the cleanups around them.
    def cleanup_diagnostic_dumps(cutoff)
      return unless DiagnosticDump.table_exists?

      deleted = 0
      DiagnosticDump.where("captured_at < ?", cutoff).in_batches(of: 1000) do |batch|
        deleted += batch.delete_all
      end

      if deleted > 0
        RailsErrorDashboard::Logger.info(
          "[RailsErrorDashboard] Retention cleanup: deleted #{deleted} diagnostic dumps"
        )
      end
    rescue => e
      RailsErrorDashboard::Logger.debug(
        "[RailsErrorDashboard] Diagnostic dump retention cleanup failed: #{e.class} - #{e.message}"
      )
    end

    def cleanup_swallowed_exceptions(cutoff)
      return unless SwallowedException.table_exists?

      deleted = 0
      SwallowedException.where("period_hour < ?", cutoff).in_batches(of: 1000) do |batch|
        deleted += batch.delete_all
      end

      if deleted > 0
        RailsErrorDashboard::Logger.info(
          "[RailsErrorDashboard] Retention cleanup: deleted #{deleted} swallowed exception records"
        )
      end
    rescue => e
      RailsErrorDashboard::Logger.debug(
        "[RailsErrorDashboard] Swallowed exception retention cleanup failed: #{e.class} - #{e.message}"
      )
    end

    # Timing gaps are pruned by their OWN age, not by a group.
    #
    # A gap describes an interval, not an error, so there is no error_log_id to
    # cascade from -- without this it would accumulate for the life of the
    # installation. It also runs ABOVE the early return in #perform, which
    # fires whenever no error logs happen to be expired: gaps expire
    # independently of errors, exactly like the rack-attack events whose
    # comment already warns about this.
    #
    # Safe to prune on covered_until: once the cutoff has moved past a gap, no
    # window the dashboard displays can still reach it, so the warning it
    # carries is no longer meaningful. Own rescue, like its siblings.
    def cleanup_event_timing_gaps(cutoff)
      return unless EventTimingGap.table_exists?

      # Kept for the LONGER of the two horizons that govern it.
      #
      # This used the configured retention cutoff alone, which is wrong
      # whenever retention is shorter than the window the dashboard reports on:
      # at retention_days = 7 the gap was deleted while the events it qualified
      # were still on the page -- ten monthly events, no warning, group still
      # active. A gap outlives its own retention precisely because the figures
      # it qualifies do.
      #
      # Deleting it only once BOTH clocks have passed means the warning can
      # never disappear while the numbers it describes are still displayed.
      # The reverse case is unaffected: with the 90-day default the retention
      # cutoff is already the later of the two, so nothing is kept longer than
      # before.
      gap_cutoff = [ cutoff, Queries::DashboardStats::WIDEST_DISPLAYED_WINDOW.ago ].min

      deleted = 0
      EventTimingGap.where("covered_until < ?", gap_cutoff).in_batches(of: 1000) do |batch|
        deleted += batch.delete_all
      end

      if deleted > 0
        RailsErrorDashboard::Logger.info(
          "[RailsErrorDashboard] Retention cleanup: deleted #{deleted} event timing gaps"
        )
      end
    rescue => e
      RailsErrorDashboard::Logger.debug(
        "[RailsErrorDashboard] Event timing gap retention cleanup failed: #{e.class} - #{e.message}"
      )
    end

    # Expire missing-translation rows not seen since the cutoff. A key that
    # is still missing is still being seen, so it keeps its row (and its
    # first_seen_at); only keys that stopped missing age out.
    #
    # Not gated on the feature flag: rows collected while tracking was on
    # must still age out after it is turned off.
    def cleanup_missing_translations(cutoff)
      return unless MissingTranslation.table_exists?

      deleted = 0
      MissingTranslation.where("last_seen_at < ?", cutoff).in_batches(of: 1000) do |batch|
        deleted += batch.delete_all
      end

      if deleted > 0
        RailsErrorDashboard::Logger.info(
          "[RailsErrorDashboard] Retention cleanup: deleted #{deleted} missing translations"
        )
      end
    rescue => e
      RailsErrorDashboard::Logger.debug(
        "[RailsErrorDashboard] Missing translation retention cleanup failed: #{e.class} - #{e.message}"
      )
    end

    # Expire aggregated Rack Attack event rows. Isolated in its own rescue so a
    # failure here (e.g. table not yet migrated) never blocks error cleanup.
    def cleanup_rack_attack_events(cutoff)
      return unless RailsErrorDashboard.configuration.enable_rack_attack_tracking
      return unless RackAttackEvent.table_exists?

      deleted = 0
      RackAttackEvent.where("period_hour < ?", cutoff).in_batches(of: 1000) do |batch|
        deleted += batch.delete_all
      end

      if deleted > 0
        RailsErrorDashboard::Logger.info(
          "[RailsErrorDashboard] Retention cleanup: deleted #{deleted} rack attack events"
        )
      end
    rescue => e
      RailsErrorDashboard::Logger.debug(
        "[RailsErrorDashboard] Rack attack retention cleanup failed: #{e.class} - #{e.message}"
      )
    end
  end
end
