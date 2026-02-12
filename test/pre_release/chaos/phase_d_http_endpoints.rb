# frozen_string_literal: true

# ============================================================================
# CHAOS TEST PHASE D: HTTP Dashboard Endpoint Verification
# Tests every dashboard route renders without 500 errors
# Run with: bin/rails runner test/pre_release/chaos/phase_d_http_endpoints.rb
# Requires: A running Rails server on localhost:3000
# ============================================================================

require "net/http"
require "uri"

harness_path = File.expand_path("../lib/test_harness.rb", __dir__)
require harness_path

PreReleaseTestHarness.reset!
PreReleaseTestHarness.header("CHAOS TEST PHASE D: HTTP DASHBOARD ENDPOINT VERIFICATION")

# Configuration — read from environment or use defaults
HTTP_PORT = ENV.fetch("PORT", "3000")
HTTP_USER = ENV.fetch("DASHBOARD_USER", "gandalf")
HTTP_PASS = ENV.fetch("DASHBOARD_PASS", "youshallnotpass")
MOUNT_PATH = ENV.fetch("MOUNT_PATH", "/error_dashboard")
HTTP_BASE = "http://localhost:#{HTTP_PORT}#{MOUNT_PATH}"

def get_status(path)
  uri = URI.parse("#{HTTP_BASE}#{path}")
  http = Net::HTTP.new(uri.host, uri.port)
  http.open_timeout = 10
  http.read_timeout = 30
  request = Net::HTTP::Get.new(uri.request_uri)
  request.basic_auth(HTTP_USER, HTTP_PASS)
  response = http.request(request)
  response.code.to_i
rescue => e
  "ERROR: #{e.class}: #{e.message}"
end

def post_status(path, params = {})
  uri = URI.parse("#{HTTP_BASE}#{path}")
  http = Net::HTTP.new(uri.host, uri.port)
  http.open_timeout = 10
  http.read_timeout = 30
  request = Net::HTTP::Post.new(uri.request_uri)
  request.basic_auth(HTTP_USER, HTTP_PASS)
  request.set_form_data(params) unless params.empty?
  response = http.request(request)
  response.code.to_i
rescue => e
  "ERROR: #{e.class}: #{e.message}"
end

# Check if server is running
puts "Checking if server is running on port #{HTTP_PORT}..."
begin
  uri = URI.parse("http://localhost:#{HTTP_PORT}/up")
  response = Net::HTTP.get_response(uri)
  if response.code.to_i == 200
    puts "  Server is UP!"
  else
    puts "  Server returned #{response.code}. Tests may fail."
  end
rescue => e
  puts "  Server not running! Start with: bin/rails server -p #{HTTP_PORT}"
  puts "    Error: #{e.message}"
  puts ""
  puts "Cannot run HTTP tests without a running server."
  exit(1)
end
puts ""

# ---------------------------------------------------------------------------
# D1: Main pages
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("D1: Main dashboard pages")

assert_http "GET / (overview)", get_status("")
assert_http "GET /overview", get_status("/overview")
assert_http "GET /errors (index)", get_status("/errors")
assert_http "GET /settings", get_status("/settings")
puts ""

# ---------------------------------------------------------------------------
# D2: Analytics pages
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("D2: Analytics pages")

assert_http "GET /errors/analytics", get_status("/errors/analytics")
assert_http "GET /errors/analytics?days=7", get_status("/errors/analytics?days=7")
assert_http "GET /errors/analytics?days=14", get_status("/errors/analytics?days=14")
assert_http "GET /errors/analytics?days=30", get_status("/errors/analytics?days=30")
assert_http "GET /errors/analytics?days=90", get_status("/errors/analytics?days=90")
puts ""

# ---------------------------------------------------------------------------
# D3: Platform comparison page
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("D3: Platform comparison")

assert_http "GET /errors/platform_comparison", get_status("/errors/platform_comparison")
assert_http "GET /errors/platform_comparison?days=7", get_status("/errors/platform_comparison?days=7")
assert_http "GET /errors/platform_comparison?days=30", get_status("/errors/platform_comparison?days=30")
puts ""

# ---------------------------------------------------------------------------
# D4: Correlation page
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("D4: Correlation")

