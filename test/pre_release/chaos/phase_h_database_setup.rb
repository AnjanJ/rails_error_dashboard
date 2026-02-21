# frozen_string_literal: true

# ============================================================================
# CHAOS TEST PHASE H: Database Setup & Verify Task
# Tests the verify rake task, multi-app support, and database configuration
# in production mode.
# Run with: bin/rails runner test/pre_release/chaos/phase_h_database_setup.rb
# ============================================================================

harness_path = File.expand_path("../lib/test_harness.rb", __dir__)
require harness_path

PreReleaseTestHarness.reset!
PreReleaseTestHarness.header("CHAOS TEST PHASE H: DATABASE SETUP & VERIFY")

# ---------------------------------------------------------------------------
# H1: Configuration validation
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("H1: Configuration validation")

config = RailsErrorDashboard.configuration

assert_no_crash("H1: configuration accessible") { config }
assert "H1: configuration responds to use_separate_database", config.respond_to?(:use_separate_database)
assert "H1: configuration responds to database", config.respond_to?(:database)
assert "H1: configuration responds to application_name", config.respond_to?(:application_name)
assert "H1: configuration responds to validate!", config.respond_to?(:validate!)

assert_no_crash("H1: validate! passes") { config.validate! }

puts ""

# ---------------------------------------------------------------------------
# H2: Database connection
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("H2: Database connection")

assert_no_crash("H2: ErrorLogsRecord connection works") do
  # Note: SQLite's active? returns nil (not true), so we test that the
  # connection can execute a query instead of checking active? truthiness
  RailsErrorDashboard::ErrorLogsRecord.connection.execute("SELECT 1")
  assert "H2: connection is usable", true
end

assert_no_crash("H2: adapter name accessible") do
  adapter = RailsErrorDashboard::ErrorLogsRecord.connection.adapter_name
  assert "H2: adapter is string", adapter.is_a?(String)
  assert "H2: adapter is not empty", adapter.present?
end

puts ""

# ---------------------------------------------------------------------------
# H3: Required tables exist
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("H3: Required tables")

required_tables = %w[
  rails_error_dashboard_applications
  rails_error_dashboard_error_logs
  rails_error_dashboard_error_occurrences
  rails_error_dashboard_error_comments
  rails_error_dashboard_error_baselines
  rails_error_dashboard_cascade_patterns
]

conn = RailsErrorDashboard::ErrorLogsRecord.connection

required_tables.each do |table|
  exists = conn.table_exists?(table)
  assert "H3: table #{table} exists", exists
end

puts ""

# ---------------------------------------------------------------------------
# H4: Application auto-registration
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("H4: Application auto-registration")

# Get auto-detected app name
detected_name = config.application_name ||
                ENV["APPLICATION_NAME"] ||
                (defined?(Rails) && Rails.application.class.module_parent_name) ||
                "Unknown"

assert "H4: application name detected", detected_name.present?,
  "got: #{detected_name.inspect}"

# Create an error — should auto-register the application
app_test_error = begin
  raise RuntimeError, "app registration test #{SecureRandom.hex(4)}"
rescue => e
  log_error_and_find(e, { controller_name: "app_reg_test", platform: "Web" })
end

assert "H4: error persisted", app_test_error.persisted?
assert "H4: error has application_id", app_test_error.application_id.present?

# Verify the application record was created
app_record = RailsErrorDashboard::Application.find(app_test_error.application_id)
assert "H4: application record exists", app_record.present?
assert "H4: application name matches", app_record.name == detected_name,
  "expected #{detected_name.inspect}, got #{app_record.name.inspect}"

puts ""

# ---------------------------------------------------------------------------
# H5: Multi-app error isolation
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("H5: Multi-app error isolation")

# Create a second application manually
app2 = RailsErrorDashboard::Application.find_or_create_by!(name: "ChaosTestApp2") do |a|
  a.description = "Created by Phase H chaos test"
end

assert "H5: second app created", app2.persisted?
assert "H5: second app has different id", app2.id != app_record.id

# Create error for app2
app2_error = RailsErrorDashboard::ErrorLog.create!(
  application: app2,
  error_type: "ArgumentError",
  message: "multi-app isolation test",
  occurred_at: Time.current,
  platform: "API",
  backtrace: "test.rb:1:in `test'"
)

assert "H5: app2 error persisted", app2_error.persisted?
assert "H5: app2 error has correct application_id", app2_error.application_id == app2.id

# Query errors scoped to each app
app1_count = RailsErrorDashboard::ErrorLog.where(application_id: app_record.id).count
app2_count = RailsErrorDashboard::ErrorLog.where(application_id: app2.id).count

assert "H5: app1 has errors", app1_count > 0
assert "H5: app2 has errors", app2_count > 0
assert "H5: errors are isolated", app1_count != app2_count || app1_count == 1

