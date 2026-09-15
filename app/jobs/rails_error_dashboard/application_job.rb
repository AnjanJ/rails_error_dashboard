module RailsErrorDashboard
  class ApplicationJob < ActiveJob::Base
    # Explicit, serialized locale for any job that renders user-facing text.
    # Jobs run outside the dashboard's around_action, so they must never read
    # the request-scoped locale directly — see Concerns::LocalizedJob for why.
    include Concerns::LocalizedJob

    # CRITICAL: Ensure job failures don't break the app or spam error logs
    # Retry failed jobs with polynomial backoff, but limit attempts
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    # Did this perform_later actually reach the queue?
    #
    # Active Job does NOT raise on every failed handoff: from Rails 7.2 an
    # ActiveJob::EnqueueError raised by the adapter is caught inside
    # perform_later, which then returns false and leaves enqueue_error set on
    # the job. A caller that only rescues therefore treats a dropped job as a
    # successful one. Callbacks that abort the enqueue behave the same way.
    #
    # Returns true for adapters/versions that predate successfully_enqueued?
    # (Rails 7.0/7.1 let the error propagate instead, so the caller's rescue
    # is what catches it there).
    #
    # @param job [ActiveJob::Base, false, nil] whatever perform_later returned
    # @return [Boolean]
    def self.enqueued?(job)
      return false unless job
      return job.successfully_enqueued? if job.respond_to?(:successfully_enqueued?)

      true
    end

    # Why a handoff failed, for the log line that reports it.
    # @param job [ActiveJob::Base, false, nil]
    # @return [String]
    def self.enqueue_failure_reason(job)
      (job.respond_to?(:enqueue_error) && job.enqueue_error&.message) ||
        "perform_later returned #{job.inspect}"
    end

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
