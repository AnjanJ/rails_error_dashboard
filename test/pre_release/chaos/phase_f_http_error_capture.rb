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
    # Request errors reach RED through Rails' executor report (the middleware
    # sits above ShowExceptions), and the row still names where it came from.
    # test-gaps-0-17/REQ-5
    assert "#{description}: controller_name captured",
      error_log.controller_name.to_s.downcase.delete("_").include?("testerrors"),
      "got #{error_log.controller_name.inspect}"
    assert "#{description}: action_name captured",
      error_log.action_name == path.delete_prefix("/test/"),
      "got #{error_log.action_name.inspect}"
  end
end
puts ""

# ---------------------------------------------------------------------------
# F2: Timeout::Error (test-gaps-0-17/REQ-6)
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

assert "Timeout: captured", timeout_count_after > timeout_count_before,
  "count unchanged: #{timeout_count_before} -> #{timeout_count_after}"
assert "Timeout: severity=medium", timeout_log&.severity&.to_sym == :medium,
  "got #{timeout_log&.severity.inspect}"
puts ""

# ---------------------------------------------------------------------------
# F3-F5: exceptions Rails maps in rescue_responses (test-gaps-0-17/REQ-7)
#
# Since Rails 7.1, ShowExceptions marks a request's exception for reporting
# only when it is NOT a rescue response (action_dispatch.report_exception =
# !wrapper.rescue_response?), and the Executor reports nothing else. RED's
# middleware sits above ShowExceptions, so these client errors are answered
# with their mapped status and never recorded. If that changes (in Rails or
# in RED), these checks fail and someone decides whether it is a bug.
# ---------------------------------------------------------------------------
RESCUE_RESPONSES_UNREPORTED = Rails.gem_version >= Gem::Version.new("7.1")

def assert_rescue_response(label, status, expected_status, count_before, count_after)
  unless RESCUE_RESPONSES_UNREPORTED
    puts "  SKIP: #{label}: Rails #{Rails.version} reports rescue responses differently (checked on 7.1+)"
    return
  end

  assert "#{label}: answered #{expected_status}", status == expected_status, "got #{status}"
  assert "#{label}: not recorded (Rails leaves rescue responses unreported)",
    count_after == count_before, "count changed: #{count_before} -> #{count_after}"
end

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

assert_rescue_response("ParameterMissing", status, 400, param_count_before, param_count_after)
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

assert_rescue_response("RecordNotFound", status, 404, notfound_count_before, notfound_count_after)
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

assert_rescue_response("RecordInvalid", status, 422, invalid_count_before, invalid_count_after)
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
  # controller_name may be "test_errors" (snake_case from request.params[:controller])
  # or "TestErrorsController" (from controller.class.name via Executor context).
  # Normalize both to a comparable form before asserting. test-gaps-0-17/REQ-5
  assert "context: controller_name captured",
    nm_error.controller_name.to_s.downcase.delete("_").include?("testerrors"),
    "got #{nm_error.controller_name.inspect}"

  assert "context: action_name is 'nil_error'",
    nm_error.action_name == "nil_error",
    "got #{nm_error.action_name.inspect}"

  assert "context: occurred_at recent",
    nm_error.occurred_at > 2.minutes.ago

  assert "context: status is new",
    nm_error.status == "new"
else
  assert "context: NoMethodError should exist for context check", false
end
puts ""

# ---------------------------------------------------------------------------
# F8: TracePoint features (the HTTP chaos app turns them on)
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("F8: Local variables, instance variables, swallowed exceptions")

def parsed_json(text)
  JSON.parse(text.to_s)
rescue JSON::ParserError
  {}
end

status = http_get("/test/variables_error")
sleep 1
refresh_db_connection!
variables_log = RailsErrorDashboard::ErrorLog.where(error_type: "ChaosVariablesError").order(id: :desc).first

assert "variables: HTTP returned 500 (#{status})", status == 500, "got #{status}"
assert "variables: error captured", variables_log.present?

# Stored as { name => { "type", "value", "truncated" } }. test-gaps-0-17/REQ-8
locals = parsed_json(variables_log&.local_variables)
assert "variables: local widget_count captured", locals.dig("widget_count", "value") == 7,
  "got #{locals["widget_count"].inspect} (all: #{locals.keys.inspect})"
assert "variables: local widget_label captured", locals.dig("widget_label", "value") == "chaos-label",
  "got #{locals["widget_label"].inspect}"

# Instance variables are keyed with their @. test-gaps-0-17/REQ-9
ivars = parsed_json(variables_log&.instance_variables)
assert "variables: instance variable @chaos_marker captured",
  ivars.dig("@chaos_marker", "value") == "ivar-chaos-marker",
  "got #{ivars["@chaos_marker"].inspect} (all: #{ivars.keys.inspect})"

# A swallowed exception is written when a request on the SAME Puma thread
# completes after the 1 s flush interval, so each round sends several
# requests (a new app runs 3 threads), waits out the interval, and sends
# several more. Buffers left on worker threads die with this server, so the
# row has to appear during this run. test-gaps-0-17/REQ-10
if RUBY_VERSION >= "3.3"
  swallowed = nil
  deadline = Time.now + 20
  until swallowed || Time.now > deadline
    6.times { http_get("/test/swallowed") }
    sleep 1.2
    6.times { http_get("/test/swallowed") }
    refresh_db_connection!
    swallowed = RailsErrorDashboard::SwallowedException
      .where(exception_class: "ChaosSwallowedError")
      .where.not(rescue_location: nil)
      .first
  end

  assert "swallowed: ChaosSwallowedError recorded with its rescue", swallowed.present?,
    "no rescue row within 20 s"
  assert "swallowed: raise located in the test controller",
    swallowed&.raise_location.to_s.include?("test_errors_controller.rb"),
    "got #{swallowed&.raise_location.inspect}"
else
  puts "  SKIP: swallowed-exception detection needs Ruby 3.3+ (running #{RUBY_VERSION})"
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
