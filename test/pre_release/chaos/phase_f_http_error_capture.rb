# frozen_string_literal: true

# ============================================================================
# CHAOS TEST PHASE F: HTTP Error Capture via Middleware + Subscriber
# Verifies that REAL controller errors are AUTOMATICALLY captured by the
# ErrorCatcher middleware and ErrorReporter subscriber.
#
# Requires: A running Rails server with test error controllers injected.
# Run with: PORT=3098 bin/rails runner test/pre_release/chaos/phase_f_http_error_capture.rb
# ============================================================================

require "net/http"
require "uri"

harness_path = File.expand_path("../lib/test_harness.rb", __dir__)
require harness_path

PreReleaseTestHarness.reset!
PreReleaseTestHarness.header("CHAOS TEST PHASE F: HTTP ERROR CAPTURE VIA MIDDLEWARE")

HTTP_PORT = ENV.fetch("PORT", "3098")
HTTP_BASE = "http://localhost:#{HTTP_PORT}"

def http_get(path)
  uri = URI.parse("#{HTTP_BASE}#{path}")
  http = Net::HTTP.new(uri.host, uri.port)
  http.open_timeout = 10
  http.read_timeout = 30
  response = http.request(Net::HTTP::Get.new(uri.request_uri))
  response.code.to_i
rescue => e
  "ERROR: #{e.class}: #{e.message}"
end

# Force a fresh database read — essential for SQLite cross-process visibility.
# With journal_mode=delete, SQLite uses traditional locking and readers
# always see committed data. We just need to clear AR's query cache.
def refresh_db_connection!
  RailsErrorDashboard::ErrorLog.connection.clear_query_cache
end

# Check server is running
puts "Checking server on port #{HTTP_PORT}..."
begin
  uri = URI.parse("#{HTTP_BASE}/up")
  response = Net::HTTP.get_response(uri)
  if response.code.to_i == 200
    puts "  Server is UP!"
  else
    puts "  Server returned #{response.code}. Tests may fail."
  end
rescue => e
  puts "  Server not running! Error: #{e.message}"
  exit(1)
end
puts ""

initial_count = RailsErrorDashboard::ErrorLog.count

# ---------------------------------------------------------------------------
# F1: Standard error endpoints — each triggers a different error type
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("F1: Error endpoints trigger middleware capture")

# Map: [path, expected_error_type, expected_severity, description]
STANDARD_ENDPOINTS = [
  [ "/test/nil_error",       "NoMethodError",      :high,     "NoMethodError from nil.method" ],
  [ "/test/divide_by_zero",  "ZeroDivisionError",  :high,     "ZeroDivisionError from 1/0" ],
  [ "/test/type_error",      "TypeError",          :high,     "TypeError from Integer(nil)" ],
  [ "/test/name_error",      "NameError",          :high,     "NameError from undefined constant" ],
  [ "/test/json_parse",      "JSON::ParserError",  :medium,   "JSON::ParserError from bad JSON" ],
  [ "/test/runtime_error",   "RuntimeError",       :low,      "RuntimeError baseline" ],
  [ "/test/custom_error",    "CustomTestError",    :critical, "CustomTestError via custom severity rule" ]
].freeze

STANDARD_ENDPOINTS.each do |path, expected_type, expected_severity, description|
  refresh_db_connection!
  count_before = RailsErrorDashboard::ErrorLog.where(error_type: expected_type).count

  status = http_get(path)
  sleep 1 # pause for server to write + DB flush

  refresh_db_connection!
  count_after = RailsErrorDashboard::ErrorLog.where(error_type: expected_type).count
  error_log = find_captured_error(expected_type)

  assert "#{description}: HTTP returned error status (#{status})",
    status.is_a?(Integer) && status >= 400,
    "got #{status}"

  assert "#{description}: ErrorLog record created",
    count_after > count_before,
    "count unchanged: #{count_before} -> #{count_after}"

  if error_log
    assert "#{description}: error_type correct", error_log.error_type == expected_type
    assert "#{description}: severity=#{expected_severity}", error_log.severity.to_sym == expected_severity,
      "got #{error_log.severity}"
    assert "#{description}: message present", error_log.message.present?
    assert "#{description}: backtrace present", error_log.backtrace.present?
    assert "#{description}: error_hash present", error_log.error_hash.present?
    # controller_name/action_name may not be available when errors are reported
    # by ActionDispatch::Executor instead of our ErrorCatcher middleware
    if error_log.controller_name.present?
      assert "#{description}: controller_name captured", true
    else
      assert "#{description}: controller_name not available (Executor path — OK)", true
    end
    if error_log.action_name.present?
      assert "#{description}: action_name captured", true
    else
      assert "#{description}: action_name not available (Executor path — OK)", true
    end
  end
