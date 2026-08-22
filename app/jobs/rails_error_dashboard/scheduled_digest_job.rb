# frozen_string_literal: true

module RailsErrorDashboard
  # Background job to send scheduled error digest emails.
  # Schedule this job via your preferred scheduler (SolidQueue, Sidekiq, cron).
  #
  # @example Schedule daily digest
  #   RailsErrorDashboard::ScheduledDigestJob.perform_later(period: "daily")
  #
  # @example Schedule via rake
  #   rails error_dashboard:send_digest PERIOD=daily
  class ScheduledDigestJob < ApplicationJob
    queue_as :default

    # @param locale [String, nil] resolved at enqueue time. nil for jobs
    #   enqueued by a pre-Phase-4 version still draining from the queue.
    def perform(period: "daily", application_id: nil, locale: nil)
      return unless RailsErrorDashboard.configuration.enable_scheduled_digests

      recipients = effective_recipients
      return if recipients.blank?

      resolved_locale = job_locale(locale)

      digest = Services::DigestBuilder.call(
        period: period.to_sym,
        application_id: application_id,
        locale: resolved_locale
      )

      DigestMailer.digest_summary(digest, recipients, locale: resolved_locale).deliver_now
    rescue => e
      Rails.logger.error("[RailsErrorDashboard] ScheduledDigestJob failed: #{e.class}: #{e.message}")
    end

    private

    def effective_recipients
      config = RailsErrorDashboard.configuration
      recipients = config.digest_recipients
      recipients = config.notification_email_recipients if recipients.blank?
      recipients.presence
    end
  end
end
