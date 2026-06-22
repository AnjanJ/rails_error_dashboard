# frozen_string_literal: true

# Test Phase 1 Configuration in Dummy App
RailsErrorDashboard.configure do |config|
  # Test custom severity rules
  config.custom_severity_rules = {
    "CustomPaymentError" => :critical,
    "CustomValidationError" => :low
  }

  # Test ignored exceptions
  config.ignored_exceptions = [
    "ActionController::RoutingError"
  ]

  # Test sampling rate (100% for tests)
  config.sampling_rate = 1.0

  # Test async configuration
  config.async_logging = false # Sync for tests
  config.async_adapter = :sidekiq

  # Storm protection OFF in tests (same rationale as async_logging = false):
  # specs that loop LogError.call must capture deterministically. Storm
  # behavior is exercised by specs that opt in explicitly.
  config.enable_storm_protection = false

  # Test backtrace limit
  config.max_backtrace_lines = 50
end

# Example: How users would configure notification callbacks
# (Not active in tests, just showing the API)
# RailsErrorDashboard.on_error_logged do |error_log|
#   puts "Error logged: #{error_log.error_type}"
# end
#
# RailsErrorDashboard.on_critical_error do |error_log|
#   puts "CRITICAL: #{error_log.error_type}"
# end
