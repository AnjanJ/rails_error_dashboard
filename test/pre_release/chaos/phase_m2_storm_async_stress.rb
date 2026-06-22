# frozen_string_literal: true

# ============================================================================
# CHAOS PHASE M2: Storm protection under the REAL async/job path
#
# Phase M validates storm logic via in-process calls with manual flushes and a
# 3600s flush interval (deterministic). It deliberately does NOT exercise:
#   M2a: the gate sitting BEFORE the async enqueue branch — :count_only events
#        must enqueue NOTHING (the central async claim of storm protection)
#   M2b: automatic interval-based flush enqueuing → StormFlushJob → reconcile
#        through the app's real ActiveJob adapter
#   M2c: ignored exceptions filtered before the gate enqueue nothing
#   M2d: a calm error (breaker closed) still enqueues the normal logging job
#
# Run inside a built async test app (queue_adapter = :inline):
#   bin/rails runner test/pre_release/chaos/phase_m2_storm_async_stress.rb
# ============================================================================

harness_path = File.expand_path("../lib/test_harness.rb", __dir__)
require harness_path

PreReleaseTestHarness.reset!
PreReleaseTestHarness.header("CHAOS PHASE M2: STORM PROTECTION — ASYNC/JOB PATH")

GATE = RailsErrorDashboard::Services::StormProtection::Gate
CONFIG = RailsErrorDashboard.configuration

def fire(message, klass: StandardError, controller: "m2")
  error = klass.new(message)
  error.set_backtrace([ "#{Rails.root}/app/models/storm_widget.rb:42:in 'detonate'" ])
  RailsErrorDashboard::Commands::LogError.call(error, { controller_name: controller, platform: "Web" })
end

# Count enqueued jobs by class, adapter-agnostically, by subscribing to the
# enqueue.active_job notification — fires for every successful enqueue
# regardless of which adapter (async/solid_queue/sidekiq/inline) is in use.
ENQUEUED = Hash.new(0)
ActiveSupport::Notifications.subscribe("enqueue.active_job") do |*, payload|
  job = payload[:job]
  ENQUEUED[job.class.name] += 1 if job
end
adapter = ActiveJob::Base.queue_adapter.class.name
PreReleaseTestHarness.section("Adapter in use: #{adapter}; async_logging=#{CONFIG.async_logging}")

CONFIG.enable_storm_protection = true
CONFIG.storm_shedding_threshold_per_second = 5
CONFIG.storm_open_threshold_per_second = 20
CONFIG.storm_cooldown_seconds = 5
CONFIG.storm_flush_interval_seconds = 3600
CONFIG.storm_notification = false
GATE.reset!

# ---------------------------------------------------------------------------
# M2a: :count_only events must NOT enqueue a logging job (gate before async)
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("M2a: count-only events enqueue no logging job")

ENQUEUED.clear
# Trip the breaker hard, then fire a big batch — once open, all are count_only
800.times { fire("async storm omega") }
state_after = GATE.state
logging_jobs = ENQUEUED["RailsErrorDashboard::AsyncErrorLoggingJob"]

assert "M2a: breaker open after flood", state_after == :open, "state=#{state_after}"
# In count-only mode the gate returns before the async branch. Some early
# events (before the breaker opened) may enqueue; assert the count is far
# below the number fired — i.e. the vast majority enqueued nothing.
assert "M2a: count-only sheds the async enqueue (jobs << fired)",
  logging_jobs < 200, "logging_jobs=#{logging_jobs} of 800 fired"
assert "M2a: counts are buffered in memory instead", GATE.count_buffer.any?

# ---------------------------------------------------------------------------
# M2b: automatic interval flush enqueues StormFlushJob, which reconciles
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("M2b: interval flush enqueues + reconciles via real job")

GATE.reset!
ENQUEUED.clear
CONFIG.storm_flush_interval_seconds = 0 # every admit past the first triggers a flush check

# Use inline execution so the enqueued StormFlushJob actually runs and writes.
prior_adapter = ActiveJob::Base.queue_adapter
ActiveJob::Base.queue_adapter = :inline
begin
  1_000.times { fire("async storm psi") }
ensure
  ActiveJob::Base.queue_adapter = prior_adapter
end

flush_jobs = ENQUEUED["RailsErrorDashboard::StormFlushJob"]
psi_log = RailsErrorDashboard::ErrorLog.where("message LIKE ?", "async storm psi%").order(:id).last

assert "M2b: a StormFlushJob was enqueued by the interval", flush_jobs.positive?, "flush_jobs=#{flush_jobs}"
assert "M2b: psi error row exists after inline flush", psi_log.present?
# Reconcile any residual buffered counts not yet flushed, then assert exactness.
snapshot = GATE.count_buffer.snapshot!
episode = GATE.breaker.episode_snapshot
serialized = episode && {
  "started_at" => episode[:started_at]&.iso8601, "ended_at" => episode[:ended_at]&.iso8601,
  "peak_rate_per_minute" => episode[:peak_rate_per_minute], "reached_open" => episode[:reached_open]
}
RailsErrorDashboard::Commands::FlushStormCounts.call(
  entries: snapshot[:entries], overflow: snapshot[:overflow], episode: serialized
)
psi_log.reload
assert "M2b: EXACT count after interval+residual reconcile (1000)",
  psi_log.occurrence_count == 1_000, "occurrence_count=#{psi_log.occurrence_count}"

# ---------------------------------------------------------------------------
# M2c: ignored exceptions are filtered BEFORE the gate — never counted/enqueued
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("M2c: ignored exceptions bypass gate (no count, no job)")

class StormIgnoredError < StandardError; end
GATE.reset!
ENQUEUED.clear
CONFIG.ignored_exceptions = [ "StormIgnoredError" ]
GATE.count_buffer.snapshot! # drain to zero
300.times { fire("ignored storm chi", klass: StormIgnoredError) }
after = GATE.count_buffer.snapshot!
ignored_logging_jobs = ENQUEUED["RailsErrorDashboard::AsyncErrorLoggingJob"]

assert "M2c: ignored exceptions are not counted by the gate",
  (after[:entries].sum { |e| e["count"] } + after[:overflow]) == 0,
  "buffered=#{after[:entries].sum { |e| e['count'] } + after[:overflow]}"
assert "M2c: ignored exceptions enqueue no logging job", ignored_logging_jobs == 0, "jobs=#{ignored_logging_jobs}"
CONFIG.ignored_exceptions = []

# ---------------------------------------------------------------------------
# M2d: a calm error (breaker closed) still enqueues the normal logging job
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("M2d: calm error still flows through the normal async path")

GATE.reset!
ENQUEUED.clear
fire("calm single error tau")
calm_state = GATE.state
calm_jobs = ENQUEUED["RailsErrorDashboard::AsyncErrorLoggingJob"]

assert "M2d: breaker closed for a single calm error", calm_state == :closed, "state=#{calm_state}"
if CONFIG.async_logging
  assert "M2d: calm error enqueues the normal logging job", calm_jobs == 1, "jobs=#{calm_jobs}"
else
  PreReleaseTestHarness.section("M2d: async_logging off — sync path, no enqueue expected (skipped enqueue assert)")
end

CONFIG.enable_storm_protection = false
exit_code = PreReleaseTestHarness.summary("PHASE M2")
exit(exit_code)
