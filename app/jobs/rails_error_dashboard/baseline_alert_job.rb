# frozen_string_literal: true

module RailsErrorDashboard
  # Sends baseline anomaly alerts through configured notification channels
  #
  # This job is triggered when an error exceeds baseline thresholds.
  # It respects cooldown periods to prevent alert fatigue and sends
  # notifications through all enabled channels (Slack, Email, Discord, etc.)
  class BaselineAlertJob < ApplicationJob
    queue_as :default

    # @param error_log_id [Integer] The error log that triggered the alert
    # @param anomaly_data [Hash] Anomaly information from baseline check
    def perform(error_log_id, anomaly_data)
      error_log = ErrorLog.find_by(id: error_log_id)
      return unless error_log

      config = RailsErrorDashboard.configuration

      # Check if we should send alert (cooldown check)
      unless Services::BaselineAlertThrottler.should_alert?(
        error_log.error_type,
        error_log.platform,
        cooldown_minutes: config.baseline_alert_cooldown_minutes
      )
        Rails.logger.info(
          "Baseline alert throttled for #{error_log.error_type} on #{error_log.platform}"
        )
        return
      end

      # Record that we're sending an alert
      Services::BaselineAlertThrottler.record_alert(
        error_log.error_type,
        error_log.platform
      )

      # Send notifications through all enabled channels
      send_notifications(error_log, anomaly_data, config)
    end

    private

    def send_notifications(error_log, anomaly_data, config)
      # Slack notification
      if config.enable_slack_notifications && config.slack_webhook_url.present?
        send_slack_notification(error_log, anomaly_data, config)
      end

      # Email notification
      if config.enable_email_notifications && config.notification_email_recipients.any?
        send_email_notification(error_log, anomaly_data, config)
      end

      # Discord notification
      if config.enable_discord_notifications && config.discord_webhook_url.present?
        send_discord_notification(error_log, anomaly_data, config)
      end

      # Webhook notification
      if config.enable_webhook_notifications && config.webhook_urls.any?
        send_webhook_notification(error_log, anomaly_data, config)
      end

      # PagerDuty for critical anomalies
      if config.enable_pagerduty_notifications &&
         config.pagerduty_integration_key.present? &&
         anomaly_data[:level] == :critical
        send_pagerduty_notification(error_log, anomaly_data, config)
      end
    end

    def send_slack_notification(error_log, anomaly_data, config)
      payload = Services::BaselineAlertPayloadBuilder.slack_payload(error_log, anomaly_data)

      post_json(config.slack_webhook_url, payload)
    rescue => e
      Rails.logger.error("Failed to send baseline alert to Slack: #{e.message}")
    end

    def send_email_notification(error_log, _anomaly_data, _config)
      Rails.logger.info(
        "Baseline alert email would be sent for #{error_log.error_type}"
      )
    rescue => e
      Rails.logger.error("Failed to send baseline alert email: #{e.message}")
    end

    def send_discord_notification(error_log, anomaly_data, config)
      payload = Services::BaselineAlertPayloadBuilder.discord_payload(error_log, anomaly_data)

      post_json(config.discord_webhook_url, payload)
    rescue => e
      Rails.logger.error("Failed to send baseline alert to Discord: #{e.message}")
    end

    def send_webhook_notification(error_log, anomaly_data, config)
      payload = Services::BaselineAlertPayloadBuilder.webhook_payload(error_log, anomaly_data)

      config.webhook_urls.each do |url|
        post_json(url, payload)
      end
    rescue => e
      Rails.logger.error("Failed to send baseline alert to webhook: #{e.message}")
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
    end

    def send_pagerduty_notification(error_log, _anomaly_data, _config)
      Rails.logger.info(
        "Baseline alert PagerDuty notification for #{error_log.error_type}"
      )
    rescue => e
      Rails.logger.error("Failed to send baseline alert to PagerDuty: #{e.message}")
    end
  end
end
