# frozen_string_literal: true

# RED's settings for the benchmark: the ones the install generator writes
# with its defaults (`rails generate rails_error_dashboard:install
# --no-interactive`), so the numbers are what a fresh install pays. Everything
# not set here keeps RED's own default.
RailsErrorDashboard.configure do |config|
  # Not the published defaults: outside development and test, RED refuses to
  # boot on those, exactly as it would in a real production app.
  config.dashboard_username = "benchmark"
  config.dashboard_password = "benchmark-only-not-a-secret"
  config.enable_middleware = true
  config.enable_error_subscriber = true
  config.retention_days = 90
  config.async_logging = true
  config.max_backtrace_lines = 100
  config.sampling_rate = 1.0
  config.use_separate_database = false
end
