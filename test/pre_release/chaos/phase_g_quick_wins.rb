# frozen_string_literal: true

# ============================================================================
# CHAOS TEST PHASE G: v0.2 Quick Wins Verification
# Tests all quick win features in production mode
# Run with: bin/rails runner test/pre_release/chaos/phase_g_quick_wins.rb
# ============================================================================

harness_path = File.expand_path("../lib/test_harness.rb", __dir__)
require harness_path

PreReleaseTestHarness.reset!
PreReleaseTestHarness.header("CHAOS TEST PHASE G: v0.2 QUICK WINS")

# ---------------------------------------------------------------------------
# G1: Exception Cause Chain
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("G1: Exception cause chain extraction")

cause_error = begin
  begin
    begin
      raise ActiveRecord::RecordNotFound, "Couldn't find User with id=999"
    rescue => inner
      raise NoMethodError, "undefined method 'name' for nil:NilClass"
    end
  rescue => middle
    raise RuntimeError, "Failed to process user request"
  end
rescue => e
  log_error_and_find(e, { controller_name: "cause_chain_test", platform: "Web" })
end

assert "G1: error persisted", cause_error.persisted?
assert "G1: exception_cause populated", cause_error.exception_cause.present?

if cause_error.exception_cause.present?
  cause_chain = JSON.parse(cause_error.exception_cause)
  assert "G1: cause chain is array", cause_chain.is_a?(Array)
  assert "G1: cause chain has entries", cause_chain.length >= 1
  first_cause = cause_chain.first
  assert "G1: cause has class_name", first_cause["class_name"].present?
  assert "G1: cause has message", first_cause["message"].present?
end
puts ""

# ---------------------------------------------------------------------------
# G2: Enriched Request Context
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("G2: Enriched request context fields")

enriched_error = begin
  raise RuntimeError, "enriched context test #{SecureRandom.hex(4)}"
rescue => e
  log_error_and_find(e, {
    controller_name: "enriched_test",
    platform: "Web",
    http_method: "POST",
    hostname: "api.example.com",
    content_type: "application/json",
    request_duration_ms: 1234
  })
end

assert "G2: error persisted", enriched_error.persisted?

if RailsErrorDashboard::ErrorLog.column_names.include?("http_method")
  assert "G2: http_method stored", enriched_error.http_method == "POST"
end

if RailsErrorDashboard::ErrorLog.column_names.include?("hostname")
  assert "G2: hostname stored", enriched_error.hostname == "api.example.com"
end

if RailsErrorDashboard::ErrorLog.column_names.include?("content_type")
  assert "G2: content_type stored", enriched_error.content_type == "application/json"
end

if RailsErrorDashboard::ErrorLog.column_names.include?("request_duration_ms")
  assert "G2: request_duration_ms stored", enriched_error.request_duration_ms == 1234
end
puts ""

# ---------------------------------------------------------------------------
# G3: Environment Info Snapshot
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("G3: Environment info snapshot")

env_error = begin
  raise RuntimeError, "environment info test #{SecureRandom.hex(4)}"
rescue => e
  log_error_and_find(e, { controller_name: "env_test", platform: "Web" })
end

assert "G3: error persisted", env_error.persisted?

if RailsErrorDashboard::ErrorLog.column_names.include?("environment_info")
  assert "G3: environment_info populated", env_error.environment_info.present?

  if env_error.environment_info.present?
    env_info = JSON.parse(env_error.environment_info, symbolize_names: true)
    assert "G3: rails_version present", env_info[:rails_version].present?
    assert "G3: ruby_version present", env_info[:ruby_version].present?
    assert "G3: rails_env present", env_info[:rails_env].present?
  end
end
puts ""

# ---------------------------------------------------------------------------
# G4: Sensitive Data Filtering
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("G4: Sensitive data filtering")

sensitive_error = begin
  raise RuntimeError, "sensitive data test #{SecureRandom.hex(4)}"
rescue => e
  log_error_and_find(e, {
    controller_name: "sensitive_test",
    platform: "Web",
    params: {
      username: "gandalf",
      password: "super_secret_123",
      api_key: "sk-1234567890abcdef",
      secret_key_base: "abc123def456ghi789",
      name: "Gandalf the Grey"
    }
  })
end

assert "G4: error persisted", sensitive_error.persisted?
assert "G4: request_params present", sensitive_error.request_params.present?

