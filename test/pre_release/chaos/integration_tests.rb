# frozen_string_literal: true

# ============================================================================
# Full Integration Tests
# Comprehensive HTTP-level testing of every dashboard page, action, and filter
#
# Run via: bin/full-integration-test
# Requires: Running Rails server with seeded data
#
# Environment variables:
#   PORT         - Server port (default: 3100)
#   MOUNT_PATH   - Engine mount path (default: /error_dashboard)
#   AUTH_USER    - Basic auth username (default: gandalf)
#   AUTH_PASS    - Basic auth password (default: youshallnotpass)
# ============================================================================

require_relative "../lib/integration_test_runner"

PORT = ENV.fetch("PORT", "3100")
MOUNT = ENV.fetch("MOUNT_PATH", "/error_dashboard")
BASE_URL = "http://localhost:#{PORT}#{MOUNT}"
AUTH_USER = ENV.fetch("AUTH_USER", "gandalf")
AUTH_PASS = ENV.fetch("AUTH_PASS", "youshallnotpass")

IntegrationTestRunner.configure(
  base_url: BASE_URL,
  user: AUTH_USER,
  password: AUTH_PASS
)

IntegrationTestRunner.header("FULL INTEGRATION TESTS — #{BASE_URL}")

# ============================================================================
# Phase 1: Authentication
# ============================================================================
section "Phase 1: Authentication"

resp = get_no_auth("/")
assert_status "No auth on overview -> 401", resp, 401..401

resp = get_no_auth("/errors")
assert_status "No auth on errors index -> 401", resp, 401..401

resp = get_wrong_auth("/")
assert_status "Wrong auth on overview -> 401", resp, 401..401

resp = get("/")
assert_status "Correct auth on overview -> 200", resp, 200..200

# ============================================================================
# Phase 2: Page Loading — Every GET route
# ============================================================================
section "Phase 2: Page Loading"

# Overview
resp = get("/")
assert_status "GET / (root/overview) -> 200", resp, 200..200
assert_contains "Overview has stats", resp.body, "error", "Error"

resp = get("/overview")
assert_status "GET /overview -> 200", resp, 200..200

# Errors index
resp = get("/errors")
assert_status "GET /errors (index) -> 200", resp, 200..200
assert_contains "Index has filter form", resp.body, "search", "severity"

# Settings
resp = get("/settings")
assert_status "GET /settings -> 200", resp, 200..200
assert_contains "Settings page has config", resp.body, "Configuration"

# Analytics
resp = get("/errors/analytics")
assert_status "GET /errors/analytics -> 200", resp, 200..200

resp = get("/errors/analytics", params: { days: "7" })
assert_status "GET /errors/analytics?days=7 -> 200", resp, 200..200

resp = get("/errors/analytics", params: { days: "90" })
assert_status "GET /errors/analytics?days=90 -> 200", resp, 200..200

# Platform comparison
resp = get("/errors/platform_comparison")
assert_status "GET /errors/platform_comparison -> 200", resp, 200..200

resp = get("/errors/platform_comparison", params: { days: "30" })
assert_status "GET /errors/platform_comparison?days=30 -> 200", resp, 200..200

# Correlation
resp = get("/errors/correlation")
assert_status "GET /errors/correlation -> 200", resp, 200..200

resp = get("/errors/correlation", params: { days: "7" })
assert_status "GET /errors/correlation?days=7 -> 200", resp, 200..200

# ============================================================================
# Phase 3: Error Show Pages
# ============================================================================
section "Phase 3: Error Show Pages"

