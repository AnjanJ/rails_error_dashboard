# frozen_string_literal: true

RailsErrorDashboard.configure do |config|
  # ============================================================================
  # AUTHENTICATION (Always Required)
  # ============================================================================

  # Dashboard authentication credentials
  # ⚠️ CHANGE THESE BEFORE PRODUCTION! ⚠️
  config.dashboard_username = ENV.fetch("ERROR_DASHBOARD_USER", "gandalf")
  config.dashboard_password = ENV.fetch("ERROR_DASHBOARD_PASSWORD", "youshallnotpass")

  # Require authentication for dashboard access
  config.require_authentication = true

  # Require authentication even in development mode
  config.require_authentication_in_development = false

  # ============================================================================
  # CORE FEATURES (Always Enabled)
  # ============================================================================

  # Error capture via middleware and Rails.error subscriber
  config.enable_middleware = true
  config.enable_error_subscriber = true

  # User model for error associations
  config.user_model = "User"

  # Error retention policy (days to keep errors before auto-deletion)
  config.retention_days = 90

  # ============================================================================
  # NOTIFICATION SETTINGS
  # ============================================================================
  # Configure which notification channels you want to use.
  # You can enable/disable any of these at any time by changing true/false.

<% if @enable_slack -%>
  # Slack Notifications - ENABLED
  config.enable_slack_notifications = true
  config.slack_webhook_url = ENV["SLACK_WEBHOOK_URL"]
  # To disable: Set config.enable_slack_notifications = false

<% else -%>
  # Slack Notifications - DISABLED
  # To enable: Set config.enable_slack_notifications = true and configure webhook URL
  config.enable_slack_notifications = false
  # config.slack_webhook_url = ENV["SLACK_WEBHOOK_URL"]

<% end -%>
<% if @enable_email -%>
  # Email Notifications - ENABLED
  config.enable_email_notifications = true
  config.notification_email_recipients = ENV.fetch("ERROR_NOTIFICATION_EMAILS", "").split(",").map(&:strip)
  config.notification_email_from = ENV.fetch("ERROR_NOTIFICATION_FROM", "errors@example.com")
  # To disable: Set config.enable_email_notifications = false

<% else -%>
  # Email Notifications - DISABLED
  # To enable: Set config.enable_email_notifications = true and configure recipients
  config.enable_email_notifications = false
  # config.notification_email_recipients = ENV.fetch("ERROR_NOTIFICATION_EMAILS", "").split(",").map(&:strip)
  # config.notification_email_from = ENV.fetch("ERROR_NOTIFICATION_FROM", "errors@example.com")

<% end -%>
<% if @enable_discord -%>
  # Discord Notifications - ENABLED
  config.enable_discord_notifications = true
  config.discord_webhook_url = ENV["DISCORD_WEBHOOK_URL"]
  # To disable: Set config.enable_discord_notifications = false

<% else -%>
  # Discord Notifications - DISABLED
  # To enable: Set config.enable_discord_notifications = true and configure webhook URL
  config.enable_discord_notifications = false
  # config.discord_webhook_url = ENV["DISCORD_WEBHOOK_URL"]

<% end -%>
<% if @enable_pagerduty -%>
  # PagerDuty Integration - ENABLED (critical errors only)
  config.enable_pagerduty_notifications = true
  config.pagerduty_integration_key = ENV["PAGERDUTY_INTEGRATION_KEY"]
  # To disable: Set config.enable_pagerduty_notifications = false

<% else -%>
  # PagerDuty Integration - DISABLED
  # To enable: Set config.enable_pagerduty_notifications = true and configure integration key
  config.enable_pagerduty_notifications = false
  # config.pagerduty_integration_key = ENV["PAGERDUTY_INTEGRATION_KEY"]