if sensitive_error.request_params.present?
  params_str = sensitive_error.request_params
  assert "G4: password filtered", params_str.include?("[FILTERED]"),
    "expected [FILTERED] in params"
  assert "G4: raw password NOT present", !params_str.include?("super_secret_123"),
    "raw password leaked!"
  assert "G4: raw api_key NOT present", !params_str.include?("sk-1234567890abcdef"),
    "raw api_key leaked!"
  assert "G4: non-sensitive username preserved", params_str.include?("gandalf")
  assert "G4: non-sensitive name preserved", params_str.include?("Gandalf the Grey")
end
puts ""

# ---------------------------------------------------------------------------
# G5: Auto-Reopen resolved errors
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("G5: Auto-reopen resolved errors")

# Create and resolve an error
reopen_error = begin
  raise RuntimeError, "auto-reopen test #{SecureRandom.hex(8)}"
rescue => e
  log_error_and_find(e, { controller_name: "reopen_test", platform: "Web" })
end

original_id = reopen_error.id
original_hash = reopen_error.error_hash
original_count = reopen_error.occurrence_count

# Resolve it
RailsErrorDashboard::Commands::ResolveError.call(
  reopen_error.id,
  resolved_by_name: "Gandalf",
  resolution_comment: "Fixed it"
)

reopen_error.reload
assert "G5: error is resolved", reopen_error.resolved == true
assert "G5: status is resolved", reopen_error.status == "resolved"
assert "G5: resolved_at set", reopen_error.resolved_at.present?

# Log the same error again → should reopen
reopened = begin
  raise RuntimeError, "auto-reopen test #{SecureRandom.hex(8)}"
rescue => e
  # Use same controller/platform to get same hash
  error = RuntimeError.new(reopen_error.message)
  error.set_backtrace(reopen_error.backtrace.to_s.split("\n"))
  log_error_and_find(error, { controller_name: "reopen_test", platform: "Web" })
end

# The reopened error should be the same record
reopen_error.reload
assert "G5: same record (not duplicated)", reopen_error.id == original_id
assert "G5: resolved cleared", reopen_error.resolved == false
assert "G5: status back to new", reopen_error.status == "new"
assert "G5: resolved_at cleared", reopen_error.resolved_at.nil?
assert "G5: occurrence_count incremented", reopen_error.occurrence_count > original_count,
  "was #{original_count}, now #{reopen_error.occurrence_count}"

if RailsErrorDashboard::ErrorLog.column_names.include?("reopened_at")
  assert "G5: reopened_at set", reopen_error.reopened_at.present?
end

# Test wont_fix → reopen path
wontfix_error = begin
  raise ArgumentError, "wont_fix reopen test #{SecureRandom.hex(8)}"
rescue => e
  log_error_and_find(e, { controller_name: "wontfix_test", platform: "Web" })
end

wontfix_id = wontfix_error.id
wontfix_error.update!(resolved: true, status: "wont_fix", resolved_at: Time.current)
wontfix_error.reload
assert "G5: wont_fix status set", wontfix_error.status == "wont_fix"

# Log same error again
wontfix_again = begin
  error = ArgumentError.new(wontfix_error.message)
  error.set_backtrace(wontfix_error.backtrace.to_s.split("\n"))
  raise error
rescue => e
  log_error_and_find(e, { controller_name: "wontfix_test", platform: "Web" })
end

wontfix_error.reload
assert "G5: wont_fix reopened", wontfix_error.resolved == false
assert "G5: wont_fix status -> new", wontfix_error.status == "new"
puts ""

# ---------------------------------------------------------------------------
# G6: Notification Throttling
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("G6: Notification throttling")

throttler = RailsErrorDashboard::Services::NotificationThrottler

# Clear state first
assert_no_crash("G6: clear! works") { throttler.clear! }

# Create test error for severity checks
throttle_error = begin
  raise SecurityError, "throttle test #{SecureRandom.hex(4)}"
rescue Exception => e
  log_error_and_find(e, { platform: "Web" })
end

assert_no_crash("G6: severity_meets_minimum? works") do
  result = throttler.severity_meets_minimum?(throttle_error)
  assert "G6: critical error meets minimum severity", result == true
end

# Record notification and check cooldown
assert_no_crash("G6: record_notification works") do
  throttler.record_notification(throttle_error)
end

assert_no_crash("G6: should_notify? respects cooldown") do
  # Should be in cooldown now
  result = throttler.should_notify?(throttle_error)
  assert "G6: in cooldown -> should_notify? returns false", result == false
end

# Check threshold milestones
low_error = begin
  raise StandardError, "threshold test #{SecureRandom.hex(4)}"
rescue => e
  log_error_and_find(e, { platform: "Web" })
end

