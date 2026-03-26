# frozen_string_literal: true

module RailsErrorDashboard
  # Background job to close a linked issue when an error is resolved.
  #
  # Triggered via :on_error_resolved plugin hook.
  # Adds a comment before closing: "Resolved in Rails Error Dashboard by {name}"
  class CloseLinkedIssueJob < ApplicationJob
    queue_as :error_notifications

    retry_on StandardError, wait: :polynomially_longer, attempts: 2
    discard_on ActiveRecord::RecordNotFound

    def perform(error_log_id)
      error = ErrorLog.find(error_log_id)
      return unless error.external_issue_url.present? && error.external_issue_number.present?

      client = Services::IssueTrackerClient.from_config
      return unless client

      # Add resolution comment
      resolved_by = error.resolved_by_name.presence || "a team member"
      comment = "Resolved in Rails Error Dashboard by #{resolved_by}."
      comment += "\n\nResolution: #{error.resolution_comment}" if error.resolution_comment.present?

      client.add_comment(number: error.external_issue_number, body: comment)

      # Close the issue
      result = client.close_issue(number: error.external_issue_number)
      if result[:success]
        Rails.logger.info("[RailsErrorDashboard] Closed issue ##{error.external_issue_number} for error #{error_log_id}")
      else
        Rails.logger.error("[RailsErrorDashboard] Failed to close issue ##{error.external_issue_number}: #{result[:error]}")
      end
    rescue ActiveRecord::RecordNotFound
      # Error was deleted
    rescue => e
      Rails.logger.error("[RailsErrorDashboard] CloseLinkedIssueJob failed: #{e.class}: #{e.message}")
      raise # retry
    end
  end
end
