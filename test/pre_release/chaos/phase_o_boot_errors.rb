# frozen_string_literal: true

# ============================================================================
# CHAOS TEST PHASE O: Boot Error Capture
# The orchestrator injected app/models/zeitwerk_bad.rb (defining the wrong
# constant), booted the app in production (eager_load = true) and expected it
# to die with Zeitwerk::NameError, then removed the file. This boot imports
# the crash file CrashCapture wrote at that exit. Verifies the row.
# Run with: bin/rails runner test/pre_release/chaos/phase_o_boot_errors.rb
# ============================================================================

harness_path = File.expand_path("../lib/test_harness.rb", __dir__)
require harness_path

PreReleaseTestHarness.reset!
PreReleaseTestHarness.header("CHAOS TEST PHASE O: BOOT ERROR CAPTURE")

PreReleaseTestHarness.section("O1: the failed boot was captured and imported")

row = RailsErrorDashboard::ErrorLog.where(platform: "boot_crash").order(id: :desc).first

assert "a boot_crash row exists", row.present?
if row
  assert "error_type is Zeitwerk::NameError", row.error_type == "Zeitwerk::NameError", row.error_type
  assert "message names the file and constant",
         row.message.to_s.match?(/expected file .*zeitwerk_bad\.rb to define constant ZeitwerkBad/), row.message.to_s[0, 160]
  assert "severity is critical", row.severity.to_s == "critical", row.severity.to_s

  info = JSON.parse(row.environment_info.to_s) rescue {}
  assert "environment_info.phase is boot", info["phase"] == "boot", info.inspect[0, 200]
  assert "boot detail names app/models/zeitwerk_bad.rb", info.dig("boot", "file") == "app/models/zeitwerk_bad.rb", info["boot"].inspect
  assert "boot detail names the constant", info.dig("boot", "constant") == "ZeitwerkBad", info["boot"].inspect
  assert "boot crash is unresolved", row.resolved == false
end

PreReleaseTestHarness.section("O2: the Boot Errors query lists it")

result = RailsErrorDashboard::Queries::BootErrors.call(30)
entry = result[:entries].find { |e| e[:error_type] == "Zeitwerk::NameError" }
assert "BootErrors query returns the crash", entry.present?
assert "query carries file and constant", entry && entry[:file] == "app/models/zeitwerk_bad.rb" && entry[:constant] == "ZeitwerkBad"
assert "no crash file left behind",
       Dir.glob(File.join(RailsErrorDashboard.configuration.crash_capture_path || Dir.tmpdir, "red_crash_*.json*")).none? { |f| File.read(f).include?("ZeitwerkBad") }

PreReleaseTestHarness.summary("phase_o_boot_errors")