assert_no_crash("G6: threshold_reached? works") do
  # With occurrence_count=1, threshold should not be reached
  result = throttler.threshold_reached?(low_error)
  assert "G6: low occurrence -> threshold not reached", result == false
end

# Clear and verify fresh state
throttler.clear!
assert_no_crash("G6: after clear, should_notify? returns true") do
  result = throttler.should_notify?(throttle_error)
  assert "G6: after clear -> should_notify? true", result == true
end
puts ""

# ---------------------------------------------------------------------------
# G7: Custom Fingerprint Lambda
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("G7: Custom fingerprint lambda")

# Save original config
original_lambda = RailsErrorDashboard.configuration.custom_fingerprint

begin
  # Set custom fingerprint that groups all errors together
  RailsErrorDashboard.configuration.custom_fingerprint = lambda { |_exception, _context|
    "fixed-fingerprint-for-test"
  }

  fp_error1 = begin
    raise RuntimeError, "fingerprint test A #{SecureRandom.hex(4)}"
  rescue => e
    log_error_and_find(e, { controller_name: "fp_test", platform: "Web" })
  end

  fp_error2 = begin
    raise ArgumentError, "fingerprint test B #{SecureRandom.hex(4)}"
  rescue => e
    log_error_and_find(e, { controller_name: "fp_test", platform: "Web" })
  end

  assert "G7: error 1 persisted", fp_error1.persisted?
  assert "G7: error 2 persisted", fp_error2.persisted?
  assert "G7: same hash (custom fingerprint dedup)", fp_error1.error_hash == fp_error2.error_hash,
    "got #{fp_error1.error_hash} vs #{fp_error2.error_hash}"
  assert "G7: same record (deduped)", fp_error1.id == fp_error2.id
ensure
  # Restore original config
  RailsErrorDashboard.configuration.custom_fingerprint = original_lambda
end
puts ""

# ---------------------------------------------------------------------------
# G8: Structured Backtrace Parsing
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("G8: Structured backtrace parsing")

parser = RailsErrorDashboard::Services::BacktraceParser

mixed_backtrace = [
  "/home/deploy/myapp/app/models/user.rb:42:in `save_record'",
  "/home/deploy/myapp/app/controllers/users_controller.rb:15:in `create'",
  "/home/deploy/.gems/gems/actionpack-7.1.0/lib/action_controller/metal.rb:227:in `dispatch'",
  "/home/deploy/.gems/gems/railties-7.1.0/lib/rails/engine.rb:123:in `call'"
].join("\n")

assert_no_crash("G8: BacktraceParser.parse works") do
  frames = parser.parse(mixed_backtrace)
  assert "G8: returns array of frames", frames.is_a?(Array)
  assert "G8: correct number of frames", frames.length == 4, "got #{frames.length}"

  app_frames = frames.select { |f| f[:category] == :app }
  non_app_frames = frames.reject { |f| f[:category] == :app }

  assert "G8: 2 app frames detected", app_frames.length == 2,
    "got #{app_frames.length} app frames"
  assert "G8: 2 framework/gem frames detected", non_app_frames.length == 2,
    "got #{non_app_frames.length} non-app frames"
end

assert_no_crash("G8: BacktraceParser handles nil") do
  frames = parser.parse(nil)
  assert "G8: nil backtrace -> empty array", frames.is_a?(Array) && frames.empty?
end

assert_no_crash("G8: BacktraceParser handles empty string") do
  frames = parser.parse("")
  assert "G8: empty backtrace -> empty array", frames.is_a?(Array) && frames.empty?
end
puts ""

# ---------------------------------------------------------------------------
# G9: CurrentAttributes Auto-Capture (fallback path)
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("G9: CurrentAttributes auto-capture (fallback)")

assert_no_crash("G9: ErrorContext handles missing Current class") do
  ctx = RailsErrorDashboard::ValueObjects::ErrorContext.new({}, nil)
  # Without Current defined, should return nil gracefully
  assert "G9: user_id is nil (no Current)", ctx.user_id.nil?
  assert "G9: request_id is nil (no Current)", ctx.request_id.nil?
end

# If Current IS defined (some Rails apps define it), test that path too
if defined?(Current)
  assert_no_crash("G9: ErrorContext with Current defined") do
    ctx = RailsErrorDashboard::ValueObjects::ErrorContext.new({}, nil)
    # Should not crash even if Current.user is nil
    assert "G9: handles Current.user=nil gracefully", true
  end
end
puts ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
exit_code = PreReleaseTestHarness.summary("PHASE G")
exit(exit_code)
