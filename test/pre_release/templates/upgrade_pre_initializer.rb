# frozen_string_literal: true

# Pre-release test: Minimal initializer compatible with v0.1.38
# Only uses config options that exist in the published gem version.
RailsErrorDashboard.configure do |config|
  # Authentication
  config.dashboard_username = "gandalf"
  config.dashboard_password = "youshallnotpass"

  # Synchronous logging
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
