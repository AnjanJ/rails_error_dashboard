# frozen_string_literal: true

module RailsErrorDashboard
  # Background job to reopen a linked issue when an error recurs after resolution.
  #
  # Triggered via :on_error_reopened plugin hook.
  # Adds a comment: "Error recurred — reopened automatically. Occurrence #{count}"
  class ReopenLinkedIssueJob < ApplicationJob
    queue_as :error_notifications

    retry_on StandardError, wait: :polynomially_longer, attempts: 2
    discard_on ActiveRecord::RecordNotFound

    def perform(error_log_id)
      error = ErrorLog.find(error_log_id)
      return unless error.external_issue_url.present? && error.external_issue_number.present?

      client = Services::IssueTrackerClient.from_config
      return unless client

      # Reopen the issue
      result = client.reopen_issue(number: error.external_issue_number)

      # Add recurrence comment
      comment = "**Reopened** — error recurred.\n\n"
      comment += "- **Occurrences:** #{error.occurrence_count}\n"
      comment += "- **Last seen:** #{error.last_seen_at&.utc&.strftime("%Y-%m-%d %H:%M:%S UTC")}"
      comment += "\n\n---\n*[RED](https://github.com/AnjanJ/rails_error_dashboard) (Rails Error Dashboard)*"

      client.add_comment(number: error.external_issue_number, body: comment)

      if result[:success]
        Rails.logger.info("[RailsErrorDashboard] Reopened issue ##{error.external_issue_number} for error #{error_log_id}")
      else
        Rails.logger.error("[RailsErrorDashboard] Failed to reopen issue ##{error.external_issue_number}: #{result[:error]}")
      end
    rescue ActiveRecord::RecordNotFound
      # Error was deleted
    rescue => e
      Rails.logger.error("[RailsErrorDashboard] ReopenLinkedIssueJob failed: #{e.class}: #{e.message}")
      raise # retry
    end
  end
end
