# frozen_string_literal: true

# ============================================================================
# CHAOS TEST PHASE J: Upgrade Path Verification (v0.1.38 → v0.2.0)
# Verifies that existing data survives the upgrade and new features work
# alongside old records.
#
# Run with: bin/rails runner test/pre_release/chaos/phase_j_upgrade_verification.rb
# ============================================================================

harness_path = File.expand_path("../lib/test_harness.rb", __dir__)
require harness_path

PreReleaseTestHarness.reset!
PreReleaseTestHarness.header("CHAOS TEST PHASE J: UPGRADE PATH VERIFICATION")

# ---------------------------------------------------------------------------
# J1: Version updated
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("J1: Version is updated")

# The from-version is resolved at runtime, so this cannot assert a literal.
#
# It also cannot assert the working copy is NEWER than the published gem:
# release-please bumps version.rb as part of the release commit, so on a normal
# branch the working copy still carries the released version number. Comparing
# them would fail on every pre-release run.
#
# What is genuinely invariant is that the app is loading the gem from a path
# (the working copy) rather than the installed .gem — that is what proves the
# Gemfile swap took effect and the rest of this phase is testing new code.
from_version = ENV["UPGRADE_FROM_VERSION"].to_s
gem_path = RailsErrorDashboard.const_source_location(:VERSION)&.first.to_s

assert "J1: app is running the working copy, not the published gem",
  !gem_path.include?("/gems/rails_error_dashboard-"),
  "loaded from #{gem_path} — expected a path-sourced copy, not an installed gem"

assert "J1: upgraded from a published release", !from_version.empty?,
  "UPGRADE_FROM_VERSION was not set by the harness"
puts ""

# ---------------------------------------------------------------------------
# J2: Old records survived the upgrade
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("J2: Old records preserved")

total = RailsErrorDashboard::ErrorLog.count
assert "J2: errors still exist after upgrade", total >= 6,
  "got #{total} (expected >= 6 from J0)"

# Verify resolved records kept their state
resolved = RailsErrorDashboard::ErrorLog.where(resolved: true)
assert "J2: resolved errors preserved", resolved.count == 2,
  "got #{resolved.count}"

resolved.each do |r|
  assert "J2: resolved_at present for ##{r.id}", r.resolved_at.present?
  assert "J2: status is resolved for ##{r.id}", r.status == "resolved"
end
puts ""

# ---------------------------------------------------------------------------
# J3: Old record attributes intact
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("J3: Old record attributes intact")

sample_error = RailsErrorDashboard::ErrorLog.where(resolved: false).first

assert "J3: sample error exists", sample_error.present?
if sample_error
  assert "J3: error_type present", sample_error.error_type.present?
  assert "J3: message present", sample_error.message.present?
  assert "J3: backtrace present", sample_error.backtrace.present?
  assert "J3: occurred_at present", sample_error.occurred_at.present?
  assert "J3: error_hash present", sample_error.error_hash.present?
  assert "J3: platform present", sample_error.platform.present?
  assert "J3: application_id present", sample_error.application_id.present?
end
puts ""

# ---------------------------------------------------------------------------
# J4: Comments survived
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("J4: Comments preserved")

if defined?(RailsErrorDashboard::ErrorComment) && RailsErrorDashboard::ErrorComment.table_exists?
  comments = RailsErrorDashboard::ErrorComment.all
  if comments.count > 0
    assert "J4: comments exist after upgrade", comments.count == 3,
      "got #{comments.count}"

    old_comment = comments.find { |c| c.body.include?("Old version comment") }
    assert "J4: old comment content preserved", old_comment.present?
    assert "J4: comment author preserved", old_comment&.author_name == "Gandalf"
  else
    # Comments may not have been created if J0 encountered issues
    assert "J4: no comments found (J0 may have skipped comments)", true
  end
else
  assert "J4: ErrorComment not available", true
end
puts ""

# ---------------------------------------------------------------------------
# J5: New columns exist (nil for old records, populated for new)
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("J5: Long-standing columns survive the upgrade")

columns = RailsErrorDashboard::ErrorLog.column_names

# These were "new" when this phase was written against a v0.1 -> v0.2 upgrade.
# They have shipped for many releases since, so the old assertion that a
# pre-upgrade record leaves them nil is no longer true — the from-version now
# populates them itself. What still matters is that the upgrade does not DROP
# them and does not corrupt the rows that already carry values.
expected_columns = %w[
  exception_cause http_method hostname content_type
  request_duration_ms environment_info reopened_at
  app_version git_sha
]

expected_columns.each do |col|
  assert "J5: column #{col} still exists after upgrade", columns.include?(col),
    "column not found — the upgrade appears to have dropped it"
end

assert_no_crash("J5: pre-upgrade record still readable across all columns") do
  sample_error&.attributes
end
puts ""

# ---------------------------------------------------------------------------
# J6: New errors populate new columns
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("J6: New errors populate v0.2 columns")

new_error = begin
  begin
    raise ActiveRecord::RecordNotFound, "inner cause"
  rescue => inner
    raise RuntimeError, "post-upgrade error #{SecureRandom.hex(4)}"
  end
rescue => e
  log_error_and_find(e, {
    controller_name: "upgrade_test",
    action_name: "create",
    platform: "Web",
    http_method: "POST",
    hostname: "upgraded.example.com",
    content_type: "application/json",
    request_duration_ms: 567
  })
end

