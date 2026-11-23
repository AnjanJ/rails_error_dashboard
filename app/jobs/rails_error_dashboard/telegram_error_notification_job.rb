# frozen_string_literal: true

module RailsErrorDashboard
  # Job to send error notifications to a Telegram chat via the Bot API
  class TelegramErrorNotificationJob < ApplicationJob
    include Concerns::TransientDelivery

    queue_as :default

    # @param locale [String, nil] resolved at enqueue time.
    # @param claimed_at [Time, nil] the cooldown claim to release if every
    #   attempt fails (Concerns::TransientDelivery). nil for rc.1's jobs.
    def perform(error_log_id, locale = nil, claimed_at = nil)
      return unless Services::TelegramDelivery.credentials?

      error_log = ErrorLog.find(error_log_id)
      payload = Services::TelegramPayloadBuilder.call(error_log, locale: job_locale(locale))

      # TelegramDelivery logs a rejection with Telegram's own description.
      response = deliver_or_retry { Services::TelegramDelivery.post(payload) }
      check_delivery_response!(response, "Telegram") if response
    rescue TransientDeliveryError
      raise
    rescue StandardError => e
      # The bot token is in the request URL; an exception that quotes it must
      # not reach the log as-is.
      Rails.logger.error(
        "[RailsErrorDashboard] Failed to send Telegram notification: #{Services::TelegramDelivery.redact(e.message)}"
      )
      Rails.logger.error(e.backtrace&.first(5)&.join("\n")) if e.backtrace
    end

    private

    def redact_delivery(text)
      Services::TelegramDelivery.redact(text)
    end
  end
end
