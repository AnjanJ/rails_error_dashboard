# frozen_string_literal: true

# ============================================================================
# CHAOS TEST PHASE K: Kitchen Sink — Every Config Option Enabled
# Verifies all configuration options work together without conflicts.
#
# Run with: bin/rails runner test/pre_release/chaos/phase_k_kitchen_sink.rb
# ============================================================================

harness_path = File.expand_path("../lib/test_harness.rb", __dir__)
require harness_path

PreReleaseTestHarness.reset!
PreReleaseTestHarness.header("CHAOS TEST PHASE K: KITCHEN SINK — ALL CONFIG OPTIONS")

config = RailsErrorDashboard.configuration

# ---------------------------------------------------------------------------
# K1: Configuration validation with all options set
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("K1: Config validation with all options active")

assert_no_crash("K1: validate! passes with all options") { config.validate! }
assert "K1: application_name set", config.application_name == "KitchenSinkApp"
assert "K1: app_version set", config.app_version == "2.0.0-rc1"
assert "K1: git_sha set", config.git_sha == "abc123def456"
assert "K1: git_repository_url set", config.git_repository_url == "https://github.com/test/kitchen-sink"
assert "K1: total_users_for_impact set", config.total_users_for_impact == 5000
assert "K1: retention_days set", config.retention_days == 90
assert "K1: sampling_rate is 1.0", config.sampling_rate == 1.0
assert "K1: max_backtrace_lines is 10", config.max_backtrace_lines == 10
assert "K1: custom_fingerprint is callable", config.custom_fingerprint.respond_to?(:call)
assert "K1: notification_minimum_severity is medium", config.notification_minimum_severity == :medium
assert "K1: notification_cooldown_minutes is 10", config.notification_cooldown_minutes == 10
assert "K1: notification_threshold_alerts custom", config.notification_threshold_alerts == [ 5, 25, 100 ]
puts ""

# ---------------------------------------------------------------------------
# K2: Ignored exceptions are skipped
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("K2: Ignored exceptions are silently skipped")

count_before = RailsErrorDashboard::ErrorLog.count

# SignalException is in the ignored list
begin
  raise SignalException, "TERM"
rescue Exception => e
  Rails.error.report(e, handled: true, severity: :error, context: { platform: "Web" })
end

count_after = RailsErrorDashboard::ErrorLog.count
assert "K2: SignalException was ignored", count_after == count_before,
  "count changed from #{count_before} to #{count_after}"

# Test regex pattern: /IgnoreMe/
ignore_class = Class.new(StandardError)
Object.const_set(:IgnoreMeError, ignore_class) unless defined?(IgnoreMeError)

count_before = RailsErrorDashboard::ErrorLog.count
begin
  raise IgnoreMeError, "should be ignored by regex"
rescue => e
  Rails.error.report(e, handled: false, severity: :error, context: { platform: "Web" })
end

count_after = RailsErrorDashboard::ErrorLog.count
assert "K2: IgnoreMeError skipped by regex", count_after == count_before,
  "count changed from #{count_before} to #{count_after}"
puts ""

# ---------------------------------------------------------------------------
# K3: Custom fingerprint groups errors
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("K3: Custom fingerprint lambda works")

fp_error1 = begin
  raise RuntimeError, "fingerprint alpha #{SecureRandom.hex(4)}"
rescue => e
  log_error_and_find(e, { controller_name: "fp_kitchen", platform: "Web" })
end

fp_error2 = begin
  raise RuntimeError, "fingerprint beta #{SecureRandom.hex(4)}"
rescue => e
  log_error_and_find(e, { controller_name: "fp_kitchen", platform: "Web" })
end

assert "K3: both persisted", fp_error1.persisted? && fp_error2.persisted?
assert "K3: same hash (custom fingerprint)", fp_error1.error_hash == fp_error2.error_hash,
  "got #{fp_error1.error_hash} vs #{fp_error2.error_hash}"
assert "K3: same record (deduped by fingerprint)", fp_error1.id == fp_error2.id
puts ""

# ---------------------------------------------------------------------------
# K4: Sensitive data filtering with custom patterns
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("K4: Sensitive data filtering with custom patterns")

sensitive_error = begin
  raise RuntimeError, "sensitive test #{SecureRandom.hex(4)}"
rescue => e
  log_error_and_find(e, {
    controller_name: "sensitive_kitchen",
    platform: "Web",
    params: {
      username: "bilbo",
      password: "ring_bearer_123",
      secret_sauce: "my_special_recipe",
      my_token: "tok_abc123",
      safe_field: "visible"
    }
  })
end

