# frozen_string_literal: true

# Pre-release test: Multi-app Beta — second app sharing a database
RailsErrorDashboard.configure do |config|
  # Authentication
  config.dashboard_username = "gandalf"
  config.dashboard_password = "youshallnotpass"

  # Different application name — isolation is the whole point
  config.application_name = "MultiAppBeta"

  # Synchronous logging
  config.async_logging = false

  # Analytics features ON
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

  # Custom severity rules
  config.custom_severity_rules = { "CustomTestError" => :critical }

  # Middleware and subscriber
  config.enable_middleware = true
  config.enable_error_subscriber = true

  # Internal logging
  config.enable_internal_logging = true
  config.log_level = :warn
end
