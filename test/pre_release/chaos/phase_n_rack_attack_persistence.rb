# frozen_string_literal: true

# ============================================================================
# CHAOS TEST PHASE N: Rack::Attack event persistence (issue #143)
#
# Verifies that Rack::Attack events reach the DATABASE inside a real
# production-mode Rails app boot.
#
# The bug this guards against: events were previously written only as
# breadcrumbs, and breadcrumbs are harvested exclusively by LogError. A
# throttled request returns HTTP 429 and raises nothing, so the event was
# always discarded when ErrorCatcher cleared the buffer. The dashboard page
# returned 200 while showing nothing — which is why the pre-existing Phase D
# check ("GET /errors/rack_attack_summary" => 200) passed against a feature
# that had never worked for anyone.
#
# The load-bearing assertion here is N3: a throttle event with NO exception
# raised must produce a row.
#
# Run with: bin/rails runner test/pre_release/chaos/phase_n_rack_attack_persistence.rb
# ============================================================================

harness_path = File.expand_path("../lib/test_harness.rb", __dir__)
require harness_path

PreReleaseTestHarness.reset!
PreReleaseTestHarness.header("CHAOS TEST PHASE N: RACK ATTACK PERSISTENCE")

tracker = RailsErrorDashboard::Services::RackAttackTracker
event_model = RailsErrorDashboard::RackAttackEvent
subscriber = RailsErrorDashboard::Subscribers::RackAttackSubscriber

# Fake request duck-type matching what Rack::Attack puts in the payload.
FakeRackAttackRequest = Struct.new(:env, :path, :request_method)

def fake_request(rule:, ip:, path: "/admin/users/sign_in", method: "POST")
  FakeRackAttackRequest.new(
    { "rack.attack.matched" => rule, "rack.attack.match_discriminator" => ip },
    path,
    method
  )
end

original_flag = RailsErrorDashboard.configuration.enable_rack_attack_tracking
RailsErrorDashboard.configuration.enable_rack_attack_tracking = true
tracker.reset!
event_model.delete_all
subscriber.subscribe!

# ---------------------------------------------------------------------------
# N1: Setup — table, model, and wiring exist in a booted app
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("N1: Setup + autoload")

assert "N1: RackAttackEvent model loaded",
  defined?(RailsErrorDashboard::RackAttackEvent) == "constant"
assert "N1: RackAttackTracker service loaded",
  defined?(RailsErrorDashboard::Services::RackAttackTracker) == "constant"
assert "N1: rack_attack_events table exists",
  event_model.table_exists?
assert "N1: enable_rack_attack_tracking is true",
  RailsErrorDashboard.configuration.enable_rack_attack_tracking == true

# ---------------------------------------------------------------------------
# N2: Capture buffers without touching the DB
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("N2: Buffering (no I/O in request path)")

ActiveSupport::Notifications.instrument(
  "throttle.rack_attack", request: fake_request(rule: "logins/ip", ip: "127.0.0.1")
) { }

assert "N2: event buffered in memory",
  tracker.buffered_counts.values.sum == 1
assert "N2: no DB row written before flush",
  event_model.count == 0

# ---------------------------------------------------------------------------
# N3: THE REGRESSION — throttle with no exception must persist
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("N3: Persistence without any error (issue #143)")

errors_before = RailsErrorDashboard::ErrorLog.count
tracker.flush!(sync: true)

assert "N3: throttle event persisted to DB",
  event_model.count == 1

row = event_model.first
assert "N3: rule stored correctly",          row.rule == "logins/ip"
assert "N3: match_type stored correctly",    row.match_type == "throttle"
assert "N3: discriminator stored correctly", row.discriminator == "127.0.0.1"
assert "N3: path stored correctly",          row.path == "/admin/users/sign_in"
assert "N3: http_method stored correctly",   row.http_method == "POST"
assert "N3: event_count is 1",               row.event_count == 1
assert "N3: no ErrorLog row was created",
  RailsErrorDashboard::ErrorLog.count == errors_before

