# frozen_string_literal: true

# Pre-release test: the initializer the upgrade test boots the PUBLISHED gem
# with, before it upgrades. The from-version can be any release from 0.1.38 on
# (release-1-0-rc1/REQ-13), and an option that version lacks would raise
# NoMethodError at boot, so each one is set only where the version has it.
RailsErrorDashboard.configure do |config|
  set = lambda do |option, value|
    setter = :"#{option}="
    config.public_send(setter, value) if config.respond_to?(setter)
  end

  # Authentication
  set.call(:dashboard_username, "chaos_test_admin")
  set.call(:dashboard_password, "chaos_test_secret_42")

  # Synchronous logging
  # Storm protection OFF for chaos tests: phases fire errors in tight
  # loops far hotter than real traffic and must capture deterministically.
  # Phase M exercises storm protection explicitly at runtime.
  set.call(:enable_storm_protection, false)
  set.call(:async_logging, false)

  # Basic analytics
  set.call(:enable_similar_errors, true)
  set.call(:enable_co_occurring_errors, true)
  set.call(:enable_error_cascades, true)
  set.call(:enable_error_correlation, true)
  set.call(:enable_platform_comparison, true)
  set.call(:enable_occurrence_patterns, true)

  # Middleware and subscriber
  set.call(:enable_middleware, true)
  set.call(:enable_error_subscriber, true)
end
