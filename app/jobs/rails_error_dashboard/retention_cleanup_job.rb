# frozen_string_literal: true

module RailsErrorDashboard
  # Background job to enforce the retention_days configuration.
  # Deletes error logs (and their associated records) older than the configured threshold.
  # Uses batch deletion (in_batches + delete_all) for performance on large tables.
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

    # @return [Integer] number of errors deleted
    def perform
      retention_days = RailsErrorDashboard.configuration.retention_days
      return 0 if retention_days.blank?

      cutoff = retention_days.days.ago

      # Rack Attack events live in their own table and expire independently of
      # errors — clean them up BEFORE the early return below, which fires
      # whenever no error logs happen to be expired.
      cleanup_rack_attack_events(cutoff)
      cleanup_storm_flush_batches(cutoff)
      cleanup_diagnostic_dumps(cutoff)
      cleanup_swallowed_exceptions(cutoff)

      expired_scope = self.class.expired_scope(cutoff)
      return 0 if expired_scope.none?

      deleted_count = 0

      # Delete dependents first, then errors — all in batches to prevent table locks
      expired_ids_scope = expired_scope.select(:id)

      # Batch delete dependent records (occurrences, comments, cascade patterns)
      ErrorOccurrence.where(error_log_id: expired_ids_scope).in_batches(of: 1000).delete_all
      ErrorComment.where(error_log_id: expired_ids_scope).in_batches(of: 1000).delete_all
      CascadePattern.where(parent_error_id: expired_ids_scope)
                    .or(CascadePattern.where(child_error_id: expired_ids_scope))
                    .in_batches(of: 1000).delete_all

      # Now batch delete the error logs themselves
      expired_scope.in_batches(of: 1000) do |batch|
        batch_size = batch.delete_all
        deleted_count += batch_size
      end

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

    private

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
