# frozen_string_literal: true

module RailsErrorDashboard
  class EmailErrorNotificationJob < ApplicationJob
    queue_as :error_notifications

    # @param locale [String, nil] resolved at enqueue time. nil for jobs
    #   enqueued by a pre-Phase-4 version still draining from the queue.
    def perform(error_log_id, locale = nil)
      error_log = ErrorLog.find_by(id: error_log_id)
      return unless error_log

      recipients = RailsErrorDashboard.configuration.notification_email_recipients
      return unless recipients.present?

      ErrorNotificationMailer.error_alert(error_log, recipients, locale: job_locale(locale)).deliver_now
    rescue => e
      Rails.logger.error("[RailsErrorDashboard] Failed to send email notification: #{e.message}")
      Rails.logger.error(e.backtrace&.first(5)&.join("\n")) if e.backtrace
    end
  end
end
