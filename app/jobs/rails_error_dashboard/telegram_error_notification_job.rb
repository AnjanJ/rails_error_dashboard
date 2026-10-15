# frozen_string_literal: true

module RailsErrorDashboard
  # Job to send error notifications to a Telegram chat via the Bot API
  class TelegramErrorNotificationJob < ApplicationJob
    queue_as :default

    # @param locale [String, nil] resolved at enqueue time.
    def perform(error_log_id, locale = nil)
      return unless Services::TelegramDelivery.credentials?

      error_log = ErrorLog.find(error_log_id)
      payload = Services::TelegramPayloadBuilder.call(error_log, locale: job_locale(locale))

      Services::TelegramDelivery.post(payload)
    rescue StandardError => e
      # The bot token is in the request URL; an exception that quotes it must
      # not reach the log as-is.
      Rails.logger.error(
        "[RailsErrorDashboard] Failed to send Telegram notification: #{Services::TelegramDelivery.redact(e.message)}"
      )
      Rails.logger.error(e.backtrace&.first(5)&.join("\n")) if e.backtrace
    end
  end
end