<% end -%>
<% if @enable_webhooks -%>
  # Generic Webhook Notifications - ENABLED
  config.enable_webhook_notifications = true
  config.webhook_urls = ENV.fetch("WEBHOOK_URLS", "").split(",").map(&:strip).reject(&:empty?)
  # To disable: Set config.enable_webhook_notifications = false

<% else -%>
  # Generic Webhook Notifications - DISABLED
  # To enable: Set config.enable_webhook_notifications = true and configure webhook URLs
  config.enable_webhook_notifications = false
  # config.webhook_urls = ENV.fetch("WEBHOOK_URLS", "").split(",").map(&:strip).reject(&:empty?)

<% end -%>
  # Dashboard base URL (used in notification links)
  config.dashboard_base_url = ENV["DASHBOARD_BASE_URL"]

  # ============================================================================
  # PERFORMANCE & SCALABILITY
  # ============================================================================

<% if @enable_async_logging -%>
  # Async Error Logging - ENABLED
  # Errors will be logged in background jobs for better performance
  config.async_logging = true
  config.async_adapter = :sidekiq  # Options: :sidekiq, :solid_queue, :async
  # To disable: Set config.async_logging = false

<% else -%>
  # Async Error Logging - DISABLED
  # Errors are logged synchronously (blocking)
  # To enable: Set config.async_logging = true and configure adapter
  config.async_logging = false
  # config.async_adapter = :sidekiq  # Options: :sidekiq, :solid_queue, :async

<% end -%>
  # Backtrace size limiting (reduces storage by ~80%)
  config.max_backtrace_lines = 50

<% if @enable_error_sampling -%>
  # Error Sampling - ENABLED
  # Reduce volume by logging only a percentage of non-critical errors
  # Critical errors are ALWAYS logged regardless of sampling rate
  config.sampling_rate = 0.1  # 10% - Adjust as needed (0.0 to 1.0)
  # To disable: Set config.sampling_rate = 1.0 (100%)

<% else -%>
  # Error Sampling - DISABLED
  # All errors are logged (100% sampling rate)
  # To enable: Set config.sampling_rate < 1.0 (e.g., 0.1 for 10%)
  config.sampling_rate = 1.0

<% end -%>
  # Ignored exceptions (skip logging these)
  # config.ignored_exceptions = [
  #   "ActionController::RoutingError",
  #   "ActionController::InvalidAuthenticityToken",
  #   /^ActiveRecord::RecordNotFound/
  # ]

  # ============================================================================
  # DATABASE CONFIGURATION
  # ============================================================================

<% if @enable_separate_database -%>
  # Separate Error Database - ENABLED
  # Errors will be stored in a dedicated database
  # See docs/guides/DATABASE_OPTIONS.md for setup instructions
  config.use_separate_database = true
  # To disable: Set config.use_separate_database = false

<% else -%>
  # Separate Error Database - DISABLED
  # Errors are stored in your main application database
  # To enable: Set config.use_separate_database = true and configure database.yml
  config.use_separate_database = false

<% end -%>
  # ============================================================================
  # ADVANCED ANALYTICS
  # ============================================================================

<% if @enable_baseline_alerts -%>
  # Baseline Anomaly Alerts - ENABLED
  # Automatically detect when error rates exceed normal patterns
  config.enable_baseline_alerts = true
  config.baseline_alert_threshold_std_devs = 2.0  # Alert when > 2 std devs above baseline
  config.baseline_alert_severities = [ :critical, :high ]
  config.baseline_alert_cooldown_minutes = 120  # 2 hours between alerts
  # To disable: Set config.enable_baseline_alerts = false

<% else -%>
  # Baseline Anomaly Alerts - DISABLED
  # To enable: Set config.enable_baseline_alerts = true
  config.enable_baseline_alerts = false
  # config.baseline_alert_threshold_std_devs = 2.0
  # config.baseline_alert_severities = [ :critical, :high ]
  # config.baseline_alert_cooldown_minutes = 120