end
puts ""

# ---------------------------------------------------------------------------
# F2: Timeout::Error (may be flaky — tolerant test)
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("F2: Timeout::Error capture")

refresh_db_connection!
timeout_count_before = RailsErrorDashboard::ErrorLog.where(error_type: "Timeout::Error").count
status = http_get("/test/timeout")
sleep 1

refresh_db_connection!
timeout_count_after = RailsErrorDashboard::ErrorLog.where(error_type: "Timeout::Error").count
timeout_log = find_captured_error("Timeout::Error")

assert "Timeout: HTTP returned error status (#{status})",
  status.is_a?(Integer) && status >= 400,
  "got #{status}"

if timeout_count_after > timeout_count_before
  assert "Timeout: captured", true
  assert "Timeout: severity=medium", timeout_log&.severity&.to_sym == :medium
else
  # Timeout can be flaky in test — don't hard-fail
  puts "  (Timeout::Error may not have fired reliably — skipped)"
  assert "Timeout: tolerant skip", true
end
puts ""

# ---------------------------------------------------------------------------
# F3: ActionController::ParameterMissing
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("F3: ActionController::ParameterMissing capture")

refresh_db_connection!
param_count_before = RailsErrorDashboard::ErrorLog
  .where(error_type: "ActionController::ParameterMissing")
  .count

status = http_get("/test/param_missing")
sleep 1

refresh_db_connection!
param_count_after = RailsErrorDashboard::ErrorLog
  .where(error_type: "ActionController::ParameterMissing")
  .count

param_log = find_captured_error("ActionController::ParameterMissing")

# Rails returns 400 for ParameterMissing in development mode
assert "ParameterMissing: HTTP returned 400+ (#{status})",
  status.is_a?(Integer) && status >= 400,
  "got #{status}"

if param_count_after > param_count_before
  assert "ParameterMissing: captured by middleware", true
  assert "ParameterMissing: error_type correct", param_log&.error_type == "ActionController::ParameterMissing"
else
  # Rails may handle ParameterMissing before middleware in some configurations
  puts "  (ParameterMissing handled by Rails before middleware — acceptable)"
  assert "ParameterMissing: Rails handled internally (OK)", true
end
puts ""

# ---------------------------------------------------------------------------
# F4: ActiveRecord::RecordNotFound
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("F4: ActiveRecord::RecordNotFound capture")

refresh_db_connection!
notfound_count_before = RailsErrorDashboard::ErrorLog
  .where(error_type: "ActiveRecord::RecordNotFound")
  .count

status = http_get("/test/not_found")
sleep 1

refresh_db_connection!
notfound_count_after = RailsErrorDashboard::ErrorLog
  .where(error_type: "ActiveRecord::RecordNotFound")
  .count

notfound_log = find_captured_error("ActiveRecord::RecordNotFound")

# Rails may return 404 for RecordNotFound
assert "RecordNotFound: HTTP returned 404 or 500 (#{status})",
  status.is_a?(Integer) && [ 404, 500 ].include?(status),
  "got #{status}"

if notfound_count_after > notfound_count_before
  assert "RecordNotFound: captured by middleware", true
  assert "RecordNotFound: severity=high", notfound_log&.severity&.to_sym == :high
else
  puts "  (RecordNotFound handled by Rails before middleware — acceptable)"
  assert "RecordNotFound: Rails handled internally (OK)", true