assert_http "GET /errors/correlation", get_status("/errors/correlation")
assert_http "GET /errors/correlation?days=7", get_status("/errors/correlation?days=7")
assert_http "GET /errors/correlation?days=30", get_status("/errors/correlation?days=30")
puts ""

# ---------------------------------------------------------------------------
# D5: Error index with filters
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("D5: Error index filters")

assert_http "GET /errors?severity=critical", get_status("/errors?severity=critical")
assert_http "GET /errors?severity=high", get_status("/errors?severity=high")
assert_http "GET /errors?severity=medium", get_status("/errors?severity=medium")
assert_http "GET /errors?severity=low", get_status("/errors?severity=low")
assert_http "GET /errors?unresolved=true", get_status("/errors?unresolved=true")
assert_http "GET /errors?timeframe=1h", get_status("/errors?timeframe=1h")
assert_http "GET /errors?timeframe=24h", get_status("/errors?timeframe=24h")
assert_http "GET /errors?timeframe=7d", get_status("/errors?timeframe=7d")
assert_http "GET /errors?timeframe=30d", get_status("/errors?timeframe=30d")
assert_http "GET /errors?hide_snoozed=true", get_status("/errors?hide_snoozed=true")
assert_http "GET /errors?status=new", get_status("/errors?status=new")
assert_http "GET /errors?status=investigating", get_status("/errors?status=investigating")
assert_http "GET /errors?status=in_progress", get_status("/errors?status=in_progress")
assert_http "GET /errors?status=resolved", get_status("/errors?status=resolved")
assert_http "GET /errors?frequency=high", get_status("/errors?frequency=high")
assert_http "GET /errors?frequency=medium", get_status("/errors?frequency=medium")
assert_http "GET /errors?frequency=low", get_status("/errors?frequency=low")
assert_http "GET /errors?search=NoMethodError", get_status("/errors?search=NoMethodError")
assert_http "GET /errors?sort_by=occurred_at&sort_direction=asc", get_status("/errors?sort_by=occurred_at&sort_direction=asc")
assert_http "GET /errors?sort_by=occurrence_count&sort_direction=desc", get_status("/errors?sort_by=occurrence_count&sort_direction=desc")
assert_http "GET /errors?sort_by=priority_score&sort_direction=desc", get_status("/errors?sort_by=priority_score&sort_direction=desc")
assert_http "GET /errors?per_page=10", get_status("/errors?per_page=10")
assert_http "GET /errors?per_page=50", get_status("/errors?per_page=50")
assert_http "GET /errors?per_page=100", get_status("/errors?per_page=100")
puts ""

# ---------------------------------------------------------------------------
# D6: Error index with combined filters
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("D6: Combined filters")

assert_http "severity+timeframe+unresolved", get_status("/errors?severity=critical&timeframe=30d&unresolved=true")
assert_http "search+platform+sort", get_status("/errors?search=error&platform=Web&sort_by=occurred_at&sort_direction=desc")
assert_http "all filters at once", get_status("/errors?severity=high&timeframe=7d&unresolved=true&hide_snoozed=true&sort_by=priority_score&sort_direction=desc&per_page=10")
puts ""

# ---------------------------------------------------------------------------
# D7: Error index with edge case filter values
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("D7: Edge case filter values")

assert_http "empty search", get_status("/errors?search=")
assert_http "bogus severity", get_status("/errors?severity=bogus")
assert_http "bogus timeframe", get_status("/errors?timeframe=bogus")
assert_http "bogus sort_by", get_status("/errors?sort_by=bogus")
assert_http "XSS in search", get_status("/errors?search=%3Cscript%3Ealert(1)%3C/script%3E")
assert_http "SQL injection in search", get_status("/errors?search='+OR+1=1+--")
assert_http "very long search", get_status("/errors?search=#{"A" * 500}")
assert_http "unicode search", get_status("/errors?search=%E6%97%A5%E6%9C%AC%E8%AA%9E")
assert_http "negative per_page", get_status("/errors?per_page=-1")
assert_http "zero per_page", get_status("/errors?per_page=0")
assert_http "huge per_page", get_status("/errors?per_page=99999")

# Pagy edge cases — our rescue_from handles these gracefully now
page0_status = get_status("/errors?page=0")
assert_http "page=0 (redirects to page 1)", page0_status, 200..399