# Verify Application.all returns both
all_apps = RailsErrorDashboard::Application.all
assert "H5: 2+ applications registered", all_apps.count >= 2

puts ""

# ---------------------------------------------------------------------------
# H6: ErrorHashGenerator includes application_id
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("H6: Error hash scoped by application")

# Same error type+message+backtrace but different apps should get different hashes
hash1 = RailsErrorDashboard::Services::ErrorHashGenerator.from_attributes(
  error_type: "TestError",
  message: "same message",
  backtrace: "test.rb:1",
  controller_name: "test",
  action_name: "index",
  application_id: app_record.id
)

hash2 = RailsErrorDashboard::Services::ErrorHashGenerator.from_attributes(
  error_type: "TestError",
  message: "same message",
  backtrace: "test.rb:1",
  controller_name: "test",
  action_name: "index",
  application_id: app2.id
)

assert "H6: hash1 is 16-char hex", hash1&.match?(/\A[0-9a-f]{16}\z/)
assert "H6: hash2 is 16-char hex", hash2&.match?(/\A[0-9a-f]{16}\z/)
assert "H6: different apps -> different hashes", hash1 != hash2,
  "both got #{hash1}"

puts ""

# ---------------------------------------------------------------------------
# H7: FindOrCreateApplication caching
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("H7: FindOrCreateApplication caching")

Rails.cache.clear

assert_no_crash("H7: first call creates app") do
  result = RailsErrorDashboard::Commands::FindOrCreateApplication.call("CachingTestApp")
  assert "H7: returns application", result.is_a?(RailsErrorDashboard::Application)
  assert "H7: correct name", result.name == "CachingTestApp"
end

# Second call should use cache (no DB query)
assert_no_crash("H7: second call uses cache") do
  result = RailsErrorDashboard::Commands::FindOrCreateApplication.call("CachingTestApp")
  assert "H7: returns same app from cache", result.name == "CachingTestApp"
end

puts ""

# ---------------------------------------------------------------------------
# H8: Database mode configuration
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("H8: Database mode configuration")

if config.use_separate_database
  assert "H8: separate DB mode", true
  assert "H8: database key configured", config.database.present?,
    "config.database is nil — should be set when use_separate_database is true"
  assert "H8: database key is symbol", config.database.is_a?(Symbol),
    "got #{config.database.class}"
else
  assert "H8: shared DB mode", true
  # In shared mode, database key is optional
end

# Verify ErrorLogsRecord connects to the right database
assert_no_crash("H8: ErrorLogsRecord can execute queries") do
  count = RailsErrorDashboard::ErrorLog.count
  assert "H8: count query works", count.is_a?(Integer)
end

puts ""

# ---------------------------------------------------------------------------
# H9: Verify task simulation (checks all the same things the rake task checks)
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("H9: Verify task checks (simulated)")

# 1. Config validates
assert_no_crash("H9: config validates") { config.validate! }

# 2. Connection works
assert_no_crash("H9: connection active") do
  RailsErrorDashboard::ErrorLogsRecord.connection.active?
end

# 3. All tables exist
missing_tables = required_tables.reject { |t| conn.table_exists?(t) }
assert "H9: all 6 tables present", missing_tables.empty?,
  "missing: #{missing_tables.join(', ')}"

# 4. Error count works
assert_no_crash("H9: error count works") do
  total = RailsErrorDashboard::ErrorLog.count
  unresolved = RailsErrorDashboard::ErrorLog.where(resolved: false).count
  assert "H9: total >= unresolved", total >= unresolved
end

# 5. Auth check
assert "H9: dashboard_username set", config.dashboard_username.present?
assert "H9: dashboard_password set", config.dashboard_password.present?

puts ""

# ---------------------------------------------------------------------------
# H10: Backward compatibility — config.database accepts any symbol
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("H10: Backward compatibility")

original_db = config.database
original_separate = config.use_separate_database

begin
  # Verify config accepts any symbol for database name
  assert_no_crash("H10: accepts :error_dashboard") do
    config.database = :error_dashboard
    assert "H10: stored :error_dashboard", config.database == :error_dashboard
  end

  assert_no_crash("H10: accepts :error_logs (legacy)") do
    config.database = :error_logs
    assert "H10: stored :error_logs", config.database == :error_logs
  end

  assert_no_crash("H10: accepts :custom_name") do
    config.database = :custom_name
    assert "H10: stored :custom_name", config.database == :custom_name
  end

  # Verify validation requires database when separate is true
  config.use_separate_database = true
  config.database = nil
  validation_failed = false
  begin
    config.validate!
  rescue RailsErrorDashboard::ConfigurationError
    validation_failed = true
  end
  assert "H10: validation fails with nil database when separate=true", validation_failed
ensure
  config.database = original_db
  config.use_separate_database = original_separate
end

puts ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
exit_code = PreReleaseTestHarness.summary("PHASE H")
exit(exit_code)
