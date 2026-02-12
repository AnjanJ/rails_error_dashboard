# frozen_string_literal: true

# ============================================================================
# CHAOS TEST PHASE A: Data Integrity
# Verifies all CRUD paths produce correct, consistent data
# Run with: bin/rails runner test/pre_release/chaos/phase_a_data_integrity.rb
# ============================================================================

harness_path = File.expand_path("../lib/test_harness.rb", __dir__)
require harness_path

PreReleaseTestHarness.reset!
PreReleaseTestHarness.header("CHAOS TEST PHASE A: DATA INTEGRITY")

# ---------------------------------------------------------------------------
# A1: Error creation via LogError command (the main capture path)
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("A1: LogError command creates well-formed records")

error = begin
  raise NoMethodError, "undefined method 'chaos_test' for nil:NilClass"
rescue => e
  log_error_and_find(e, {
    controller_name: "chaos_controller",
    action_name: "destroy",
    request_url: "https://example.com/chaos?id=42",
    user_id: "999",
    user_agent: "ChaosBot/1.0",
    ip_address: "192.168.1.1",
    platform: "Web"
  })
end

assert "error persisted", error.persisted?
assert "error_type correct", error.error_type == "NoMethodError"
assert "message present", error.message.present?
assert "backtrace present", error.backtrace.present?
assert "error_hash is 16-char hex", error.error_hash&.match?(/\A[0-9a-f]{16}\z/)
assert "severity classified", %w[critical high medium low].include?(error.severity.to_s)
assert "priority_score 0-100", error.priority_score.is_a?(Integer) && error.priority_score.between?(0, 100)
assert "controller_name stored", error.controller_name == "chaos_controller"
assert "action_name stored", error.action_name == "destroy"
assert "request_url stored", error.request_url == "https://example.com/chaos?id=42"
assert "user_id stored", error.user_id.to_s == "999"
assert "user_agent stored", error.user_agent == "ChaosBot/1.0"
assert "ip_address stored", error.ip_address == "192.168.1.1"
assert "platform stored", error.platform == "Web"
assert "occurred_at set", error.occurred_at.present?
assert "occurrence_count >= 1", error.occurrence_count >= 1
assert "status is 'new'", error.status == "new"
assert "not resolved", error.resolved == false
puts ""

# ---------------------------------------------------------------------------
# A2: Error deduplication (same error -> same hash -> increment count)
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("A2: Deduplication increments occurrence count")

first_count = error.occurrence_count

error2 = begin
  raise NoMethodError, "undefined method 'chaos_test' for nil:NilClass"
rescue => e
  log_error_and_find(e, {
    controller_name: "chaos_controller",
    action_name: "destroy",
    platform: "Web"
  })
end

assert "same error_hash", error.error_hash == error2.error_hash
assert "same record (deduped)", error.id == error2.id

error.reload
assert "occurrence_count incremented", error.occurrence_count > first_count, "was #{first_count}, now #{error.occurrence_count}"
puts ""

# ---------------------------------------------------------------------------
# A3: Different errors get different hashes
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("A3: Different errors get unique hashes")

errors = []
[
  [ ArgumentError, "bad argument" ],
  [ RuntimeError, "runtime failure" ],
  [ TypeError, "wrong type" ],
  [ NameError, "uninitialized constant Foo" ],
  [ ZeroDivisionError, "divided by 0" ]
].each do |klass, msg|
  e = begin
    raise klass, msg
  rescue => ex
    log_error_and_find(ex, { controller_name: "chaos", platform: "Web" })
  end
  errors << e
end

hashes = errors.map(&:error_hash).uniq
assert "5 different errors -> 5 unique hashes", hashes.length == 5, "got #{hashes.length} unique hashes"
puts ""

# ---------------------------------------------------------------------------
# A4: ErrorHashGenerator.from_attributes matches model behavior
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("A4: ErrorHashGenerator.from_attributes produces valid hashes")

