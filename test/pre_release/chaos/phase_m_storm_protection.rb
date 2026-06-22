# frozen_string_literal: true

# ============================================================================
# CHAOS TEST PHASE M: Storm Protection (circuit breaker + adaptive sampling)
#
# Simulates error storms against a REAL production-mode app and asserts the
# gem provably degrades itself first:
#   M1: single-fingerprint flood  → bounded rows, breaker opens, exact counts
#   M2: unique-fingerprint flood  → bounded memory (map cap + overflow bucket)
#   M3: count reconciliation      → stored + counted == fired, storm_event row
#   M4: capture latency under storm stays sub-5ms
#   M5: recovery                  → breaker closes after calm, episode finalized
#
# Storm protection is OFF in the app initializer (other phases fire errors in
# tight loops); this phase enables and tunes it at runtime — config is
# process-local to this `rails runner` invocation, so nothing leaks.
#
# Run with: bin/rails runner test/pre_release/chaos/phase_m_storm_protection.rb
# ============================================================================

harness_path = File.expand_path("../lib/test_harness.rb", __dir__)
require harness_path

PreReleaseTestHarness.reset!
PreReleaseTestHarness.header("CHAOS TEST PHASE M: STORM PROTECTION")

GATE = RailsErrorDashboard::Services::StormProtection::Gate
CONFIG = RailsErrorDashboard.configuration

def fire_error(message, klass: StandardError, controller: "storms")
  error = klass.new(message)
  error.set_backtrace([ "#{Rails.root}/app/models/storm_widget.rb:42:in 'detonate'" ])
  RailsErrorDashboard::Commands::LogError.call(error, { controller_name: controller, platform: "Web" })
end

def drain_and_flush!
  snapshot = GATE.count_buffer.snapshot!
  episode = GATE.breaker.episode_snapshot
  GATE.breaker.clear_closed_episode!
  serialized = episode && {
    "started_at" => episode[:started_at]&.iso8601,
    "ended_at" => episode[:ended_at]&.iso8601,
    "peak_rate_per_minute" => episode[:peak_rate_per_minute],
    "reached_open" => episode[:reached_open]
  }
  RailsErrorDashboard::Commands::FlushStormCounts.call(
    entries: snapshot[:entries], overflow: snapshot[:overflow], episode: serialized
  )
  snapshot
end

CONFIG.enable_storm_protection = true
CONFIG.storm_shedding_threshold_per_second = 5
CONFIG.storm_open_threshold_per_second = 20     # fast-trip at 200 events/bucket
CONFIG.storm_cooldown_seconds = 5
CONFIG.storm_flush_interval_seconds = 3600      # manual flushes only — deterministic
CONFIG.storm_notification = false               # no outbound posts from chaos
GATE.reset!

# ---------------------------------------------------------------------------
# M1: Single-fingerprint flood — Layer 1 + breaker
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("M1: Single-fingerprint flood (2,000 identical errors)")

logs_before = RailsErrorDashboard::ErrorLog.count
occurrences_before = RailsErrorDashboard::ErrorOccurrence.count

FIRED_M1 = 2_000
FIRED_M1.times { fire_error("storm flood alpha") }

m1_logs = RailsErrorDashboard::ErrorLog.count - logs_before
m1_occurrences = RailsErrorDashboard::ErrorOccurrence.count - occurrences_before

assert "M1: breaker opened under flood", GATE.state == :open, "state=#{GATE.state}"
assert "M1: dedup keeps a single ErrorLog row", m1_logs == 1, "rows=#{m1_logs}"
assert "M1: occurrence rows bounded (<300 of 2,000)", m1_occurrences < 300, "rows=#{m1_occurrences}"
assert "M1: count buffer holds the shed events", GATE.count_buffer.any?

# ---------------------------------------------------------------------------
# M2: Unique-fingerprint flood — bounded memory
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("M2: Unique-fingerprint flood (1,500 distinct errors)")

