# frozen_string_literal: true

module RailsErrorDashboard
  class EmailErrorNotificationJob < ApplicationJob
    include Concerns::TransientDelivery

    queue_as :error_notifications

    # @param locale [String, nil] resolved at enqueue time. nil for jobs
    #   enqueued by a pre-Phase-4 version still draining from the queue.
    # @param claimed_at [Time, nil] the cooldown claim to release if every
    #   attempt fails (Concerns::TransientDelivery). nil for rc.1's jobs.
    def perform(error_log_id, locale = nil, claimed_at = nil)
      error_log = ErrorLog.find_by(id: error_log_id)
      return unless error_log

      recipients = RailsErrorDashboard.configuration.notification_email_recipients
      return unless recipients.present?

      # A timeout, a refused connection or an SMTP 4xx retries; an SMTP 5xx
      # (unknown recipient, rejected sender) would fail every time.
      deliver_or_retry do
        ErrorNotificationMailer.error_alert(error_log, recipients, locale: job_locale(locale)).deliver_now
      end
    rescue TransientDeliveryError
      raise
    rescue => e
      Rails.logger.error("[RailsErrorDashboard] Failed to send email notification: #{e.message}")
      Rails.logger.error(e.backtrace&.first(5)&.join("\n")) if e.backtrace
    end
  end
end
