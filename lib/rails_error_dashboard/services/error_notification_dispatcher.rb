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
        # OTel: emit a child span around the dispatch so operators can see
        # which channels fired for a given error and how long the enqueue
        # itself took. Actual delivery happens in the background jobs (Slack
        # HTTP, SMTP, etc.) — those would need their own instrumentation to
        # measure delivery latency.
        RailsErrorDashboard::Integrations::Tracer.in_span(
          "notification_dispatch",
          kind: :notifications,
          attributes: { "rails_error_dashboard.error_id" => error_log.id.to_i }
        ) do |span|
          config = RailsErrorDashboard.configuration
          fired = []

          if config.enable_slack_notifications && config.slack_webhook_url.present?
            SlackErrorNotificationJob.perform_later(error_log.id)
            fired << "slack"
          end

          if config.enable_email_notifications && config.notification_email_recipients.present?
            EmailErrorNotificationJob.perform_later(error_log.id)
            fired << "email"
          end

          if config.enable_discord_notifications && config.discord_webhook_url.present?
            DiscordErrorNotificationJob.perform_later(error_log.id)
            fired << "discord"
          end

          if config.enable_pagerduty_notifications && config.pagerduty_integration_key.present?
            PagerdutyErrorNotificationJob.perform_later(error_log.id)
            fired << "pagerduty"
          end

          if config.enable_webhook_notifications && config.webhook_urls.present?
            WebhookErrorNotificationJob.perform_later(error_log.id)
            fired << "webhook"
          end

          if span && !span.equal?(RailsErrorDashboard::Integrations::Tracer::NOOP_SPAN)
            span.set_attribute("channels", fired)
            span.set_attribute("channel_count", fired.size)
          end
        end
      end
    end
  end
end
