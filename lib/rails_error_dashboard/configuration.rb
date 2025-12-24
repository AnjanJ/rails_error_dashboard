# frozen_string_literal: true

module RailsErrorDashboard
  class Configuration
    # Dashboard authentication
    attr_accessor :dashboard_username
    attr_accessor :dashboard_password
    attr_accessor :require_authentication
    attr_accessor :require_authentication_in_development

    # User model (for associations)
    attr_accessor :user_model

    # Notifications
    attr_accessor :slack_webhook_url
    attr_accessor :notification_email_recipients
    attr_accessor :notification_email_from
    attr_accessor :dashboard_base_url
    attr_accessor :enable_slack_notifications
    attr_accessor :enable_email_notifications

    # Discord notifications
    attr_accessor :discord_webhook_url
    attr_accessor :enable_discord_notifications

    # PagerDuty notifications (critical errors only)
    attr_accessor :pagerduty_integration_key
    attr_accessor :enable_pagerduty_notifications

    # Generic webhook notifications
    attr_accessor :webhook_urls
    attr_accessor :enable_webhook_notifications

    # Separate database configuration
    attr_accessor :use_separate_database

    # Retention policy (days to keep errors)
    attr_accessor :retention_days

    # Enable/disable error catching middleware
    attr_accessor :enable_middleware

    # Enable/disable Rails.error subscriber
    attr_accessor :enable_error_subscriber

    def initialize
      # Default values
      @dashboard_username = ENV.fetch("ERROR_DASHBOARD_USER", "admin")
      @dashboard_password = ENV.fetch("ERROR_DASHBOARD_PASSWORD", "password")
      @require_authentication = true
      @require_authentication_in_development = false

      @user_model = "User"

      # Notification settings
      @slack_webhook_url = ENV["SLACK_WEBHOOK_URL"]
      @notification_email_recipients = ENV.fetch("ERROR_NOTIFICATION_EMAILS", "").split(",").map(&:strip)
      @notification_email_from = ENV.fetch("ERROR_NOTIFICATION_FROM", "errors@example.com")
      @dashboard_base_url = ENV["DASHBOARD_BASE_URL"]
      @enable_slack_notifications = true
      @enable_email_notifications = true

      # Discord notification settings
      @discord_webhook_url = ENV["DISCORD_WEBHOOK_URL"]
      @enable_discord_notifications = false

      # PagerDuty notification settings (critical errors only)
      @pagerduty_integration_key = ENV["PAGERDUTY_INTEGRATION_KEY"]
      @enable_pagerduty_notifications = false

      # Generic webhook settings (array of URLs)
      @webhook_urls = ENV.fetch("WEBHOOK_URLS", "").split(",").map(&:strip).reject(&:empty?)
      @enable_webhook_notifications = false

      @use_separate_database = ENV.fetch("USE_SEPARATE_ERROR_DB", "false") == "true"

      @retention_days = 90

      @enable_middleware = true
      @enable_error_subscriber = true
    end
  end
end