<% end -%>
<% if @enable_similar_errors -%>
  # Fuzzy Error Matching - ENABLED
  # Find similar errors even with different error_hashes
  config.enable_similar_errors = true
  # To disable: Set config.enable_similar_errors = false

<% else -%>
  # Fuzzy Error Matching - DISABLED
  # To enable: Set config.enable_similar_errors = true
  config.enable_similar_errors = false

<% end -%>
<% if @enable_co_occurring_errors -%>
  # Co-occurring Errors - ENABLED
  # Detect errors that happen together in time
  config.enable_co_occurring_errors = true
  # To disable: Set config.enable_co_occurring_errors = false

<% else -%>
  # Co-occurring Errors - DISABLED
  # To enable: Set config.enable_co_occurring_errors = true
  config.enable_co_occurring_errors = false

<% end -%>
<% if @enable_error_cascades -%>
  # Error Cascade Detection - ENABLED
  # Identify error chains (A causes B causes C)
  config.enable_error_cascades = true
  # To disable: Set config.enable_error_cascades = false

<% else -%>
  # Error Cascade Detection - DISABLED
  # To enable: Set config.enable_error_cascades = true
  config.enable_error_cascades = false

<% end -%>
<% if @enable_error_correlation -%>
  # Error Correlation Analysis - ENABLED
  # Correlate errors with versions, users, and time
  config.enable_error_correlation = true
  # To disable: Set config.enable_error_correlation = false

<% else -%>
  # Error Correlation Analysis - DISABLED
  # To enable: Set config.enable_error_correlation = true
  config.enable_error_correlation = false

<% end -%>
<% if @enable_platform_comparison -%>
  # Platform Comparison - ENABLED
  # Compare iOS vs Android vs Web health metrics
  config.enable_platform_comparison = true
  # To disable: Set config.enable_platform_comparison = false

<% else -%>
  # Platform Comparison - DISABLED
  # To enable: Set config.enable_platform_comparison = true
  config.enable_platform_comparison = false

<% end -%>
<% if @enable_occurrence_patterns -%>
  # Occurrence Pattern Detection - ENABLED
  # Detect cyclical patterns and error bursts
  config.enable_occurrence_patterns = true
  # To disable: Set config.enable_occurrence_patterns = false

<% else -%>
  # Occurrence Pattern Detection - DISABLED
  # To enable: Set config.enable_occurrence_patterns = true
  config.enable_occurrence_patterns = false

<% end -%>
  # ============================================================================
  # INTERNAL LOGGING (Silent by Default)
  # ============================================================================
  # Rails Error Dashboard logging is SILENT by default to keep your logs clean.
  # Enable only for debugging gem issues or troubleshooting setup.

  # Enable internal logging (default: false - silent)
  config.enable_internal_logging = false

  # Log level (default: :silent)
  # Options: :debug, :info, :warn, :error, :silent
  config.log_level = :silent

  # Example: Enable verbose logging for debugging
  # config.enable_internal_logging = true
  # config.log_level = :debug

  # Example: Log only errors (troubleshooting)
  # config.enable_internal_logging = true
  # config.log_level = :error

  # ============================================================================
  # ADDITIONAL CONFIGURATION
  # ============================================================================

  # Custom severity rules (override automatic severity classification)
  # config.custom_severity_rules = {
  #   "PaymentError" => :critical,
  #   "ValidationError" => :low
  # }

  # Enhanced metrics (optional)
  config.app_version = ENV["APP_VERSION"]
  config.git_sha = ENV["GIT_SHA"]
  # config.total_users_for_impact = 10000  # For user impact % calculation

  # Git repository URL for clickable commit links
  # Examples:
  #   GitHub: "https://github.com/username/repo"
  #   GitLab: "https://gitlab.com/username/repo"
  #   Bitbucket: "https://bitbucket.org/username/repo"
  # config.git_repository_url = ENV["GIT_REPOSITORY_URL"]
end
