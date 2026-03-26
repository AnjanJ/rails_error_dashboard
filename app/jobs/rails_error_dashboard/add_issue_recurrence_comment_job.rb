# frozen_string_literal: true

module RailsErrorDashboard
  # Background job to add a recurrence comment on a linked issue.
  #
  # Triggered via :on_error_recurred plugin hook.
  # Throttled: max 1 comment per hour per error to prevent spam on
  # high-frequency errors.
  class AddIssueRecurrenceCommentJob < ApplicationJob
    queue_as :error_notifications

    retry_on StandardError, wait: :polynomially_longer, attempts: 2
    discard_on ActiveRecord::RecordNotFound

    THROTTLE_INTERVAL = 3600 # 1 hour

    # Track last comment time per error to throttle
    @@last_comment_at = {}

    def perform(error_log_id)
      # Throttle: max 1 comment per hour per error
      if throttled?(error_log_id)
        Rails.logger.debug("[RailsErrorDashboard] Skipping recurrence comment for error #{error_log_id} — throttled")
        return
      end

      error = ErrorLog.find(error_log_id)
      return unless error.external_issue_url.present? && error.external_issue_number.present?

      client = Services::IssueTrackerClient.from_config
      return unless client

      comment = "Error occurred again (#{error.occurrence_count} total occurrences).\n\n"
      comment += "- **Last seen:** #{error.last_seen_at&.utc&.strftime("%Y-%m-%d %H:%M:%S UTC")}\n"
      comment += "- **First seen:** #{error.first_seen_at&.utc&.strftime("%Y-%m-%d %H:%M:%S UTC")}"

      result = client.add_comment(number: error.external_issue_number, body: comment)

      if result[:success]
        record_comment(error_log_id)
        Rails.logger.info("[RailsErrorDashboard] Added recurrence comment on issue ##{error.external_issue_number}")
      else
        Rails.logger.error("[RailsErrorDashboard] Failed to add recurrence comment: #{result[:error]}")
      end
    rescue ActiveRecord::RecordNotFound
      # Error was deleted
    rescue => e
      Rails.logger.error("[RailsErrorDashboard] AddIssueRecurrenceCommentJob failed: #{e.class}: #{e.message}")
      raise # retry
    end

    private

    def throttled?(error_log_id)
      last = @@last_comment_at[error_log_id]
      last && (Time.current - last) < THROTTLE_INTERVAL
    end

    def record_comment(error_log_id)
      @@last_comment_at[error_log_id] = Time.current
      # Cleanup old entries to prevent memory growth
      cleanup_stale_entries if @@last_comment_at.size > 1000
    end

    def cleanup_stale_entries
      cutoff = Time.current - THROTTLE_INTERVAL
      @@last_comment_at.reject! { |_, t| t < cutoff }
    end
  end
end
