# frozen_string_literal: true

module RailsErrorDashboard
  module Concerns
    # Retries for the per-error notification jobs (Slack, email, Discord,
    # Telegram, PagerDuty, webhook), and the cooldown claim when they give up.
    #
    # WHICH FAILURES RETRY
    #
    # A failure another attempt could fix: a timeout, a refused or reset
    # connection, a DNS failure, HTTP 429, HTTP 5xx, or an SMTP 4xx. Each job
    # turns one of those into a TransientDeliveryError, and retry_on below runs
    # it again. Anything else (HTTP 400, a bad token, a template error) would
    # fail the same way every time, so the job logs it and finishes. That is
    # why every job here still rescues StandardError: ApplicationJob's
    # `retry_on StandardError` must not retry what cannot succeed.
    #
    # The retry_on here is registered after ApplicationJob's, and Active Job
    # checks rescue handlers from the last one registered, so
    # TransientDeliveryError is matched here before StandardError is.
    #
    # THE CLAIM
    #
    # LogError takes the cooldown claim (error_logs.last_notified_at) before it
    # enqueues the jobs, and passes its time to each job as claimed_at. When a
    # job's retries run out it hands the claim back, so the next occurrence can
    # notify, but only if the column still holds that time: a newer claim
    # belongs to a later notification. A job enqueued without claimed_at (by
    # rc.1, or by the dashboard's test button) releases nothing.
    #
    # hardening-1-0-rc2, REQ-29 to REQ-31.
    module TransientDelivery
      extend ActiveSupport::Concern

      ATTEMPTS = 3

      # Raised by a channel job for a failure worth another attempt.
      class TransientDeliveryError < StandardError; end

      included do
        retry_on TransientDeliveryError, wait: :polynomially_longer, attempts: ATTEMPTS do |job, error|
          job.send(:delivery_retries_exhausted, error)
        end
      end

      # Connection-level failures another attempt could fix. Net::OpenTimeout,
      # Net::ReadTimeout and Net::WriteTimeout are Timeout::Errors; a DNS
      # failure is a SocketError (Socket::ResolutionError on Ruby 3.3+).
      NETWORK_ERRORS = [
        Timeout::Error,
        Errno::ETIMEDOUT,
        Errno::ECONNREFUSED,
        Errno::ECONNRESET,
        SocketError
      ].freeze

      class_methods do
        # @param error [Exception]
        # @return [Boolean] true if another attempt could succeed
        def transient_error?(error)
          return true if NETWORK_ERRORS.any? { |klass| error.is_a?(klass) }

          # SMTP 4xx. net/smtp is loaded by the mail gem when email is used;
          # without it there is no SMTP error to match.
          defined?(Net::SMTPServerBusy) && error.is_a?(Net::SMTPServerBusy) ? true : false
        end

        # @param code [#to_i] an HTTP status
        # @return [Boolean] true for 429 and 5xx
        def transient_status?(code)
          status = code.to_i
          status == 429 || (500..599).cover?(status)
        end
      end

      private

      # A retry the queue adapter can't schedule (:inline, and adapters with no
      # scheduler) makes this attempt the last one, so the claim goes back as
      # it does when the retries run out. ApplicationJob#retry_job calls this
      # (hardening-1-0-rc2, REQ-31, REQ-63).
      # @param error [Exception] the error retry_on was retrying (activejob 7.2 to 8.1)
      def retry_unschedulable(error)
        Rails.logger.error(
          "[RailsErrorDashboard] #{self.class.name.demodulize} could not schedule a retry: " \
          "the queue adapter has no scheduled jobs"
        )
        delivery_retries_exhausted(error)
      end

      # Run a send, turning a transient failure into a TransientDeliveryError.
      # Other errors propagate unchanged, for the job's own rescue to log.
      def deliver_or_retry
        yield
      rescue TransientDeliveryError
        raise
      rescue => e
        raise unless self.class.transient_error?(e)

        raise TransientDeliveryError, redact_delivery("#{e.class}: #{e.message}")
      end

      # Raise TransientDeliveryError for a 429 or 5xx answer.
      # @return [Boolean] true for a 2xx answer, false for any other the caller logs
      def check_delivery_response!(response, channel)
        code = response.code.to_i
        return true if (200..299).cover?(code)

        if self.class.transient_status?(code)
          raise TransientDeliveryError, "#{channel} answered HTTP #{code}"
        end

        false
      end

      # The text that goes in logs and error messages. Telegram overrides it:
      # its bot token is in the request URL.
      def redact_delivery(text)
        text
      end

      # The claim time this job was enqueued with, or nil (rc.1's jobs, the
      # dashboard's test button). Positional, after error_log_id and locale.
      def delivery_claimed_at
        arguments[2]
      end

      # release! never raises: a failed release only leaves the cooldown in place.
      def delivery_retries_exhausted(error)
        Rails.logger.error(
          "[RailsErrorDashboard] #{self.class.name.demodulize} gave up after #{executions} attempts: " \
          "#{redact_delivery(error.message)}"
        )
        Services::NotificationThrottler.release!(arguments.first, delivery_claimed_at)
      end
    end
  end
end
