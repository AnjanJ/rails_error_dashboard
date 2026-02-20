# frozen_string_literal: true

module RailsErrorDashboard
  # Background job to enforce the retention_days configuration.
  # Deletes error logs (and their associated records) older than the configured threshold.
  # Uses find_each + destroy to respect dependent: :destroy on associations.
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
      deleted_count = 0

      # Use find_each to process in batches (default 1000)
      # destroy triggers dependent: :destroy on associations (occurrences, comments, cascades)
      ErrorLog.where("occurred_at < ?", cutoff).find_each do |error_log|
        error_log.destroy
        deleted_count += 1
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
  end
end
