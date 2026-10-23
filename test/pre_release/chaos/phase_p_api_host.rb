# frozen_string_literal: true

# ============================================================================
# CHAOS TEST PHASE P: an API-only host
# Run with: PORT=3097 bin/rails runner test/pre_release/chaos/phase_p_api_host.rb
# Requires: a running server for an app made with `rails new --api`, with the
# injected ApiProbeController (bin/pre-release-test full_api).
#
# Installing RED must leave the host's API alone: no cookies, no sessions.
# The dashboard, which needs a session for CSRF tokens, the flash and the
# language picker, must still work end to end, on a session of its own.
# (Spec: .shipkit/specs/host-hygiene-0-17, REQ-1 and REQ-2.)
# ============================================================================

require "net/http"
require "uri"

harness_path = File.expand_path("../lib/test_harness.rb", __dir__)
require harness_path

PreReleaseTestHarness.reset!
PreReleaseTestHarness.header("CHAOS TEST PHASE P: API-ONLY HOST")

HTTP_PORT = ENV.fetch("PORT", "3000")
HTTP_USER = ENV.fetch("DASHBOARD_USER", "chaos_test_admin")
HTTP_PASS = ENV.fetch("DASHBOARD_PASS", "chaos_test_secret_42")
MOUNT_PATH = ENV.fetch("MOUNT_PATH", "/red")
ROOT = "http://localhost:#{HTTP_PORT}"
COOKIE_NAME = "_rails_error_dashboard_session"

def http_request(method, path, cookie: nil, form: nil, auth: true)
  uri = URI.parse("#{ROOT}#{path}")
  http = Net::HTTP.new(uri.host, uri.port)
  http.open_timeout = 10
  http.read_timeout = 30
  request = (method == :post ? Net::HTTP::Post : Net::HTTP::Get).new(uri.request_uri)
  request.basic_auth(HTTP_USER, HTTP_PASS) if auth
  request["Cookie"] = cookie if cookie
  request.set_form_data(form) if form
  http.request(request)
end

def set_cookies(response)
  Array(response.get_fields("set-cookie"))
end

# The dashboard's cookie as a request header, from the latest response that set it.
def dashboard_cookie(response, current = nil)
  fresh = set_cookies(response).map { |c| c.split(";").first }.find { |c| c.start_with?("#{COOKIE_NAME}=") }
  fresh || current
end

def csrf_token(body)
  body[/<meta name="csrf-token" content="([^"]+)"/, 1]
end

# ---------------------------------------------------------------------------
# P1: the host's own API endpoints
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("P1: The host's API stays sessionless (REQ-1)")

ping = http_request(:get, "/api_probe/ping", auth: false)
assert_http "host API endpoint answers", ping.code.to_i, 200..200
assert "host API endpoint sets no cookie", set_cookies(ping).empty?, set_cookies(ping).inspect

before = RailsErrorDashboard::ErrorLog.where(error_type: "ActionDispatch::Request::Session::DisabledSessionError").count
touch = http_request(:get, "/api_probe/touch_session", auth: false)
assert_http "a host endpoint that writes the session fails, as without RED", touch.code.to_i, 500..500
assert "the failing host endpoint sets no cookie", set_cookies(touch).empty?, set_cookies(touch).inspect

# The runner keeps a query cache, so a repeated COUNT would read its own first
# answer back; clear it each time (as Phase F does).
recorded = false
20.times do
  RailsErrorDashboard::ErrorLog.connection.clear_query_cache
  recorded = RailsErrorDashboard::ErrorLog
    .where(error_type: "ActionDispatch::Request::Session::DisabledSessionError").count > before
  break if recorded

  sleep 0.25
end
assert "the failure is Rails' DisabledSessionError (recorded by RED)", recorded
puts ""

# ---------------------------------------------------------------------------
# P2: the dashboard has a session of its own
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("P2: The dashboard keeps a working session (REQ-2)")

index = http_request(:get, "#{MOUNT_PATH}/errors")
assert_http "dashboard index loads", index.code.to_i, 200..200
cookie = dashboard_cookie(index)
assert "dashboard sets its own cookie (#{COOKIE_NAME})", cookie.present?, set_cookies(index).inspect

error = RailsErrorDashboard::ErrorLog.where(status: "new").order(:id).last ||
        RailsErrorDashboard::ErrorLog.order(:id).last
if error
  page = http_request(:get, "#{MOUNT_PATH}/errors/#{error.id}", cookie: cookie)
  assert_http "error page loads with the session cookie", page.code.to_i, 200..200
  cookie = dashboard_cookie(page, cookie)
  token = csrf_token(page.body)
  assert "error page carries a CSRF token", token.present?

  error.update_columns(status: "new")
  update = http_request(:post, "#{MOUNT_PATH}/errors/#{error.id}/update_status", cookie: cookie,
    form: { authenticity_token: token, status: "investigating" })
  assert_http "a CSRF-protected form post is accepted", update.code.to_i, 302..302
  RailsErrorDashboard::ErrorLog.connection.clear_query_cache
  assert "the status changed", error.reload.status == "investigating", error.status
  cookie = dashboard_cookie(update, cookie)

  # Without a redirect there is nothing to follow; the failures above say why.
  if update["location"]
    after = http_request(:get, URI.parse(update["location"]).request_uri, cookie: cookie)
    assert_http "the redirect target loads", after.code.to_i, 200..200
    assert "the flash notice shows on the next page", after.body.include?("Status changed to"),
      "no flash notice in the page"
    cookie = dashboard_cookie(after, cookie)

    picker = http_request(:post, "#{MOUNT_PATH}/locale", cookie: cookie,
      form: { authenticity_token: csrf_token(after.body), locale: "de" })
    assert_http "the language picker accepts the change", picker.code.to_i, 302..302
    cookie = dashboard_cookie(picker, cookie)

    german = http_request(:get, "#{MOUNT_PATH}/errors", cookie: cookie)
    assert "the next page is in the picked language", german.body.include?('<html lang="de"'),
      german.body[/<html[^>]*>/].to_s
  else
    assert "the form post redirected, so the flash and the language picker can be checked", false
  end
else
  assert "an error exists to exercise the dashboard's forms", false
end
puts ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
exit_code = PreReleaseTestHarness.summary("PHASE P")
exit(exit_code)
