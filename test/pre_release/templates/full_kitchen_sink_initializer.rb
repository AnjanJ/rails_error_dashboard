# frozen_string_literal: true

# Pre-release test: EVERY config option set to non-default simultaneously.
# Purpose: catch interaction bugs when ALL options are active at once.
RailsErrorDashboard.configure do |config|
  # Authentication
  config.dashboard_username = "gandalf"
  config.dashboard_password = "youshallnotpass"

  # Synchronous logging (kitchen sink tests config interactions, not async)
  config.async_logging = false

  # Application identity
  config.application_name = "KitchenSinkApp"
  config.app_version = "2.0.0-rc1"
  config.git_sha = "abc123def456"
  config.git_repository_url = "https://github.com/test/kitchen-sink"
  config.total_users_for_impact = 5000

  # Ignored exceptions — these should be silently skipped
  config.ignored_exceptions = [ "SignalException", /IgnoreMe/ ]

  # Custom fingerprint — group by error class + controller only
  config.custom_fingerprint = ->(exception, context) {
    ctrl = context[:controller_name] || "unknown"
    "kitchen-#{exception.class.name}-#{ctrl}"
  }

  # Sensitive data filtering with extra patterns
  config.filter_sensitive_data = true
  config.sensitive_data_patterns = [ /secret_sauce/i, /my_token/i ]

  # Custom severity rules
  config.custom_severity_rules = {
    "CustomTestError" => :critical,
    "ArgumentError" => :medium
  }

  # Sampling — keep all errors
  config.sampling_rate = 1.0

  # Backtrace truncation — short (test that truncation works)
  config.max_backtrace_lines = 10

  # Retention policy
  config.retention_days = 90

  # Rate limiting ON
  config.enable_rate_limiting = true
  config.rate_limit_per_minute = 50

  # All analytics features ON
  config.enable_similar_errors = true
  config.enable_co_occurring_errors = true
  config.enable_error_cascades = true
  config.enable_error_correlation = true
  config.enable_platform_comparison = true
  config.enable_occurrence_patterns = true

  # Baseline alerts ON
  config.enable_baseline_alerts = true
  config.baseline_alert_threshold_std_devs = 2.0
  config.baseline_alert_cooldown_minutes = 120

  # Source code integration ON
  config.enable_source_code_integration = true
  config.source_code_context_lines = 7
  config.enable_git_blame = true

  # Notification throttling — non-default values
  config.notification_minimum_severity = :medium
  config.notification_cooldown_minutes = 10
  config.notification_threshold_alerts = [ 5, 25, 100 ]

  # Webhook notifications (fake URL — tests path without crashing)
  config.enable_webhook_notifications = true
  config.webhook_urls = [ "http://localhost:9999/fake-webhook" ]

  # Middleware and subscriber — the core capture mechanisms
  config.enable_middleware = true
  config.enable_error_subscriber = true

  # Internal logging
  config.enable_internal_logging = true
  config.log_level = :warn
end

# Notification callbacks (must be outside configure block)
RailsErrorDashboard.on_error_logged do |error_log|
  # Intentionally empty — just verify the callback path doesn't crash
end

RailsErrorDashboard.on_critical_error do |error_log|
  # Intentionally empty — just verify the callback path doesn't crash
end
