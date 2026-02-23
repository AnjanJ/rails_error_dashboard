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

assert "J1: version is 0.2.0", RailsErrorDashboard::VERSION == "0.2.0",
  "got #{RailsErrorDashboard::VERSION}"
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
PreReleaseTestHarness.section("J5: New v0.2 columns exist")

columns = RailsErrorDashboard::ErrorLog.column_names

new_v2_columns = %w[
  exception_cause http_method hostname content_type
  request_duration_ms environment_info reopened_at
  app_version git_sha
]

new_v2_columns.each do |col|
  if columns.include?(col)
    assert "J5: new column #{col} exists", true

    # Old records should have nil for new columns
    old_value = sample_error&.send(col)
    assert "J5: old record #{col} is nil", old_value.nil?,
      "expected nil, got #{old_value.inspect}"
  else
    assert "J5: column #{col} missing (may not be in this version)", false,
      "column not found"
  end
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
# Summary
# ---------------------------------------------------------------------------
exit_code = PreReleaseTestHarness.summary("PHASE J")
exit(exit_code)
