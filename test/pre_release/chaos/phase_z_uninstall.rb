# frozen_string_literal: true

# ============================================================================
# CHAOS TEST PHASE Z: Uninstall drops every table (DESTRUCTIVE: run it LAST)
# Runs the real rails_error_dashboard:db:drop task in a production-mode app,
# on the error database (separate or shared), and checks that every RED table
# is gone while the host app's own tables are not. It must be the app's final
# phase: nothing can run after the tables are dropped.
# Run with: bin/rails runner test/pre_release/chaos/phase_z_uninstall.rb
# ============================================================================

harness_path = File.expand_path("../lib/test_harness.rb", __dir__)
require harness_path
require "rake"
require "stringio"

PreReleaseTestHarness.reset!
PreReleaseTestHarness.header("CHAOS TEST PHASE Z: UNINSTALL")

red_table = /\Arails_error_dashboard_/
config = RailsErrorDashboard.configuration
error_db = RailsErrorDashboard::ErrorLogsRecord.connection
primary = ActiveRecord::Base.connection

# ---------------------------------------------------------------------------
# Z1: Before the drop, with a row behind every foreign key
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("Z1: before the drop")

if config.use_separate_database
  assert "Z1: RED is on the configured error database",
    error_db.pool.db_config.name == config.database.to_s, error_db.pool.db_config.name
end

# SQLite only refuses to drop a referenced table while rows reference it, so
# make sure every foreign key has a row behind it.
assert_no_crash("Z1: seed a row behind every foreign key") do
  app = RailsErrorDashboard::Application.first || RailsErrorDashboard::Application.create!(name: "ChaosUninstall")
  parent, child = 2.times.map do |i|
    RailsErrorDashboard::ErrorLog.create!(
      application: app, error_type: "ChaosUninstallError#{i}", message: "phase z #{i}",
      occurred_at: Time.current, platform: "API"
    )
  end
  RailsErrorDashboard::ErrorOccurrence.create!(error_log: parent, occurred_at: Time.current)
  RailsErrorDashboard::ErrorComment.create!(error_log: parent, author_name: "chaos", body: "phase z")
  RailsErrorDashboard::CascadePattern.create!(parent_error: parent, child_error: child, frequency: 1)
  RailsErrorDashboard::DiagnosticDump.create!(application: app, dump_data: "{}", captured_at: Time.current)
end

red_before = error_db.tables.grep(red_table)
host_before = primary.tables.grep_v(red_table).sort
assert "Z1: RED tables exist (#{red_before.size})", red_before.size >= 13, red_before.join(", ")

# ---------------------------------------------------------------------------
# Z2: The real task, confirmed
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("Z2: rails_error_dashboard:db:drop")

Rails.application.load_tasks
output = StringIO.new
original_stdin = $stdin
original_stdout = $stdout
begin
  $stdin = StringIO.new("DELETE ALL DATA\n")
  $stdout = output
  Rake::Task["rails_error_dashboard:db:drop"].invoke
rescue => e
  output.puts "RAISED #{e.class}: #{e.message}"
ensure
  $stdin = original_stdin
  $stdout = original_stdout
end

assert "Z2: the task reports every table dropped",
  output.string.include?("Successfully dropped #{red_before.size} table(s)"),
  output.string.lines.last(6).join

# ---------------------------------------------------------------------------
# Z3: After the drop
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("Z3: after the drop")

left = error_db.tables.grep(red_table)
assert "Z3: no RED table remains on the error database", left.empty?, left.join(", ")
assert "Z3: no RED table on the primary database either", primary.tables.grep(red_table).empty?
assert "Z3: the host app's own tables are untouched", primary.tables.grep_v(red_table).sort == host_before

puts ""

exit_code = PreReleaseTestHarness.summary("PHASE Z")
exit(exit_code)