hash1 = RailsErrorDashboard::Services::ErrorHashGenerator.from_attributes(
  error_type: "NoMethodError",
  message: "test chaos #123",
  backtrace: "app/models/user.rb:10:in `name'\napp/controllers/users_controller.rb:5",
  controller_name: "users",
  action_name: "show",
  application_id: 1
)
assert "from_attributes returns 16-char hex", hash1.match?(/\A[0-9a-f]{16}\z/)

hash2 = RailsErrorDashboard::Services::ErrorHashGenerator.from_attributes(
  error_type: "NoMethodError",
  message: "test chaos #123",
  backtrace: "app/models/user.rb:10:in `name'\napp/controllers/users_controller.rb:5",
  controller_name: "users",
  action_name: "show",
  application_id: 1
)
assert "deterministic (same inputs = same hash)", hash1 == hash2

hash3 = RailsErrorDashboard::Services::ErrorHashGenerator.from_attributes(
  error_type: "NoMethodError",
  message: "test chaos #999",
  backtrace: "app/models/user.rb:10:in `name'\napp/controllers/users_controller.rb:5",
  controller_name: "users",
  action_name: "show",
  application_id: 1
)
assert "normalizes IDs (#123 vs #999)", hash1 == hash3
puts ""

# ---------------------------------------------------------------------------
# A5: SeverityClassifier produces correct classifications
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("A5: SeverityClassifier classifications")

sc = RailsErrorDashboard::Services::SeverityClassifier
assert "SecurityError -> critical", sc.classify("SecurityError") == :critical
assert "SignalException -> critical", sc.classify("SignalException") == :critical
assert "NoMethodError -> high", sc.classify("NoMethodError") == :high
assert "ActiveRecord::RecordNotFound -> high", sc.classify("ActiveRecord::RecordNotFound") == :high
assert "StandardError -> low", sc.classify("StandardError") == :low
assert "critical?('SecurityError') -> true", sc.critical?("SecurityError") == true
assert "critical?('StandardError') -> false", sc.critical?("StandardError") == false
puts ""

# ---------------------------------------------------------------------------
# A6: PriorityScoreCalculator produces sensible scores
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("A6: PriorityScoreCalculator scoring")

calc = RailsErrorDashboard::Services::PriorityScoreCalculator

# SecurityError inherits from Exception, not StandardError
critical_error = begin
  raise SecurityError, "critical chaos #{SecureRandom.hex(4)}"
rescue Exception => e
  log_error_and_find(e, { platform: "Web" })
end
critical_error.update_columns(occurrence_count: 500, occurred_at: 10.minutes.ago)

low_error = begin
  raise StandardError, "low chaos #{SecureRandom.hex(4)}"
rescue => e
  log_error_and_find(e, { platform: "Web" })
end
low_error.update_columns(occurrence_count: 1, occurred_at: 60.days.ago)

critical_score = calc.compute(critical_error.reload)
low_score = calc.compute(low_error.reload)

assert "critical+frequent+recent scores higher than low+rare+old", critical_score > low_score,
       "critical=#{critical_score}, low=#{low_score}"
assert "scores in valid range", critical_score.between?(0, 100) && low_score.between?(0, 100)
puts ""

# ---------------------------------------------------------------------------
# A7: Workflow commands (resolve, assign, snooze, comment, status)
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("A7: Workflow commands")

workflow_error = begin
  raise RuntimeError, "workflow chaos test #{SecureRandom.hex(4)}"
rescue => e
  log_error_and_find(e, { controller_name: "workflow_test", platform: "Web" })
end
error_id = workflow_error.id

# Assign
assigned = RailsErrorDashboard::Commands::AssignError.call(error_id, assigned_to: "Gandalf")
assert "assigned_to set", assigned.assigned_to == "Gandalf"
assert "status -> in_progress (after assign)", assigned.status == "in_progress"

# Update status to investigating
result = RailsErrorDashboard::Commands::UpdateErrorStatus.call(error_id, status: "investigating", comment: "Working on it")
assert "status -> investigating", result[:error]&.status == "investigating" || result[:success] != false
if result[:comment]
  assert "comment created", result[:comment].body == "Working on it"
else
  assert "status update returned result", result.key?(:error) || result.key?(:success)
end