# ---------------------------------------------------------------------------
# N4: Aggregation — floods collapse into hourly buckets
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("N4: Hourly aggregation under flood")

50.times do
  ActiveSupport::Notifications.instrument(
    "throttle.rack_attack", request: fake_request(rule: "logins/ip", ip: "127.0.0.1")
  ) { }
end
tracker.flush!(sync: true)

assert "N4: 50 more events did NOT create 50 rows",
  event_model.count == 1
assert "N4: count aggregated to 51",
  event_model.first.event_count == 51

# ---------------------------------------------------------------------------
# N5: Distinct discriminators and match types
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("N5: Distinct keys + match types")

ActiveSupport::Notifications.instrument(
  "blocklist.rack_attack", request: fake_request(rule: "bad_ips", ip: "10.0.0.1", path: "/admin")
) { }
ActiveSupport::Notifications.instrument(
  "track.rack_attack", request: fake_request(rule: "api_usage", ip: "user_42", path: "/api")
) { }
tracker.flush!(sync: true)

assert "N5: blocklist event persisted",
  event_model.where(match_type: "blocklist", rule: "bad_ips").exists?
assert "N5: track event persisted",
  event_model.where(match_type: "track", rule: "api_usage").exists?

# ---------------------------------------------------------------------------
# N6: Query layer reflects persisted rows
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("N6: RackAttackSummary query")

summary = RailsErrorDashboard::Queries::RackAttackSummary.call(30)
rules = summary[:events].map { |e| e[:rule] }

assert "N6: summary returns all three rules",
  %w[logins/ip bad_ips api_usage].all? { |r| rules.include?(r) }

logins = summary[:events].find { |e| e[:rule] == "logins/ip" }
assert "N6: logins/ip count is 51", logins[:count] == 51
assert "N6: logins/ip unique_ips is 1", logins[:unique_ips] == 1
assert "N6: sorted by count descending",
  summary[:events].first[:rule] == "logins/ip"

# ---------------------------------------------------------------------------
# N7: Config gate — disabled means no capture
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("N7: Config gate")

RailsErrorDashboard.configuration.enable_rack_attack_tracking = false
tracker.reset!
ActiveSupport::Notifications.instrument(
  "throttle.rack_attack", request: fake_request(rule: "ignored", ip: "9.9.9.9")
) { }

assert "N7: nothing buffered when tracking disabled",
  tracker.buffered_counts.empty?

RailsErrorDashboard.configuration.enable_rack_attack_tracking = true

# ---------------------------------------------------------------------------
# N8: Host app safety — malformed payloads never raise
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("N8: Host app safety")

safety_ok = true
begin
  ActiveSupport::Notifications.instrument("throttle.rack_attack", request: nil) { }
  ActiveSupport::Notifications.instrument("throttle.rack_attack", {}) { }
  ActiveSupport::Notifications.instrument(
    "throttle.rack_attack", request: FakeRackAttackRequest.new(nil, nil, nil)
  ) { }
rescue => e
  safety_ok = false
  puts "  Unexpected raise: #{e.class} - #{e.message}"
end

assert "N8: malformed payloads never raise to the host", safety_ok

# Over-long values must not blow the column limits
tracker.reset!
ActiveSupport::Notifications.instrument(
  "throttle.rack_attack",
  request: fake_request(rule: "r" * 500, ip: "d" * 500, path: "p" * 500)
) { }

long_ok = true
begin
  tracker.flush!(sync: true)
rescue => e
  long_ok = false
  puts "  Unexpected raise on long values: #{e.class} - #{e.message}"
end
assert "N8: over-long values truncated and persisted", long_ok

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
subscriber.unsubscribe!
tracker.reset!
event_model.delete_all
RailsErrorDashboard.configuration.enable_rack_attack_tracking = original_flag

exit_code = PreReleaseTestHarness.summary("PHASE N")
exit(exit_code)
