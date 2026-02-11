# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Service: Route error notifications to configured channels
    #
    # Checks configuration and enqueues notification jobs for all enabled channels.
    # Each channel has its own background job for delivery.
    #
    # @example
    #   ErrorNotificationDispatcher.call(error_log)
    class ErrorNotificationDispatcher
      # @param error_log [ErrorLog] The error to notify about
      def self.call(error_log)
        config = RailsErrorDashboard.configuration

        if config.enable_slack_notifications && config.slack_webhook_url.present?
          SlackErrorNotificationJob.perform_later(error_log.id)
        end

        if config.enable_email_notifications && config.notification_email_recipients.present?
          EmailErrorNotificationJob.perform_later(error_log.id)
        end

        if config.enable_discord_notifications && config.discord_webhook_url.present?
          DiscordErrorNotificationJob.perform_later(error_log.id)
        end

        if config.enable_pagerduty_notifications && config.pagerduty_integration_key.present?
          PagerdutyErrorNotificationJob.perform_later(error_log.id)
        end

        if config.enable_webhook_notifications && config.webhook_urls.present?
          WebhookErrorNotificationJob.perform_later(error_log.id)
        end
      end
    end
  end
end