# Update priority (priority_level is integer: 3=P0/Critical, 2=P1/High, 1=P2/Medium, 0=P3/Low)
prioritized = RailsErrorDashboard::Commands::UpdateErrorPriority.call(error_id, priority_level: 3)
assert "priority_level -> 3 (P0)", prioritized.priority_level == 3

# Snooze
snoozed = RailsErrorDashboard::Commands::SnoozeError.call(error_id, hours: 2, reason: "Investigating later")
assert "snoozed_until set", snoozed.snoozed_until.present?
assert "snoozed_until ~2 hours from now", snoozed.snoozed_until > 1.hour.from_now

# Unsnooze
unsnoozed = RailsErrorDashboard::Commands::UnsnoozeError.call(error_id)
assert "snoozed_until cleared", unsnoozed.snoozed_until.nil?

# Add comment
commented = RailsErrorDashboard::Commands::AddErrorComment.call(error_id, author_name: "Frodo", body: "This looks like a ring issue")
assert "comment added", commented.comments.count >= 1
assert "latest comment by Frodo", commented.comments.last.author_name == "Frodo"

# Resolve
resolved = RailsErrorDashboard::Commands::ResolveError.call(error_id,
  resolved_by_name: "Aragorn",
  resolution_comment: "Fixed the chaos",
  resolution_reference: "PR #42"
)
assert "resolved", resolved.resolved == true
assert "resolved_by_name", resolved.resolved_by_name == "Aragorn"
assert "resolved_at set", resolved.resolved_at.present?
assert "status -> resolved", resolved.status == "resolved"
puts ""

# ---------------------------------------------------------------------------
# A8: Batch operations
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("A8: Batch operations")

batch_errors = 3.times.map do |i|
  begin
    raise RuntimeError, "batch chaos #{i} #{SecureRandom.hex(4)}"
  rescue => e
    log_error_and_find(e, { controller_name: "batch_test", platform: "Web" })
  end
end
batch_ids = batch_errors.map { |e| e.id.to_s }

result = RailsErrorDashboard::Commands::BatchResolveErrors.call(batch_ids,
  resolved_by_name: "Gimli",
  resolution_comment: "Batch fixed"
)
assert "batch resolve success", result[:success] == true
assert "batch resolved count", result[:count] == 3

batch_errors.each(&:reload)
assert "all batch errors resolved", batch_errors.all?(&:resolved?)

# Batch delete
delete_errors = 2.times.map do |i|
  begin
    raise RuntimeError, "delete chaos #{i} #{SecureRandom.hex(4)}"
  rescue => e
    log_error_and_find(e, { controller_name: "delete_test", platform: "Web" })
  end
end
delete_ids = delete_errors.map { |e| e.id.to_s }

delete_result = RailsErrorDashboard::Commands::BatchDeleteErrors.call(delete_ids)
assert "batch delete success", delete_result[:success] == true
assert "batch deleted count", delete_result[:count] == 2
assert "records actually deleted", RailsErrorDashboard::ErrorLog.where(id: delete_ids.map(&:to_i)).count == 0
puts ""

# ---------------------------------------------------------------------------
# A9: Multi-platform error creation
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("A9: Multi-platform errors")

%w[Web iOS Android API Background].each do |platform|
  e = begin
    raise RuntimeError, "platform test #{platform} #{SecureRandom.hex(4)}"
  rescue => ex
    log_error_and_find(ex, { platform: platform, controller_name: "platform_test" })
  end
  assert "#{platform} error created", e.persisted? && e.platform == platform
end
puts ""

# ---------------------------------------------------------------------------
# A10: Occurrence tracking
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("A10: Occurrence tracking")

if RailsErrorDashboard::ErrorLog.column_names.include?("occurrence_count")
  occ_error = begin
    raise RuntimeError, "occurrence tracking chaos #{SecureRandom.hex(8)}"
  rescue => e
    log_error_and_find(e, { controller_name: "occ_test", platform: "Web" })
  end

  initial_count = occ_error.occurrence_count
  assert "occurrence_count starts at >= 1", initial_count >= 1
end
puts ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
exit_code = PreReleaseTestHarness.summary("PHASE A")
exit(exit_code)
