# frozen_string_literal: true

module RailsErrorDashboard
  # Sends the ONE message that replaces the rest of a burst of new-error
  # notifications.
  #
  # A bad deploy can produce hundreds of DISTINCT new errors. Each is a first
  # occurrence, so the per-error cooldown never applies; without a cap every
  # one of them pages. NotificationThrottler.burst_decision lets the first
  # config.notification_burst_limit through per window and asks for this job
  # exactly once, when the limit is first exceeded.
  #
  # The message states the limit and the window rather than a count of what
  # was suppressed: it is sent when suppression STARTS, and a count at that
  # moment would always be one. Every error is still stored and counted; only
  # the notifications are held back.
  class NotificationBurstSummaryJob < ApplicationJob
    include Concerns::PlainChannelMessage

    queue_as :default

    # @param limit [Integer] config.notification_burst_limit when the cap engaged
    # @param window_seconds [Integer] config.notification_burst_window_seconds
    # @param locale [String, nil] resolved at enqueue time
    def perform(limit:, window_seconds:, locale: nil)
      config = RailsErrorDashboard.configuration

      deliver_plain_message(build_message(limit, window_seconds, config, job_locale(locale)), {
        event: "new_error_notifications_suppressed",
        limit: limit,
        window_seconds: window_seconds,
        application: app_name(config)
      })
    rescue => e
      Rails.logger.error("[RailsErrorDashboard] NotificationBurstSummaryJob failed: #{e.class} - #{e.message}")
    end

    private

    # Whole sentences joined, never fragments: see StormNotificationJob.
    # ":warning:" is Slack/Discord emoji shortcode, not text.
    def build_message(limit, window_seconds, config, locale)
      dashboard = (config.dashboard_base_url || "").chomp("/")
      link = if dashboard.present?
        " " + t("red.notifications.burst.dashboard", locale, url: "#{dashboard}/errors")
      else
        ""
      end

      ":warning: " \
        "#{t("red.notifications.burst.suppressed", locale, application: app_name(config), limit: limit, window: window_seconds)} " \
        "#{t("red.notifications.burst.still_recorded", locale)}#{link}"
    end
  end
end
