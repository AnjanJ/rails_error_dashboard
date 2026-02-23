# frozen_string_literal: true

# ============================================================================
# CHAOS TEST PHASE J0: Seed Old Version Data
# Creates error records under the published v0.1.38 schema.
# Run BEFORE upgrading the gem to local version.
#
# Run with: bin/rails runner test/pre_release/chaos/phase_j0_seed_old_data.rb
# ============================================================================

harness_path = File.expand_path("../lib/test_harness.rb", __dir__)
require harness_path

PreReleaseTestHarness.reset!
PreReleaseTestHarness.header("CHAOS TEST PHASE J0: SEED OLD VERSION DATA")

# ---------------------------------------------------------------------------
# J0-1: Seed errors with various states
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("J0-1: Seeding errors under old schema")

# Seed a variety of error types
error_types = [
  [ RuntimeError, "old runtime error" ],
  [ NoMethodError, "undefined method 'old_method' for nil" ],
  [ ArgumentError, "wrong number of arguments" ],
  [ TypeError, "no implicit conversion" ],
  [ NameError, "uninitialized constant OldConstant" ]
]

seeded_ids = []

error_types.each do |klass, msg|
  full_msg = "#{msg} #{SecureRandom.hex(4)}"
  error = begin
    raise klass, full_msg
  rescue => e
    log_error_and_find(e, {
      controller_name: "old_controller",
      action_name: "index",
      platform: "Web"
    })
  end

  assert "J0: #{klass.name} seeded", error.persisted?
  seeded_ids << error.id
end

# Seed duplicates to test occurrence counting
3.times do
  begin
    raise RuntimeError, "repeated old error for dedup"
  rescue => e
    log_error_and_find(e, {
      controller_name: "old_controller",
      action_name: "show",
      platform: "Web"
    })
  end
end

dedup_check = RailsErrorDashboard::ErrorLog
  .where("message LIKE ?", "%repeated old error for dedup%")
  .first

assert "J0: dedup record exists", dedup_check.present?
assert "J0: dedup occurrence_count >= 3", dedup_check&.occurrence_count.to_i >= 3,
  "got #{dedup_check&.occurrence_count}"
puts ""

# ---------------------------------------------------------------------------
# J0-2: Resolve some errors
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("J0-2: Resolving some errors")

# Resolve the first 2 errors
seeded_ids.first(2).each do |id|
  RailsErrorDashboard::Commands::ResolveError.call(
    id,
    resolved_by_name: "OldGandalf",
    resolution_comment: "Fixed in old version"
  )
end

resolved_count = RailsErrorDashboard::ErrorLog.where(resolved: true).count
assert "J0: 2 errors resolved", resolved_count == 2,
  "got #{resolved_count}"
puts ""

# ---------------------------------------------------------------------------
# J0-3: Add comments
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("J0-3: Adding comments")

begin
  if defined?(RailsErrorDashboard::ErrorComment) && RailsErrorDashboard::ErrorComment.table_exists?
    seeded_ids.first(3).each_with_index do |id, i|
      RailsErrorDashboard::ErrorComment.create!(
        error_log_id: id,
        author_name: "Gandalf",
        body: "Old version comment ##{i + 1}"
      )
    end

    comment_count = RailsErrorDashboard::ErrorComment.count
    assert "J0: 3 comments created", comment_count == 3,
      "got #{comment_count}"
  else
    assert "J0: ErrorComment not available (OK for this version)", true
  end
rescue => e
  assert "J0: comment creation failed (#{e.class}: #{e.message})", false
end
puts ""

# ---------------------------------------------------------------------------
# J0-4: Snooze an error
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("J0-4: Snoozing an error")

begin
  if seeded_ids.length >= 4
    snooze_target = RailsErrorDashboard::ErrorLog.find(seeded_ids[3])
    if snooze_target.respond_to?(:status=) && RailsErrorDashboard::ErrorLog.column_names.include?("status")
      snooze_target.update!(status: "snoozed")
      assert "J0: error snoozed", snooze_target.reload.status == "snoozed"
    else
      assert "J0: status column not available (OK for old schema)", true
    end
  end
rescue => e
  assert "J0: snooze failed (#{e.class}: #{e.message})", false
end
puts ""

# ---------------------------------------------------------------------------
# J0-5: Record final state
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("J0-5: Final state before upgrade")

total = RailsErrorDashboard::ErrorLog.count
unresolved = RailsErrorDashboard::ErrorLog.where(resolved: false).count
resolved = RailsErrorDashboard::ErrorLog.where(resolved: true).count

assert "J0: total errors seeded", total >= 6, "got #{total}"
assert "J0: resolved count correct", resolved == 2, "got #{resolved}"
assert "J0: unresolved count correct", unresolved == total - 2,
  "got #{unresolved} (expected #{total - 2})"

puts ""
puts "  Seeded IDs: #{seeded_ids.inspect}"
puts "  Total: #{total}, Resolved: #{resolved}, Unresolved: #{unresolved}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
exit_code = PreReleaseTestHarness.summary("PHASE J0")
exit(exit_code)
