module RailsErrorDashboard
  class ApplicationJob < ActiveJob::Base
    # Explicit, serialized locale for any job that renders user-facing text.
    # Jobs run outside the dashboard's around_action, so they must never read
    # the request-scoped locale directly — see Concerns::LocalizedJob for why.
    include Concerns::LocalizedJob

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
    #
    # The line names the job by class and id, not its arguments: a capture
    # job's arguments are the capture (hardening-1-0-rc2, REQ-60). It is one
    # rate-limited line, and the detail goes to debug (REQ-54 to REQ-57).
    retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
      Services::CaptureFailureLog.report("#{job.class.name} (retries exhausted)", error, job_id: job.job_id) do
        [
          "[RailsErrorDashboard] Job #{job.class.name} failed: #{error.class} - #{error.message}",
          "Job ID: #{job.job_id}",
          "Attempt: #{job.executions}/3",
          error.backtrace&.first(10)&.join("\n"),
          "[RailsErrorDashboard] Job #{job.class.name} discarded after #{job.executions} attempts"
        ]
      end
    end

    # Active Job schedules a retry with the adapter's enqueue_at. :inline, and
    # adapters without a scheduler (Resque without resque-scheduler, Sneakers,
    # queue_classic), raise NotImplementedError there. That is a ScriptError,
    # so no `rescue => e` stops it, and under :inline a job runs inside
    # perform_later, on the thread that enqueued it: for most RED jobs, a
    # capture inside the host's request. A retry that can't be scheduled makes
    # this attempt the last one (hardening-1-0-rc2, REQ-63).
    #
    # One rescue here, for every RED job: a job that needs another answer
    # overrides retry_unschedulable, never retry_job (a retry_job of its own
    # that calls super would never see the NotImplementedError).
    def retry_job(options = {})
      super
    rescue NotImplementedError
      retry_unschedulable(options[:error])
    end

    # Did this perform_later actually reach the queue?
    #
    # Active Job does NOT raise on every failed handoff: from Rails 7.2 an
    # ActiveJob::EnqueueError raised by the adapter is caught inside
    # perform_later, which then returns false and leaves enqueue_error set on
    # the job. A caller that only rescues therefore treats a dropped job as a
    # successful one. Callbacks that abort the enqueue behave the same way.
    #
    # @param job [ActiveJob::Base, false, nil] whatever perform_later returned
    # @return [Boolean]
    def self.enqueued?(job)
      return false unless job

      job.successfully_enqueued?
    end

    # Why a handoff failed, for the log line that reports it.
    # @param job [ActiveJob::Base, false, nil]
    # @return [String]
    def self.enqueue_failure_reason(job)
      (job.respond_to?(:enqueue_error) && job.enqueue_error&.message) ||
        "perform_later returned #{job.inspect}"
    end

    private

    # What a RED job does when its retry can't be scheduled: one rate-limited
    # line, and the attempt ends (hardening-1-0-rc2, REQ-54, REQ-63).
    # Concerns::TransientDelivery overrides it to hand back the notification
    # claim.
    # @param error [Exception, nil] the error retry_on was retrying
    # @return [nil]
    def retry_unschedulable(error)
      name = self.class.name.delete_prefix("RailsErrorDashboard::")
      Services::CaptureFailureLog.report("#{name}#retry_job", "NotImplementedError", error, job_id: job_id) do
        "[RailsErrorDashboard] #{name} could not schedule a retry: the queue adapter has no scheduled jobs, " \
          "so this attempt was the last (#{error.class})"
      end
      nil
    end
  end
end
