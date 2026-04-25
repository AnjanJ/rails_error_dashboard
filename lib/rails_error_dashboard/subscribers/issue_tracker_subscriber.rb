# frozen_string_literal: true

module RailsErrorDashboard
  module Subscribers
    # Hooks into the error lifecycle to trigger issue tracker jobs.
    #
    # Called from the engine initializer via direct integration with
    # the LogError and ResolveError commands' callback mechanisms.
    #
    # All work is done via background jobs — never blocks the capture path.
    class IssueTrackerSubscriber
      class << self
        # Called when a new error is first logged
        def on_error_logged(error_log)
          return unless should_auto_create?(error_log)
          dashboard_url = Services::NotificationHelpers.dashboard_url(error_log)
          CreateIssueJob.perform_later(error_log.id, dashboard_url: dashboard_url)
        rescue => e
          nil
        end

        # Called when a resolved error recurs (auto-reopened)
        def on_error_reopened(error_log)
          return unless error_log.external_issue_url.present?
          return unless RailsErrorDashboard.configuration.enable_issue_tracking
          ReopenLinkedIssueJob.perform_later(error_log.id)
        rescue => e
          nil
        end

        # Called when an existing error occurs again
        def on_error_recurred(error_log)
          return unless error_log.external_issue_url.present?
          return unless RailsErrorDashboard.configuration.enable_issue_tracking
          AddIssueRecurrenceCommentJob.perform_later(error_log.id)
        rescue => e
          nil
        end

        # Called when an error is resolved in the dashboard
        def on_error_resolved(error_log)
          return unless error_log.external_issue_url.present?
          return unless RailsErrorDashboard.configuration.enable_issue_tracking
          CloseLinkedIssueJob.perform_later(error_log.id)
        rescue => e
          nil
        end

        private

        def should_auto_create?(error_log)
          config = RailsErrorDashboard.configuration
          return false unless config.enable_issue_tracking
          return false if error_log.external_issue_url.present?

          # Check if another error record with the same hash already has a linked
          # issue. The 24-hour dedup window in FindOrIncrementError can create new
          # ErrorLog records for the same logical error — we must not create
          # duplicate GitHub/GitLab issues for them (issue #114 screenshot).
          existing = ErrorLog
            .where(error_hash: error_log.error_hash, application_id: error_log.application_id)
            .where.not(external_issue_url: [ nil, "" ])
            .where.not(id: error_log.id)
            .order(created_at: :desc)
            .first

          if existing
            # Link this record to the existing issue instead of creating a new one
            error_log.update_columns(
              external_issue_url: existing.external_issue_url,
              external_issue_number: existing.external_issue_number,
              external_issue_provider: existing.external_issue_provider
            )
            return false
          end

          # First occurrence — always auto-create
          return true if error_log.occurrence_count == 1

          # Severity threshold check
          severity = error_log.severity&.to_sym
          if config.issue_tracker_auto_create_severities&.include?(severity)
            return true
          end

          false
        end
      end
    end
  end
end
