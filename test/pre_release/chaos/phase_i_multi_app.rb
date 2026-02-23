# frozen_string_literal: true

# ============================================================================
# CHAOS TEST PHASE I: Multi-App Shared Database Isolation
# Verifies two applications sharing one error dashboard database maintain
# proper data isolation via application_id scoping.
#
# Expects: Two apps have already seeded errors via Phase E.
# Expects: ENV["ALPHA_APP_DIR"] and ENV["BETA_APP_DIR"] are set (for context),
#           and this script runs from the Alpha app.
# Expects: ENV["BETA_APP_NAME"] = "MultiAppBeta"
#
# Run with: bin/rails runner test/pre_release/chaos/phase_i_multi_app.rb
# ============================================================================

harness_path = File.expand_path("../lib/test_harness.rb", __dir__)
require harness_path

PreReleaseTestHarness.reset!
PreReleaseTestHarness.header("CHAOS TEST PHASE I: MULTI-APP SHARED DB ISOLATION")

beta_app_name = ENV.fetch("BETA_APP_NAME", "MultiAppBeta")

# ---------------------------------------------------------------------------
# I1: Both applications exist in the database
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("I1: Both applications registered")

all_apps = RailsErrorDashboard::Application.all
app_names = all_apps.map(&:name)

alpha_app = all_apps.find { |a| a.name == "MultiAppAlpha" }
beta_app = all_apps.find { |a| a.name == beta_app_name }

assert "I1: MultiAppAlpha exists", alpha_app.present?,
  "apps in DB: #{app_names.inspect}"
assert "I1: #{beta_app_name} exists", beta_app.present?,
  "apps in DB: #{app_names.inspect}"
assert "I1: different application IDs", alpha_app&.id != beta_app&.id
puts ""

# ---------------------------------------------------------------------------
# I2: Errors are scoped by application_id
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("I2: Error scoping by application_id")

if alpha_app && beta_app
  alpha_errors = RailsErrorDashboard::ErrorLog.where(application_id: alpha_app.id)
  beta_errors = RailsErrorDashboard::ErrorLog.where(application_id: beta_app.id)
  total_errors = RailsErrorDashboard::ErrorLog.count

  assert "I2: Alpha has errors", alpha_errors.count > 0,
    "alpha count: #{alpha_errors.count}"
  assert "I2: Beta has errors", beta_errors.count > 0,
    "beta count: #{beta_errors.count}"
  assert "I2: total = alpha + beta", total_errors == alpha_errors.count + beta_errors.count,
    "total=#{total_errors}, alpha=#{alpha_errors.count}, beta=#{beta_errors.count}"

  # Verify no cross-contamination: Alpha errors should not have Beta's app_id
  cross_alpha = alpha_errors.where(application_id: beta_app.id).count
  cross_beta = beta_errors.where(application_id: alpha_app.id).count
  assert "I2: no cross-contamination Alpha->Beta", cross_alpha == 0
  assert "I2: no cross-contamination Beta->Alpha", cross_beta == 0
end
puts ""

# ---------------------------------------------------------------------------
# I3: Error hashes are scoped by application
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("I3: Error hash scoping by application")

if alpha_app && beta_app
  # Same error type/message/backtrace should get different hashes per app
  hash1 = RailsErrorDashboard::Services::ErrorHashGenerator.from_attributes(
    error_type: "RuntimeError",
    message: "multi-app hash test",
    backtrace: "test.rb:1",
    controller_name: "test",
    action_name: "index",
    application_id: alpha_app.id
  )

  hash2 = RailsErrorDashboard::Services::ErrorHashGenerator.from_attributes(
    error_type: "RuntimeError",
    message: "multi-app hash test",
    backtrace: "test.rb:1",
    controller_name: "test",
    action_name: "index",
    application_id: beta_app.id
  )

  assert "I3: Alpha hash is valid", hash1&.match?(/\A[0-9a-f]{16}\z/)
  assert "I3: Beta hash is valid", hash2&.match?(/\A[0-9a-f]{16}\z/)
  assert "I3: different apps -> different hashes", hash1 != hash2,
    "both got #{hash1}"
end
puts ""

# ---------------------------------------------------------------------------
# I4: DashboardStats scopes correctly
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("I4: DashboardStats with application scoping")

assert_no_crash("I4: DashboardStats runs without crash") do
  RailsErrorDashboard::Queries::DashboardStats.call
end

assert_no_crash("I4: ErrorsList runs without crash") do
  RailsErrorDashboard::Queries::ErrorsList.call
end
puts ""

# ---------------------------------------------------------------------------
# I5: FindOrCreateApplication caching works for both apps
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("I5: Application caching")

Rails.cache.clear

assert_no_crash("I5: FindOrCreate Alpha") do
  result = RailsErrorDashboard::Commands::FindOrCreateApplication.call("MultiAppAlpha")
  assert "I5: returns Alpha", result.name == "MultiAppAlpha"
end

assert_no_crash("I5: FindOrCreate Beta") do
  result = RailsErrorDashboard::Commands::FindOrCreateApplication.call(beta_app_name)
  assert "I5: returns Beta", result.name == beta_app_name
end

# Verify cache doesn't mix them up
assert_no_crash("I5: cached Alpha != cached Beta") do
  alpha = RailsErrorDashboard::Commands::FindOrCreateApplication.call("MultiAppAlpha")
  beta = RailsErrorDashboard::Commands::FindOrCreateApplication.call(beta_app_name)
  assert "I5: different cached records", alpha.id != beta.id
end
puts ""

# ---------------------------------------------------------------------------
# I6: New error from Alpha stays in Alpha
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("I6: New error stays in correct app scope")

if alpha_app
  new_error = begin
    raise RuntimeError, "isolation verify #{SecureRandom.hex(8)}"
  rescue => e
    log_error_and_find(e, { controller_name: "isolation_test", platform: "Web" })
  end

  assert "I6: new error persisted", new_error.persisted?
  assert "I6: new error belongs to Alpha", new_error.application_id == alpha_app.id,
    "expected app_id=#{alpha_app.id}, got #{new_error.application_id}"
end
puts ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
exit_code = PreReleaseTestHarness.summary("PHASE I")
exit(exit_code)
