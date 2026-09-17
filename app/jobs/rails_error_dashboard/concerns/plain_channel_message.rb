# frozen_string_literal: true

module RailsErrorDashboard
  module Concerns
    # Delivery of a plain, one-sentence message that is ABOUT the dashboard's
    # own behaviour rather than about one error: "a storm is in progress",
    # "further new-error notifications are suppressed". The per-error jobs
    # build rich payloads from an ErrorLog; these messages have no row.
    #
    # Shared by StormNotificationJob and NotificationBurstSummaryJob.
    module PlainChannelMessage
      private

      # Slack takes {text:}, Discord {content:}, custom webhooks a
      # machine-readable event. Email and PagerDuty are not used: neither has
      # a sensible shape for a message that is not an incident.
      def deliver_plain_message(message, webhook_payload)
        config = RailsErrorDashboard.configuration
        delivered = false

        if config.enable_slack_notifications && config.slack_webhook_url.present?
          post_json(config.slack_webhook_url, { text: message })
          delivered = true
        end

        if config.enable_discord_notifications && config.discord_webhook_url.present?
          post_json(config.discord_webhook_url, { content: message })
          delivered = true
        end

        if config.enable_webhook_notifications && config.webhook_urls.present?
          config.webhook_urls.each { |url| post_json(url, webhook_payload) }
          delivered = true
        end

        # An email-only or PagerDuty-only deployment has no channel for this.
        # Say so where an operator can find it rather than dropping it silently.
        unless delivered
          Rails.logger.warn("[RailsErrorDashboard] #{self.class.name.demodulize}: no Slack, Discord or webhook channel is enabled; message not sent: #{message}")
        end
      end

      def t(key, locale, **options)
        RailsErrorDashboard::I18nStore.translate(key, locale: locale, **options)
      end

      def app_name(config)
        config.application_name || ENV["APPLICATION_NAME"] ||
          (defined?(Rails) && Rails.application.class.module_parent_name) || "Rails Application"
      end

      def post_json(url, payload)
        if defined?(HTTParty)
          HTTParty.post(url, body: payload.to_json,
            headers: { "Content-Type" => "application/json" }, timeout: 10)
        else
          uri = URI(url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = 5
          http.read_timeout = 10
          request = Net::HTTP::Post.new(uri.path, { "Content-Type" => "application/json" })
          request.body = payload.to_json
          http.request(request)
        end
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] #{self.class.name.demodulize} post failed: #{e.message}")
      end
    end
  end
end
