# frozen_string_literal: true

# Pre-release test: Minimal initializer compatible with v0.1.38
# Only uses config options that exist in the published gem version.
RailsErrorDashboard.configure do |config|
  # Authentication
  config.dashboard_username = "chaos_test_admin"
  config.dashboard_password = "chaos_test_secret_42"

  # Synchronous logging
  # Storm protection OFF for chaos tests: phases fire errors in tight
  # loops far hotter than real traffic and must capture deterministically.
  # Phase M exercises storm protection explicitly at runtime.
  config.enable_storm_protection = false
  config.async_logging = false

  # Basic analytics
  config.enable_similar_errors = true
  config.enable_co_occurring_errors = true
  config.enable_error_cascades = true
  config.enable_error_correlation = true
  config.enable_platform_comparison = true
  config.enable_occurrence_patterns = true

  # Middleware and subscriber
  config.enable_middleware = true
  config.enable_error_subscriber = true
end
