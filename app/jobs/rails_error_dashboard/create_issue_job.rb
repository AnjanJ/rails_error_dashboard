# frozen_string_literal: true

module RailsErrorDashboard
  # Background job for creating issues on GitHub/GitLab/Codeberg.
  #
  # Used by auto-create (triggered from plugin hooks) and can be
  # called directly for deferred issue creation.
  #
  # Retry strategy: 3 attempts with exponential backoff.
  # Circuit breaker: skips if >5 failures in the last 10 minutes
  # (tracked via class-level counter, reset on success).
  class CreateIssueJob < ApplicationJob
    queue_as :error_notifications

    retry_on StandardError, wait: :polynomially_longer, attempts: 3
    discard_on ActiveRecord::RecordNotFound

    # Simple circuit breaker — class-level failure tracking
    @@recent_failures = []
    CIRCUIT_BREAKER_THRESHOLD = 5
    CIRCUIT_BREAKER_WINDOW = 600 # 10 minutes

    def perform(error_log_id, dashboard_url: nil)
      if circuit_open?
        Rails.logger.warn("[RailsErrorDashboard] CreateIssueJob circuit breaker open — skipping")
        return
      end

      result = Commands::CreateIssue.call(error_log_id, dashboard_url: dashboard_url)

      if result[:success]
        record_success
        Rails.logger.info("[RailsErrorDashboard] Issue created for error #{error_log_id}: #{result[:issue_url]}")
      else
        record_failure
        Rails.logger.error("[RailsErrorDashboard] Failed to create issue for error #{error_log_id}: #{result[:error]}")
        # Don't retry on "already has a linked issue" or "not configured"
        return if result[:error]&.include?("already has") || result[:error]&.include?("not configured")
        raise "Issue creation failed: #{result[:error]}" # triggers retry
      end
    rescue ActiveRecord::RecordNotFound
      # Error was deleted — discard silently
    rescue => e
      record_failure
      raise # re-raise for retry
    end

    private

    def circuit_open?
      cleanup_old_failures
      @@recent_failures.size >= CIRCUIT_BREAKER_THRESHOLD
    end

    def record_failure
      @@recent_failures << Time.current
    end

    def record_success
      @@recent_failures.clear
    end

    def cleanup_old_failures
      cutoff = Time.current - CIRCUIT_BREAKER_WINDOW
      @@recent_failures.reject! { |t| t < cutoff }
    end
  end
end
