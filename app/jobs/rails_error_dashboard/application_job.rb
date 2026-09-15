module RailsErrorDashboard
  class ApplicationJob < ActiveJob::Base
    # Explicit, serialized locale for any job that renders user-facing text.
    # Jobs run outside the dashboard's around_action, so they must never read
    # the request-scoped locale directly — see Concerns::LocalizedJob for why.
    include Concerns::LocalizedJob

    # Polynomial backoff, as a Proc rather than the :polynomially_longer
    # symbol.
    #
    # That symbol arrived in Rails 7.1; on 7.0 -- which this gem still
    # supports -- retry_on raises "Couldn't determine a delay based on
    # :polynomially_longer" the moment a retry is actually scheduled. The
    # symbol therefore passed every 7.1+ CI row and failed every 7.0 one.
    #
    # This is the same formula Rails uses: (executions ** 4) + 2, with jitter.
    POLYNOMIAL_BACKOFF = ->(executions) {
      ((executions**4) + 2) + (Kernel.rand * (executions**4) * 0.15)
    }

    # CRITICAL: Ensure job failures don't break the app or spam error logs
    # Retry failed jobs with polynomial backoff, but limit attempts.
    #
    # This must be the ONLY StandardError handler on this class. A
    # `rescue_from StandardError` used to sit below it and log-then-re-raise:
    # rescue_from is resolved in reverse registration order, so it won the
    # lookup every time and retry_on's handler was never consulted. Retries
    # still happened (the re-raise reached the adapter) but the polynomial
    # backoff never applied -- failures retried immediately, three times, on
    # every job in the gem. The logging that block provided now runs from
    # retry_on's own exhaustion block, where it fires once, after the last
    # attempt, with the same detail.
    retry_on StandardError, wait: RailsErrorDashboard::ApplicationJob::POLYNOMIAL_BACKOFF, attempts: 3 do |job, error|
      Rails.logger.error("[RailsErrorDashboard] Job #{job.class.name} failed: #{error.class} - #{error.message}")
      Rails.logger.error("Job arguments: #{job.arguments.inspect}")
      Rails.logger.error("Attempt: #{job.executions}/3")
      Rails.logger.error(error.backtrace&.first(10)&.join("\n")) if error.backtrace
      Rails.logger.error("[RailsErrorDashboard] Job #{job.class.name} discarded after #{job.executions} attempts")
    end

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
  end
end