assert "K4: error persisted", sensitive_error.persisted?
if sensitive_error.request_params.present?
  params_str = sensitive_error.request_params
  assert "K4: password filtered", !params_str.include?("ring_bearer_123"),
    "raw password leaked!"
  assert "K4: secret_sauce filtered", !params_str.include?("my_special_recipe"),
    "secret_sauce leaked!"
  assert "K4: my_token filtered", !params_str.include?("tok_abc123"),
    "my_token leaked!"
  assert "K4: safe field preserved", params_str.include?("visible")
end
puts ""

# ---------------------------------------------------------------------------
# K5: Custom severity rules work alongside defaults
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("K5: Custom severity rules")

# ArgumentError is overridden to :medium in kitchen sink config
arg_error = begin
  raise ArgumentError, "severity override test #{SecureRandom.hex(4)}"
rescue => e
  log_error_and_find(e, { controller_name: "severity_kitchen", platform: "Web" })
end

assert "K5: ArgumentError persisted", arg_error.persisted?
assert "K5: ArgumentError severity is medium (custom rule)", arg_error.severity.to_sym == :medium,
  "got #{arg_error.severity}"
puts ""

# ---------------------------------------------------------------------------
# K6: app_version and git_sha stored on errors
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("K6: app_version and git_sha in error records")

versioned_error = begin
  raise RuntimeError, "version capture test #{SecureRandom.hex(4)}"
rescue => e
  log_error_and_find(e, { controller_name: "version_kitchen", platform: "Web" })
end

assert "K6: error persisted", versioned_error.persisted?

if RailsErrorDashboard::ErrorLog.column_names.include?("app_version")
  assert "K6: app_version stored", versioned_error.app_version == "2.0.0-rc1",
    "got #{versioned_error.app_version.inspect}"
end

if RailsErrorDashboard::ErrorLog.column_names.include?("git_sha")
  assert "K6: git_sha stored", versioned_error.git_sha == "abc123def456",
    "got #{versioned_error.git_sha.inspect}"
end
puts ""

# ---------------------------------------------------------------------------
# K7: Notification throttling respects custom config
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("K7: Notification throttling with custom thresholds")

throttler = RailsErrorDashboard::Services::NotificationThrottler
throttler.clear!

# notification_minimum_severity = :medium, so :low errors should NOT trigger
low_error = begin
  raise StandardError, "low severity throttle #{SecureRandom.hex(4)}"
rescue => e
  log_error_and_find(e, { platform: "Web" })
end

assert_no_crash("K7: severity check on low error") do
  meets = throttler.severity_meets_minimum?(low_error)
  assert "K7: low severity below :medium minimum", meets == false
end

# :critical should still meet minimum
crit_error = begin
  raise SecurityError, "critical throttle #{SecureRandom.hex(4)}"
rescue Exception => e
  log_error_and_find(e, { platform: "Web" })
end

assert_no_crash("K7: severity check on critical error") do
  meets = throttler.severity_meets_minimum?(crit_error)
  assert "K7: critical meets :medium minimum", meets == true
end

throttler.clear!
puts ""

# ---------------------------------------------------------------------------
# K8: Backtrace truncation works
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("K8: Backtrace truncation (max 10 lines)")

# Generate a deep call stack
deep_error = begin
  def self.deep_call(n)
    raise RuntimeError, "deep backtrace test" if n <= 0
    deep_call(n - 1)
  end
  deep_call(30)
rescue => e
  log_error_and_find(e, { controller_name: "backtrace_kitchen", platform: "Web" })
end

assert "K8: error persisted", deep_error.persisted?
if deep_error.backtrace.present?
  bt_lines = deep_error.backtrace.split("\n").reject(&:blank?)
  # max_backtrace_lines may include an extra "... N more lines" truncation notice
  assert "K8: backtrace truncated to <= 11 lines", bt_lines.length <= 11,
    "got #{bt_lines.length} lines"
end
puts ""

# ---------------------------------------------------------------------------
# K9: Notification callbacks fire without crashing
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("K9: Notification callbacks don't crash")

assert_no_crash("K9: error logged with on_error_logged callback") do
  begin
    raise RuntimeError, "callback test #{SecureRandom.hex(4)}"
  rescue => e
    log_error_and_find(e, { controller_name: "callback_kitchen", platform: "Web" })
  end
end
puts ""

# ---------------------------------------------------------------------------
# K10: All query classes still work with all options enabled
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("K10: Query classes work with all config options")

assert_no_crash("K10: DashboardStats") do
  RailsErrorDashboard::Queries::DashboardStats.call
end

assert_no_crash("K10: ErrorsList") do
  RailsErrorDashboard::Queries::ErrorsList.call
end

assert_no_crash("K10: AnalyticsStats") do
  RailsErrorDashboard::Queries::AnalyticsStats.call
end
puts ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
exit_code = PreReleaseTestHarness.summary("PHASE K")
exit(exit_code)
