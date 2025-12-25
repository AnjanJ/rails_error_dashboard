# frozen_string_literal: true

module RailsErrorDashboard
  class EmailErrorNotificationJob < ApplicationJob
    queue_as :error_notifications

    def perform(error_log_id)
      error_log = ErrorLog.find_by(id: error_log_id)
      return unless error_log

      recipients = RailsErrorDashboard.configuration.notification_email_recipients
      return unless recipients.present?

      ErrorNotificationMailer.error_alert(error_log, recipients).deliver_now
    rescue => e
      Rails.logger.error("[RailsErrorDashboard] Failed to send email notification: #{e.message}")
      Rails.logger.error(e.backtrace&.first(5)&.join("\n")) if e.backtrace
    end
  end
end