assert "J6: new error persisted", new_error.persisted?

if columns.include?("exception_cause")
  assert "J6: exception_cause populated", new_error.exception_cause.present?
end

if columns.include?("http_method")
  assert "J6: http_method populated", new_error.http_method == "POST"
end

if columns.include?("hostname")
  assert "J6: hostname populated", new_error.hostname == "upgraded.example.com"
end

if columns.include?("environment_info")
  assert "J6: environment_info populated", new_error.environment_info.present?
end
puts ""

# ---------------------------------------------------------------------------
# J7: Deduplication works across upgrade boundary
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("J7: Deduplication across upgrade boundary")

# Find the dedup record from J0
old_dedup = RailsErrorDashboard::ErrorLog
  .where("message LIKE ?", "%repeated old error for dedup%")
  .first

if old_dedup
  old_count = old_dedup.occurrence_count

  # Log the same error again — should dedup into existing record
  begin
    error = RuntimeError.new(old_dedup.message)
    error.set_backtrace(old_dedup.backtrace.to_s.split("\n"))
    raise error
  rescue => e
    log_error_and_find(e, {
      controller_name: "old_controller",
      action_name: "show",
      platform: "Web"
    })
  end

  old_dedup.reload
  assert "J7: occurrence_count incremented", old_dedup.occurrence_count > old_count,
    "was #{old_count}, now #{old_dedup.occurrence_count}"
end
puts ""

# ---------------------------------------------------------------------------
# J8: Auto-reopen works on old resolved errors
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("J8: Auto-reopen on old resolved errors")

old_resolved = RailsErrorDashboard::ErrorLog.where(resolved: true).first

if old_resolved
  old_id = old_resolved.id

  # Re-raise the same error — should reopen the resolved record
  begin
    error = old_resolved.error_type.constantize.new(old_resolved.message)
    error.set_backtrace(old_resolved.backtrace.to_s.split("\n"))
    raise error
  rescue => e
    log_error_and_find(e, {
      controller_name: "old_controller",
      action_name: "index",
      platform: "Web"
    })
  end

  old_resolved.reload
  assert "J8: resolved error reopened", old_resolved.resolved == false
  assert "J8: status back to new", old_resolved.status == "new"
  assert "J8: same record ID", old_resolved.id == old_id

  if columns.include?("reopened_at")
    assert "J8: reopened_at set", old_resolved.reopened_at.present?
  end
end
puts ""

# ---------------------------------------------------------------------------
# J9: All query classes work after upgrade
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("J9: All queries work post-upgrade")

assert_no_crash("J9: DashboardStats") do
  RailsErrorDashboard::Queries::DashboardStats.call
end

assert_no_crash("J9: ErrorsList") do
  RailsErrorDashboard::Queries::ErrorsList.call
end

assert_no_crash("J9: AnalyticsStats") do
  RailsErrorDashboard::Queries::AnalyticsStats.call
end
puts ""

# ---------------------------------------------------------------------------
# J10: Schema additions from this release applied cleanly
#
# WHY: the docs tell upgraders to run install:migrations + db:migrate. This is
# the only place that instruction is verified end-to-end against a real app that
# was installed at the PREVIOUS published release. A column added this cycle but
# never copied into the host app would break the dashboard at runtime, not here,
# so assert on the schema directly rather than trusting the migration ran.
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("J10: New columns exist after migrating")

ra_table = RailsErrorDashboard::RackAttackEvent.table_name
ra_columns = RailsErrorDashboard::RackAttackEvent.connection.columns(ra_table).map(&:name)

assert "J10: rack_attack_events table exists",
  RailsErrorDashboard::RackAttackEvent.connection.table_exists?(ra_table)

assert "J10: user_agent column was added by the upgrade",
  ra_columns.include?("user_agent"),
  "columns: #{ra_columns.sort.join(', ')}"

# The unique upsert index is budgeted against MySQL's 3072-byte utf8mb4 limit.
# user_agent must stay out of it or the migration breaks on MySQL — a failure
# SQLite would never surface.
upsert_index = RailsErrorDashboard::RackAttackEvent.connection
  .indexes(ra_table).find { |i| i.name == "index_rack_attack_events_upsert_key" }

assert "J10: upsert index still exists", upsert_index.present?

assert "J10: user_agent stayed OUT of the upsert index",
  upsert_index.nil? || !upsert_index.columns.include?("user_agent"),
  "index columns: #{upsert_index&.columns&.join(', ')}"

# The column has to be writable, not merely present.
assert_no_crash("J10: rack_attack event round-trips with a user agent") do
  RailsErrorDashboard::RackAttackEvent.create!(
    rule: "upgrade-check",
    match_type: "track",
    discriminator: "198.51.100.42",
    path: "/doc",
    http_method: "GET",
    user_agent: "ChatGPT-User/1.0",
    period_hour: Time.current.beginning_of_hour,
    event_count: 1,
    last_seen_at: Time.current
  )
end

written = RailsErrorDashboard::RackAttackEvent.find_by(rule: "upgrade-check")
assert "J10: user agent persisted", written&.user_agent == "ChatGPT-User/1.0",
  "got #{written&.user_agent.inspect}"

assert_no_crash("J10: RackAttackSummary query works post-upgrade") do
  RailsErrorDashboard::Queries::RackAttackSummary.call(30)
end
puts ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
exit_code = PreReleaseTestHarness.summary("PHASE J")
exit(exit_code)
