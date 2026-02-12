# frozen_string_literal: true

# Pre-release test v2: ALL features enabled, async Sidekiq (inline), shared DB
RailsErrorDashboard.configure do |config|
  # Authentication
  config.dashboard_username = "gandalf"
  config.dashboard_password = "youshallnotpass"

  # Async logging via Sidekiq adapter
  # ActiveJob queue_adapter set to :inline in separate initializer
  config.async_logging = true
  config.async_adapter = :sidekiq

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

  # Rate limiting ON
  config.enable_rate_limiting = true
  config.rate_limit_per_minute = 100

  # Full backtrace + sampling
  config.max_backtrace_lines = 50
  config.sampling_rate = 1.0

  # Custom severity rules
  config.custom_severity_rules = { "CustomTestError" => :critical }

  # Webhook notifications (fake URL)
  config.enable_webhook_notifications = true
  config.webhook_urls = ["http://localhost:9999/fake-webhook"]

  # Middleware and subscriber
  config.enable_middleware = true
  config.enable_error_subscriber = true

  # Internal logging
  config.enable_internal_logging = true
  config.log_level = :warn
end
