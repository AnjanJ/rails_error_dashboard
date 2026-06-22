# frozen_string_literal: true

module RailsErrorDashboard
  # Sends the SINGLE "error storm in progress" notification per storm episode.
  #
  # During a storm, per-error notifications are suppressed (500 Slack pings
  # help nobody) — this one message replaces them. The gate guarantees at
  # most one enqueue per episode; this job just delivers.
  class StormNotificationJob < ApplicationJob
    queue_as :default

    # @param started_at [String] ISO8601 episode start
    # @param state [String] breaker state at notification time ("shedding"/"open")
    def perform(started_at:, state: "shedding")
      config = RailsErrorDashboard.configuration
      message = build_message(started_at, state, config)

      if config.enable_slack_notifications && config.slack_webhook_url.present?
        post_json(config.slack_webhook_url, { text: message })
      end

      if config.enable_discord_notifications && config.discord_webhook_url.present?
        post_json(config.discord_webhook_url, { content: message })
      end

      if config.enable_webhook_notifications && config.webhook_urls.any?
        payload = {
          event: "error_storm_detected",
          started_at: started_at,
          state: state,
          application: app_name(config)
        }
        config.webhook_urls.each { |url| post_json(url, payload) }
      end
    rescue => e
      Rails.logger.error("[RailsErrorDashboard] StormNotificationJob failed: #{e.class} - #{e.message}")
    end

    private

    def build_message(started_at, state, config)
      mode = state == "open" ? "count-only mode (occurrences tallied, detail paused)" : "shedding mode (context sampling active)"
      dashboard = (config.dashboard_base_url || "").chomp("/")
      link = dashboard.present? ? " Dashboard: #{dashboard}/errors/storms" : ""

      ":warning: Error storm detected in #{app_name(config)} at #{started_at}. " \
        "Storm protection engaged — #{mode}. Per-error notifications are " \
        "suppressed until the storm subsides; exact counts are preserved.#{link}"
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
      Rails.logger.error("[RailsErrorDashboard] Storm notification post failed: #{e.message}")
    end
  end
end
