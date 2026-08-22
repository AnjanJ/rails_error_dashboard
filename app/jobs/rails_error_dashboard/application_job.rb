module RailsErrorDashboard
  class ApplicationJob < ActiveJob::Base
    # Explicit, serialized locale for any job that renders user-facing text.
    # Jobs run outside the dashboard's around_action, so they must never read
    # the request-scoped locale directly — see Concerns::LocalizedJob for why.
    include Concerns::LocalizedJob

    # CRITICAL: Ensure job failures don't break the app or spam error logs
    # Retry failed jobs with exponential backoff, but limit attempts
    retry_on StandardError, wait: :exponentially_longer, attempts: 3

    # Global exception handling for all dashboard jobs
    rescue_from StandardError do |exception|
      # Log the error for debugging but don't propagate
      Rails.logger.error("[RailsErrorDashboard] Job #{self.class.name} failed: #{exception.class} - #{exception.message}")
      Rails.logger.error("Job arguments: #{arguments.inspect}")
      Rails.logger.error("Attempt: #{executions}/3") if respond_to?(:executions)
      Rails.logger.error(exception.backtrace&.first(10)&.join("\n")) if exception.backtrace

      # Re-raise to trigger retry mechanism (up to 3 attempts)
      # After 3 attempts, ActiveJob will discard the job and log it
      raise exception if executions < 3

      # If we've exhausted retries, log and give up gracefully
      Rails.logger.error("[RailsErrorDashboard] Job #{self.class.name} discarded after #{executions} attempts")
    end
  end
end