page_huge_status = get_status("/errors?page=999999")
assert_http "page=999999 (redirects to page 1)", page_huge_status, 200..399
puts ""

# ---------------------------------------------------------------------------
# D8: Individual error show pages
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("D8: Error show pages")

error_ids = RailsErrorDashboard::ErrorLog.order(id: :desc).limit(5).pluck(:id)
error_ids.each do |id|
  assert_http "GET /errors/#{id} (show)", get_status("/errors/#{id}")
end

# Non-existent error — returns 404 (RecordNotFound rescued)
status = get_status("/errors/999999")
assert_http "GET /errors/999999 (not found -> 404)", status, 404..404
puts ""

# ---------------------------------------------------------------------------
# D9: Multi-app filter
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("D9: Multi-app filter")

apps = RailsErrorDashboard::Application.pluck(:id, :name)
apps.each do |id, name|
  assert_http "GET /errors?application_id=#{id} (#{name})", get_status("/errors?application_id=#{id}")
  assert_http "GET /overview?application_id=#{id}", get_status("/overview?application_id=#{id}")
  assert_http "GET /errors/analytics?application_id=#{id}", get_status("/errors/analytics?application_id=#{id}")
end
puts ""

# ---------------------------------------------------------------------------
# D10: Workflow actions via HTTP
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("D10: Workflow actions via HTTP")

test_error = begin
  raise RuntimeError, "HTTP workflow chaos #{SecureRandom.hex(4)}"
rescue => e
  log_error_and_find(e, { platform: "Web" })
end
eid = test_error.id

# POST endpoints require CSRF token — without it, Rails returns 422 (CSRF protection)
assert_http "POST assign blocked by CSRF", post_status("/errors/#{eid}/assign", { assigned_to: "Gandalf" }), 422..500
assert_http "POST resolve blocked by CSRF", post_status("/errors/#{eid}/resolve", { resolved_by_name: "Aragorn" }), 422..500
puts "  (POST actions require CSRF token — correct Rails security behavior)"

# Verify workflow commands still work directly
assigned = RailsErrorDashboard::Commands::AssignError.call(eid, assigned_to: "Gandalf")
assert_http "direct assign works", (assigned.assigned_to == "Gandalf" ? 200 : 500)

resolved = RailsErrorDashboard::Commands::ResolveError.call(eid, resolved_by_name: "Aragorn")
assert_http "direct resolve works", (resolved.resolved? ? 200 : 500)
puts ""

# ---------------------------------------------------------------------------
# D11: Batch action via HTTP
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("D11: Batch actions")

batch_errors = 2.times.map do |i|
  begin
    raise RuntimeError, "batch http chaos #{i} #{SecureRandom.hex(4)}"
  rescue => e
    log_error_and_find(e, { platform: "Web" })
  end
end
batch_ids = batch_errors.map { |e| e.id.to_s }

# Batch resolve via HTTP blocked by CSRF (expected)
assert_http "POST batch_action blocked by CSRF", post_status("/errors/batch_action", {
  "error_ids[]" => batch_ids.first,
  action_type: "resolve",
  resolved_by_name: "Gandalf"
}), 422..500

# Direct batch resolve works
result = RailsErrorDashboard::Commands::BatchResolveErrors.call(batch_ids, resolved_by_name: "Gimli")
assert_http "direct batch resolve works", (result[:success] ? 200 : 500)
puts ""

# ---------------------------------------------------------------------------
# D12: Authentication checks
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("D12: Authentication checks")

# Try without auth
uri = URI.parse("http://localhost:#{HTTP_PORT}#{MOUNT_PATH}")
http = Net::HTTP.new(uri.host, uri.port)
http.open_timeout = 5
http.read_timeout = 10
request = Net::HTTP::Get.new(uri.request_uri)
response = http.request(request)
no_auth_status = response.code.to_i
assert_http "no auth -> 401", no_auth_status, 401..401

# Try with wrong auth
request2 = Net::HTTP::Get.new(uri.request_uri)
request2.basic_auth("sauron", "onering")
response2 = http.request(request2)
wrong_auth_status = response2.code.to_i
assert_http "wrong auth -> 401", wrong_auth_status, 401..401
puts ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
exit_code = PreReleaseTestHarness.summary("PHASE D")
exit(exit_code)