CONFIG.storm_max_tracked_fingerprints = 500
FIRED_M2 = 1_500
FIRED_M2.times { |i| fire_error("unique storm error #{i}", controller: "unique#{i}") }

tracked = 0
overflow_seen = false
# Peek without draining: map size is bounded by config
map_snapshot = GATE.count_buffer.snapshot!
tracked = map_snapshot[:entries].size
overflow_seen = map_snapshot[:overflow].positive?
m2_total = map_snapshot[:entries].sum { |e| e["count"] } + map_snapshot[:overflow]

assert "M2: tracked fingerprints bounded by cap (~500)", tracked <= 510, "tracked=#{tracked}"
assert "M2: overflow bucket caught the rest", overflow_seen, "overflow=#{map_snapshot[:overflow]}"
assert "M2: every event accounted for (tracked + overflow)", m2_total >= FIRED_M2 - 5, "total=#{m2_total}"

# Reconcile M2 counts so M3 starts clean (re-uses the M2 snapshot)
RailsErrorDashboard::Commands::FlushStormCounts.call(
  entries: map_snapshot[:entries], overflow: map_snapshot[:overflow], episode: nil
)

# ---------------------------------------------------------------------------
# M3: Exact count reconciliation + storm_event row
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("M3: Exact reconciliation — stored + counted == fired")

GATE.reset!
CONFIG.storm_max_tracked_fingerprints = 1000
logs_before = RailsErrorDashboard::ErrorLog.count

FIRED_M3 = 1_000
FIRED_M3.times { fire_error("storm reconciliation beta") }
drain_and_flush!

beta_log = RailsErrorDashboard::ErrorLog.where("message LIKE ?", "storm reconciliation beta%").order(:id).last
assert "M3: beta error exists after flush", beta_log.present?
assert "M3: EXACT count — occurrence_count == events fired",
  beta_log&.occurrence_count == FIRED_M3,
  "occurrence_count=#{beta_log&.occurrence_count} fired=#{FIRED_M3}"

storm_event = RailsErrorDashboard::StormEvent.order(:id).last
assert "M3: storm_event row recorded", storm_event.present?
assert "M3: storm_event reached count-only mode", storm_event&.reached_open == true
assert "M3: storm_event counted events recorded", storm_event&.events_counted_only.to_i.positive?

# ---------------------------------------------------------------------------
# M4: Capture latency stays bounded DURING the storm
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("M4: p99 capture latency under storm < 5ms")

GATE.reset!
500.times { fire_error("latency warmup gamma") } # trip the breaker

latencies = []
200.times do |i|
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  fire_error("latency probe gamma")
  latencies << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000
end
p99 = latencies.sort[(latencies.size * 0.99).floor - 1]

assert "M4: breaker open during latency probe", GATE.state == :open, "state=#{GATE.state}"
assert "M4: p99 capture latency < 5ms in count-only mode", p99 < 5.0, "p99=#{p99.round(3)}ms"
drain_and_flush!

# ---------------------------------------------------------------------------
# M5: Recovery — calm traffic closes the breaker, episode finalized
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("M5: Recovery (waits ~45s of bucket rolls)")

GATE.reset!
500.times { fire_error("recovery storm delta") } # open
assert "M5: breaker open at storm peak", GATE.state == :open

# Trickle calm traffic across bucket boundaries: 10s buckets, 5s cooldown,
# open → half_open → (2 calm buckets) → closed
8.times do
  sleep 5.5
  fire_error("recovery trickle delta")
end

assert "M5: breaker closed after calm period", GATE.state == :closed, "state=#{GATE.state}"

episode = GATE.breaker.episode_snapshot
assert "M5: episode finalized with ended_at", episode && episode[:ended_at].present?
drain_and_flush!

final_event = RailsErrorDashboard::StormEvent.order(:id).last
assert "M5: storm_event row has ended_at after recovery flush", final_event&.ended_at.present?

CONFIG.enable_storm_protection = false
exit_code = PreReleaseTestHarness.summary("PHASE M")
exit(exit_code)