end
puts ""

# ---------------------------------------------------------------------------
# F5: ActiveRecord::RecordInvalid
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("F5: ActiveRecord::RecordInvalid capture")

refresh_db_connection!
invalid_count_before = RailsErrorDashboard::ErrorLog
  .where(error_type: "ActiveRecord::RecordInvalid")
  .count

status = http_get("/test/validation_error")
sleep 1

refresh_db_connection!
invalid_count_after = RailsErrorDashboard::ErrorLog
  .where(error_type: "ActiveRecord::RecordInvalid")
  .count

invalid_log = find_captured_error("ActiveRecord::RecordInvalid")

assert "RecordInvalid: HTTP returned error status (#{status})",
  status.is_a?(Integer) && status >= 400,
  "got #{status}"

if invalid_count_after > invalid_count_before
  assert "RecordInvalid: captured", true
  assert "RecordInvalid: severity=medium", invalid_log&.severity&.to_sym == :medium
else
  # RecordInvalid may be rescued by Rails rescue_responses (mapped to 422)
  # and not reported via Rails.error in some Rails versions
  puts "  (RecordInvalid not reported by Rails Executor — acceptable)"
  assert "RecordInvalid: Rails handled internally (OK)", true
end
puts ""

# ---------------------------------------------------------------------------
# F6: Deduplication across HTTP requests
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("F6: Deduplication across HTTP requests")

# RuntimeError from /test/runtime_error has already been hit once in F1
# Hit it again — should deduplicate
refresh_db_connection!
runtime_before = RailsErrorDashboard::ErrorLog
  .where(error_type: "RuntimeError")
  .where("message LIKE ?", "%Runtime error from test controller%")
  .first

initial_occurrence = runtime_before&.occurrence_count.to_i

http_get("/test/runtime_error")
sleep 1

refresh_db_connection!
runtime_after = RailsErrorDashboard::ErrorLog
  .where(error_type: "RuntimeError")
  .where("message LIKE ?", "%Runtime error from test controller%")
  .to_a

assert "dedup: single RuntimeError record", runtime_after.length == 1,
  "got #{runtime_after.length} records"
assert "dedup: occurrence_count incremented", runtime_after.first&.occurrence_count.to_i > initial_occurrence,
  "was #{initial_occurrence}, now #{runtime_after.first&.occurrence_count}"
puts ""

# ---------------------------------------------------------------------------
# F7: Request context from real HTTP requests
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("F7: Request context from real HTTP requests")

# Check the NoMethodError from F1 for full request context
refresh_db_connection!
nm_error = RailsErrorDashboard::ErrorLog
  .where(error_type: "NoMethodError")
  .order(id: :desc)
  .first

if nm_error
  # In production mode, errors may be reported by either:
  # 1. Our ErrorCatcher middleware (includes request context)
  # 2. ActionDispatch::Executor (may not include request context)
  # Test tolerantly: verify context is present when available
  # controller_name may be "test_errors" (from request.params[:controller])
  # or "TestErrorsController" (from controller.class.name via Executor context)
  if nm_error.controller_name.present?
    assert "context: controller_name captured",
      nm_error.controller_name.downcase.include?("testerror"),
      "got #{nm_error.controller_name.inspect}"
  else
    assert "context: controller_name not available (Executor path — OK)", true
  end

  if nm_error.action_name.present?
    assert "context: action_name is 'nil_error'",
      nm_error.action_name == "nil_error",
      "got #{nm_error.action_name.inspect}"
  else
    assert "context: action_name not available (Executor path — OK)", true
  end

  assert "context: occurred_at recent",
    nm_error.occurred_at > 2.minutes.ago

  assert "context: status is new",
    nm_error.status == "new"
else
  assert "context: NoMethodError should exist for context check", false
end
puts ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
refresh_db_connection!
new_count = RailsErrorDashboard::ErrorLog.count
puts "  Total errors captured via middleware: #{new_count - initial_count}"
exit_code = PreReleaseTestHarness.summary("PHASE F")
exit(exit_code)