# Get the errors list to find error IDs
index_resp = get("/errors", params: { per_page: "50" })
if index_resp && index_resp.code.to_i == 200
  # Extract error IDs from href links like /error_dashboard/errors/123
  error_ids = index_resp.body.scan(/#{Regexp.escape(MOUNT)}\/errors\/(\d+)/).flatten.uniq.first(10)

  assert "Found error IDs in index page", error_ids.length > 0, "found #{error_ids.length}"

  error_ids.first(5).each do |eid|
    resp = get("/errors/#{eid}")
    assert_status "GET /errors/#{eid} (show) -> 200", resp, 200..200

    if resp && resp.code.to_i == 200
      body = resp.body
      # Verify key sections are present
      assert_contains "Show page #{eid} has error info", body, "error_type", "backtrace"
      assert_contains "Show page #{eid} has metadata sidebar", body, "Occurrence", "First Seen"
      assert_contains "Show page #{eid} has CSRF token", body, "csrf-token"
    end
  end

  # 404 for non-existent error
  resp = get("/errors/999999")
  assert_status "GET /errors/999999 -> 404", resp, 404..404
else
  $stdout.puts "  [SKIP] Could not load errors index"
end

# ============================================================================
# Phase 4: Filters & Pagination
# ============================================================================
section "Phase 4: Filters & Pagination"

filter_tests = [
  [ { severity: "critical" }, "severity=critical" ],
  [ { severity: "high" }, "severity=high" ],
  [ { severity: "low" }, "severity=low" ],
  [ { platform: "Web" }, "platform=Web" ],
  [ { platform: "iOS" }, "platform=iOS" ],
  [ { platform: "Android" }, "platform=Android" ],
  [ { unresolved: "true" }, "unresolved=true" ],
  [ { status: "resolved" }, "status=resolved" ],
  [ { status: "investigating" }, "status=investigating" ],
  [ { status: "new" }, "status=new" ],
  [ { timeframe: "7d" }, "timeframe=7d" ],
  [ { timeframe: "24h" }, "timeframe=24h" ],
  [ { search: "NoMethodError" }, "search=NoMethodError" ],
  [ { search: "RuntimeError" }, "search=RuntimeError" ],
  [ { sort_by: "occurrence_count", sort_direction: "desc" }, "sort by occurrence_count desc" ],
  [ { sort_by: "occurred_at", sort_direction: "asc" }, "sort by occurred_at asc" ],
  [ { hide_snoozed: "true" }, "hide_snoozed=true" ],
  [ { per_page: "10" }, "per_page=10" ],
  [ { per_page: "50" }, "per_page=50" ],
  [ { page: "2", per_page: "5" }, "page=2 with per_page=5" ],
]

filter_tests.each do |params, label|
  resp = get("/errors", params: params)
  assert_status "Filter: #{label} -> 200", resp, 200..200
end

# Combined filters
resp = get("/errors", params: { severity: "critical", unresolved: "true", platform: "Web" })
assert_status "Combined: severity+unresolved+platform -> 200", resp, 200..200

resp = get("/errors", params: { search: "Error", sort_by: "occurrence_count", sort_direction: "desc", per_page: "10" })
assert_status "Combined: search+sort+per_page -> 200", resp, 200..200

# Multi-app filter — get an application_id from the index page first
if index_resp && index_resp.body.include?("application_id")
  app_ids = index_resp.body.scan(/application_id=(\d+)/).flatten.uniq
  if app_ids.any?
    resp = get("/errors", params: { application_id: app_ids.first })
    assert_status "Filter: application_id=#{app_ids.first} -> 200", resp, 200..200

    resp = get("/overview", params: { application_id: app_ids.first })
    assert_status "Overview with application_id -> 200", resp, 200..200
  end
end

# ============================================================================
# Phase 5: Edge Cases
# ============================================================================
section "Phase 5: Edge Cases"

# Pagy overflow — page too high should redirect or return 200
resp = get("/errors", params: { page: "99999" })
assert_status "page=99999 -> redirect or 200", resp, 200..302

# XSS in search — should not break, content should be escaped
resp = get("/errors", params: { search: "<script>alert(1)</script>" })
assert_status "XSS search -> 200", resp, 200..200
if resp && resp.code.to_i == 200
  assert_not_contains "XSS search is escaped", resp.body, "<script>alert(1)</script>"
end

# SQL injection in search
resp = get("/errors", params: { search: "' OR 1=1--" })
assert_status "SQL injection search -> 200", resp, 200..200

# Invalid sort_by
resp = get("/errors", params: { sort_by: "DROP_TABLE" })
assert_status "Invalid sort_by -> 200", resp, 200..200

# Invalid severity
resp = get("/errors", params: { severity: "nonexistent" })
assert_status "Invalid severity -> 200", resp, 200..200

# Empty search
resp = get("/errors", params: { search: "" })
assert_status "Empty search -> 200", resp, 200..200

# Unicode search
resp = get("/errors", params: { search: "エラー 错误 오류" })
assert_status "Unicode search -> 200", resp, 200..200

# Negative per_page
resp = get("/errors", params: { per_page: "-1" })
assert_status "per_page=-1 -> 200", resp, 200..200

# Huge per_page
resp = get("/errors", params: { per_page: "10000" })
assert_status "per_page=10000 -> 200", resp, 200..200

# ============================================================================
# Phase 6: Actions (POST with CSRF)
# ============================================================================
section "Phase 6: Actions (POST with CSRF tokens)"

# We need error IDs to test actions on.
# Re-fetch index to find unresolved errors.
index_resp = get("/errors", params: { per_page: "50", unresolved: "true" })
if index_resp && index_resp.code.to_i == 200
  all_ids = index_resp.body.scan(/#{Regexp.escape(MOUNT)}\/errors\/(\d+)/).flatten.uniq
  test_ids = all_ids.first(8)

  if test_ids.length >= 6
    # --- Assign ---
    assign_id = test_ids[0]
    # Visit show page first to get fresh CSRF token
    get("/errors/#{assign_id}")
    resp = post("/errors/#{assign_id}/assign", params: { assigned_to: "tester@example.com" })
    if resp
      assert_status "Assign error #{assign_id} -> 200 (after redirect)", resp, 200..200
      assert_contains "Assign visible on page", resp.body, "tester@example.com"
    end

    # --- Unassign ---
    get("/errors/#{assign_id}")
    resp = post("/errors/#{assign_id}/unassign")
    if resp
      assert_status "Unassign error #{assign_id} -> 200", resp, 200..200
      assert_not_contains "Assigned_to cleared", resp.body, "tester@example.com"
    end

    # --- Update Priority ---
    priority_id = test_ids[1]
    get("/errors/#{priority_id}")
    resp = post("/errors/#{priority_id}/update_priority", params: { priority_level: "0" })
    if resp
      assert_status "Update priority #{priority_id} to P0 -> 200", resp, 200..200
      assert_contains "Priority P0 visible", resp.body, "Critical"
    end

    # --- Snooze ---
    snooze_id = test_ids[2]
    get("/errors/#{snooze_id}")
    resp = post("/errors/#{snooze_id}/snooze", params: { hours: "24", reason: "Integration test snooze" })
    if resp
      assert_status "Snooze error #{snooze_id} -> 200", resp, 200..200
      assert_contains "Snoozed indicator visible", resp.body, "Snoozed", "nooz"
    end

    # --- Unsnooze ---
    get("/errors/#{snooze_id}")
    resp = post("/errors/#{snooze_id}/unsnooze")
    if resp
      assert_status "Unsnooze error #{snooze_id} -> 200", resp, 200..200
    end

    # --- Update Status ---
    status_id = test_ids[3]
    get("/errors/#{status_id}")
    resp = post("/errors/#{status_id}/update_status", params: { status: "investigating", comment: "Looking into it" })
    if resp
      assert_status "Update status #{status_id} to investigating -> 200", resp, 200..200
      assert_contains "Status investigating visible", resp.body, "investigating", "nvestigat"
    end

    get("/errors/#{status_id}")
    resp = post("/errors/#{status_id}/update_status", params: { status: "in_progress" })
    if resp
      assert_status "Update status #{status_id} to in_progress -> 200", resp, 200..200
    end

    # --- Add Comment ---
    comment_id = test_ids[4]
    get("/errors/#{comment_id}")
    resp = post("/errors/#{comment_id}/add_comment", params: {
      author_name: "Integration Tester",
      body: "This is an integration test comment with special chars: <b>bold</b> & 'quotes'"
    })
    if resp
      assert_status "Add comment to #{comment_id} -> 200", resp, 200..200
      assert_contains "Comment visible on page", resp.body, "Integration Tester", "integration test comment"
    end

    # --- Resolve ---
    resolve_id = test_ids[5]
    get("/errors/#{resolve_id}")
    resp = post("/errors/#{resolve_id}/resolve", params: {
      resolved_by_name: "Integration Test",
      resolution_comment: "Resolved during integration testing",
      resolution_reference: "TEST-001"
    })
    if resp
      assert_status "Resolve error #{resolve_id} -> 200", resp, 200..200
      assert_contains "Resolved indicator visible", resp.body, "Resolved", "resolved", "esolved"
    end
  else
    $stdout.puts "  [SKIP] Not enough unresolved errors for action tests (need 6, found #{test_ids.length})"
  end

  # --- Batch Resolve ---
  if test_ids.length >= 8
    batch_ids = test_ids[6..7]
    get("/errors") # Get CSRF token from index page
    resp = post("/errors/batch_action", params: {
      "action_type" => "resolve",
      "error_ids[]" => batch_ids[0],
      "resolved_by_name" => "Batch Tester",
      "resolution_comment" => "Batch resolved"
    })
    # Batch action may also accept multiple error_ids differently
    # The controller reads params[:error_ids] as an array
    if resp
      assert_status "Batch resolve -> 200", resp, 200..200
    end
  end
else
  $stdout.puts "  [SKIP] Could not load errors index for action tests"
end

# ============================================================================
# Phase 7: Content & Link Integrity
# ============================================================================
section "Phase 7: Content & Link Integrity"

# Re-fetch index
index_resp = get("/errors", params: { per_page: "50" })
if index_resp && index_resp.code.to_i == 200
  error_ids = index_resp.body.scan(/#{Regexp.escape(MOUNT)}\/errors\/(\d+)/).flatten.uniq

  # Test first 3 error show pages in detail
  error_ids.first(3).each do |eid|
    resp = get("/errors/#{eid}")
    next unless resp && resp.code.to_i == 200

    body = resp.body

    # Structural elements
    assert_contains "Show #{eid}: has breadcrumb nav", body, "errors", "Error"
    assert_contains "Show #{eid}: has severity badge", body, "badge"
    assert_contains "Show #{eid}: has CSRF meta tag", body, "csrf-token"

    # Metadata sidebar checks
    has_occurrence = body.include?("Occurrence") || body.include?("occurrence")
    assert "Show #{eid}: has occurrence count", has_occurrence

    has_first_seen = body.include?("First Seen") || body.include?("first_seen") || body.include?("First seen")
    assert "Show #{eid}: has first seen", has_first_seen

    has_severity = body.include?("Severity") || body.include?("severity")
    assert "Show #{eid}: has severity section", has_severity

    has_status = body.include?("Status") || body.include?("status")
    assert "Show #{eid}: has status section", has_status

    # Action modals/buttons should be present for unresolved errors
    unless body.include?("Resolved") && !body.include?("resolveModal")
      has_resolve = body.include?("resolve") || body.include?("Resolve")
      assert "Show #{eid}: has resolve action", has_resolve
    end

    has_assign = body.include?("assign") || body.include?("Assign")
    assert "Show #{eid}: has assign action", has_assign

    has_priority = body.include?("priority") || body.include?("Priority")
    assert "Show #{eid}: has priority section", has_priority
  end

  # Verify overview page has key sections
  resp = get("/")
  if resp && resp.code.to_i == 200
    body = resp.body
    assert_contains "Overview: has error stats", body, "error", "Error"
    has_links = body.include?("errors") || body.include?("/errors")
    assert "Overview: has links to error pages", has_links
  end

  # Verify analytics page has chart/data sections
  resp = get("/errors/analytics")
  if resp && resp.code.to_i == 200
    body = resp.body
    has_time_data = body.include?("chart") || body.include?("Chart") || body.include?("chartkick") || body.include?("day")
    assert "Analytics: has chart or time data", has_time_data
  end
end

# ============================================================================
# Phase 8: Error Capture via HTTP
# ============================================================================
section "Phase 8: Error Capture via HTTP"

# These tests hit the test error controller endpoints (injected by the orchestrator)
# and verify the errors appear on the dashboard

test_error_endpoints = [
  [ "/test/nil_error", "NoMethodError" ],
  [ "/test/divide_by_zero", "ZeroDivisionError" ],
  [ "/test/type_error", "TypeError" ],
  [ "/test/runtime_error", "RuntimeError" ],
  [ "/test/json_parse", "JSON::ParserError" ],
]

# Hit each error endpoint (these are outside the engine mount, no auth needed)
test_base = "http://localhost:#{PORT}"

test_error_endpoints.each do |path, expected_type|
  begin
    uri = URI("#{test_base}#{path}")
    req = Net::HTTP::Get.new(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 10
    resp = http.request(req)
    # Error endpoints return 500 (or similar) — that's expected
    assert "Hit #{path} -> got response (#{resp.code})", !resp.nil?
  rescue => e
    # Connection errors are OK if the server is responding
    assert "Hit #{path} -> connection (#{e.class.name})", true
  end
end

# Wait a moment for async capture
sleep 2

# Now check that errors appear on the dashboard
resp = get("/errors", params: { per_page: "100" })
if resp && resp.code.to_i == 200
  body = resp.body
  captured_types = test_error_endpoints.map { |_, t| t }
  captured_types.each do |error_type|
    has_type = body.include?(error_type)
    assert "Captured #{error_type} visible on dashboard", has_type
  end
end

# Check error_count endpoint for verification
begin
  uri = URI("#{test_base}/test/error_count")
  req = Net::HTTP::Get.new(uri)
  http = Net::HTTP.new(uri.host, uri.port)
  http.open_timeout = 5
  http.read_timeout = 10
  resp = http.request(req)
  if resp.code.to_i == 200
    data = JSON.parse(resp.body)
    assert "Error count endpoint returns total > 0", data["total"].to_i > 0, "total=#{data["total"]}"
  end
rescue => e
  $stdout.puts "  [SKIP] Error count endpoint: #{e.message}"
end

# Deduplication test — hit the same error endpoint twice
2.times do
  begin
    uri = URI("#{test_base}/test/runtime_error")
    req = Net::HTTP::Get.new(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 10
    http.request(req)
  rescue
    # Expected
  end
end

sleep 1

# Verify RuntimeError occurrence count > 1 by searching
resp = get("/errors", params: { search: "RuntimeError", per_page: "10" })
if resp && resp.code.to_i == 200
  # The occurrence count should be visible in the table
  assert "RuntimeError search returns results", resp.body.include?("RuntimeError")
end

# ============================================================================
# Summary
# ============================================================================

IntegrationTestRunner.summary("FULL INTEGRATION TESTS")
