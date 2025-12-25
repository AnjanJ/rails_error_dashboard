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

    # Advanced configuration options
    # Custom severity classification rules (hash of error_type => severity)
    attr_accessor :custom_severity_rules

    # Exceptions to ignore (array of strings, regexes, or classes)
    attr_accessor :ignored_exceptions

    # Sampling rate for non-critical errors (0.0 to 1.0, default 1.0 = 100%)
    attr_accessor :sampling_rate

    # Async logging configuration
    attr_accessor :async_logging
    attr_accessor :async_adapter # :sidekiq, :solid_queue, or :async

    # Backtrace configuration
    attr_accessor :max_backtrace_lines

    # Enhanced metrics
    attr_accessor :app_version
    attr_accessor :git_sha
    attr_accessor :total_users_for_impact # For user impact % calculation

    # Advanced error analysis features
    attr_accessor :enable_similar_errors          # Fuzzy error matching
    attr_accessor :enable_co_occurring_errors     # Detect errors happening together
    attr_accessor :enable_error_cascades          # Parent→child error relationships
    attr_accessor :enable_error_correlation       # Version/user/time correlation
    attr_accessor :enable_platform_comparison     # iOS vs Android analytics
    attr_accessor :enable_occurrence_patterns     # Cyclical/burst pattern detection

    # Baseline alert configuration
    attr_accessor :enable_baseline_alerts
    attr_accessor :baseline_alert_threshold_std_devs # Number of std devs to trigger alert (default: 2.0)
    attr_accessor :baseline_alert_severities # Array of severities to alert on (default: [:critical, :high])
    attr_accessor :baseline_alert_cooldown_minutes # Minutes between alerts for same error type (default: 120)

    # Notification callbacks (managed via helper methods, not set directly)
    attr_reader :notification_callbacks

    def initialize
      # Default values
      @dashboard_username = ENV.fetch("ERROR_DASHBOARD_USER", "gandalf")
      @dashboard_password = ENV.fetch("ERROR_DASHBOARD_PASSWORD", "youshallnotpass")
      @require_authentication = true
      @require_authentication_in_development = false

      @user_model = "User"

      # Notification settings (disabled by default - enable during installation or in initializer)
      @slack_webhook_url = ENV["SLACK_WEBHOOK_URL"]
      @notification_email_recipients = ENV.fetch("ERROR_NOTIFICATION_EMAILS", "").split(",").map(&:strip)
      @notification_email_from = ENV.fetch("ERROR_NOTIFICATION_FROM", "errors@example.com")
      @dashboard_base_url = ENV["DASHBOARD_BASE_URL"]
      @enable_slack_notifications = false
      @enable_email_notifications = false

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

      # Advanced configuration defaults
      @custom_severity_rules = {}
      @ignored_exceptions = []
      @sampling_rate = 1.0 # 100% by default
      @async_logging = false
      @async_adapter = :sidekiq # Battle-tested default
      @max_backtrace_lines = 50

      # Enhanced metrics defaults
      @app_version = ENV["APP_VERSION"]
      @git_sha = ENV["GIT_SHA"]
      @total_users_for_impact = nil # Auto-detect if not set

      # Advanced error analysis features (all OFF by default - opt-in)
      @enable_similar_errors = false        # Fuzzy error matching
      @enable_co_occurring_errors = false   # Co-occurring error detection
      @enable_error_cascades = false        # Error cascade detection
      @enable_error_correlation = false     # Version/user/time correlation
      @enable_platform_comparison = false   # Platform health comparison
      @enable_occurrence_patterns = false   # Pattern detection

      # Baseline alert defaults
      @enable_baseline_alerts = false  # OFF by default (opt-in)
      @baseline_alert_threshold_std_devs = ENV.fetch("BASELINE_ALERT_THRESHOLD", "2.0").to_f
      @baseline_alert_severities = [ :critical, :high ] # Alert on critical and high severity anomalies
      @baseline_alert_cooldown_minutes = ENV.fetch("BASELINE_ALERT_COOLDOWN", "120").to_i

      @notification_callbacks = {
        error_logged: [],
        critical_error: [],
        error_resolved: []
      }
    end

    # Reset configuration to defaults
    def reset!
      initialize
    end
  end
end
