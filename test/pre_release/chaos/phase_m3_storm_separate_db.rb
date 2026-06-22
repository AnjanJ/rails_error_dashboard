# frozen_string_literal: true

# ============================================================================
# CHAOS PHASE M3: Storm protection under SEPARATE-DB routing
#
# StormEvent < ErrorLogsRecord, so storm_events + the reconciled ErrorLog rows
# must land in the SEPARATE error_dashboard database, not the host app's
# primary DB. Phase M only runs against a shared-DB app, so this path is
# otherwise untested.
#
#   M3a: a storm flood reconciles exactly onto an ErrorLog in the separate DB
#   M3b: the storm_events row is written to the separate DB connection
#   M3c: the host app's primary connection has NO storm tables (isolation)
#
# Run inside the built separate-db app:
#   bin/rails runner test/pre_release/chaos/phase_m3_storm_separate_db.rb
# ============================================================================

harness_path = File.expand_path("../lib/test_harness.rb", __dir__)
require harness_path

PreReleaseTestHarness.reset!
PreReleaseTestHarness.header("CHAOS PHASE M3: STORM PROTECTION — SEPARATE DB")

GATE = RailsErrorDashboard::Services::StormProtection::Gate
CONFIG = RailsErrorDashboard.configuration

def fire(message)
  error = StandardError.new(message)
  error.set_backtrace([ "#{Rails.root}/app/models/storm_widget.rb:42:in 'detonate'" ])
  RailsErrorDashboard::Commands::LogError.call(error, { controller_name: "m3", platform: "Web" })
end

def drain_and_flush!
  snapshot = GATE.count_buffer.snapshot!
  episode = GATE.breaker.episode_snapshot
  GATE.breaker.clear_closed_episode!
  serialized = episode && {
    "started_at" => episode[:started_at]&.iso8601, "ended_at" => episode[:ended_at]&.iso8601,
    "peak_rate_per_minute" => episode[:peak_rate_per_minute], "reached_open" => episode[:reached_open]
  }
  RailsErrorDashboard::Commands::FlushStormCounts.call(
    entries: snapshot[:entries], overflow: snapshot[:overflow], episode: serialized
  )
end

# Confirm we're actually on a separate connection (else this phase is moot).
red_db = RailsErrorDashboard::ErrorLogsRecord.connection_db_config.database.to_s
primary_db = ActiveRecord::Base.connection_db_config.database.to_s
PreReleaseTestHarness.section("error_dashboard DB: #{File.basename(red_db)} | primary DB: #{File.basename(primary_db)}")
assert "M3: error_dashboard uses a DIFFERENT database file than the host app",
  red_db != primary_db, "red=#{red_db} primary=#{primary_db}"

CONFIG.enable_storm_protection = true
CONFIG.storm_shedding_threshold_per_second = 5
CONFIG.storm_open_threshold_per_second = 20
CONFIG.storm_cooldown_seconds = 5
CONFIG.storm_flush_interval_seconds = 3600
CONFIG.storm_notification = false
GATE.reset!

# ---------------------------------------------------------------------------
# M3a + M3b: flood → reconcile exactly → storm_event in the separate DB
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("M3a/b: flood reconciles into the separate DB")

FIRED = 1_000
events_before = RailsErrorDashboard::StormEvent.count
FIRED.times { fire("separate-db storm flood") }
assert "M3a: breaker opened under flood", GATE.state == :open, "state=#{GATE.state}"
drain_and_flush!

log = RailsErrorDashboard::ErrorLog.where("message LIKE ?", "separate-db storm flood%").order(:id).last
assert "M3a: reconciled ErrorLog exists in the separate DB", log.present?
assert "M3a: EXACT reconciled count (1000)", log&.occurrence_count == FIRED,
  "occurrence_count=#{log&.occurrence_count}"

event = RailsErrorDashboard::StormEvent.order(:id).last
assert "M3b: storm_event row written", RailsErrorDashboard::StormEvent.count > events_before
assert "M3b: storm_event reached count-only mode", event&.reached_open == true
assert "M3b: storm_event counts recorded", event&.events_counted_only.to_i.positive?

# ---------------------------------------------------------------------------
# M3c: isolation — storm tables live ONLY on the error_dashboard connection
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("M3c: primary connection has no storm tables")

red_has = RailsErrorDashboard::ErrorLogsRecord.connection.table_exists?("rails_error_dashboard_storm_events")
primary_has = ActiveRecord::Base.connection.table_exists?("rails_error_dashboard_storm_events")
assert "M3c: storm_events exists on the error_dashboard connection", red_has
assert "M3c: storm_events does NOT exist on the host's primary connection", !primary_has,
  "primary unexpectedly has the storm_events table"

CONFIG.enable_storm_protection = false
exit_code = PreReleaseTestHarness.summary("PHASE M3")
exit(exit_code)
