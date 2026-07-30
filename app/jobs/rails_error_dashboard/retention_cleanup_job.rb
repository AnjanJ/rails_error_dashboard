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

    # @return [Integer] number of errors deleted
    def perform
      retention_days = RailsErrorDashboard.configuration.retention_days
      return 0 if retention_days.blank?

      cutoff = retention_days.days.ago

      # Rack Attack events live in their own table and expire independently of
      # errors — clean them up BEFORE the early return below, which fires
      # whenever no error logs happen to be expired.
      cleanup_rack_attack_events(cutoff)

      expired_scope = ErrorLog.where("occurred_at < ?", cutoff)
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
