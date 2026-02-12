# frozen_string_literal: true

# ============================================================================
# CHAOS TEST PHASE B: Edge Cases & Malformed Inputs
# Tests nil, empty, huge, and bizarre inputs through every service
# Run with: bin/rails runner test/pre_release/chaos/phase_b_edge_cases.rb
# ============================================================================

harness_path = File.expand_path("../lib/test_harness.rb", __dir__)
require harness_path

PreReleaseTestHarness.reset!
PreReleaseTestHarness.header("CHAOS TEST PHASE B: EDGE CASES & MALFORMED INPUTS")

# ---------------------------------------------------------------------------
# B1: LogError with minimal/missing context
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("B1: LogError with minimal context")

assert_no_crash("LogError with empty context hash") do
  begin
    raise RuntimeError, "minimal context"
  rescue => e
    result = log_error_and_find(e, {})
    assert "persisted with empty context", result.persisted?
  end
end

assert_no_crash("LogError with nil context values") do
  begin
    raise RuntimeError, "nil context values"
  rescue => e
    result = log_error_and_find(e, {
      controller_name: nil,
      action_name: nil,
      request_url: nil,
      user_id: nil,
      user_agent: nil,
      ip_address: nil,
      platform: nil
    })
    assert "persisted with nil context", result.persisted?
  end
end

assert_no_crash("LogError with empty string context values") do
  begin
    raise RuntimeError, "empty string context"
  rescue => e
    result = log_error_and_find(e, {
      controller_name: "",
      action_name: "",
      request_url: "",
      user_id: "",
      platform: ""
    })
    assert "persisted with empty strings", result.persisted?
  end
end
puts ""

# ---------------------------------------------------------------------------
# B2: LogError with huge payloads
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("B2: LogError with huge payloads")

assert_no_crash("LogError with very long message") do
  begin
    raise RuntimeError, "A" * 10_000
  rescue => e
    result = log_error_and_find(e, { platform: "Web" })
    assert "persisted with 10K message", result.persisted?
  end
end

assert_no_crash("LogError with huge backtrace") do
  begin
    error = RuntimeError.new("huge backtrace test")
    error.set_backtrace(500.times.map { |i| "app/models/deep#{i}.rb:#{i}:in `method_#{i}'" })
    raise error
  rescue => e
    result = log_error_and_find(e, { platform: "Web" })
    assert "persisted with 500-line backtrace", result.persisted?
    lines = result.backtrace.to_s.split("\n")
    assert "backtrace truncated to <= 51 lines (50 + footer)", lines.length <= 51, "got #{lines.length} lines"
  end
end

assert_no_crash("LogError with unicode message") do
  begin
    raise RuntimeError, "Unicod\u00e9 error: \u65e5\u672c\u8a9e\u30c6\u30b9\u30c8 \u{1f525}\u{1f4a5}\u{1f680} \u00d1o\u00f1o"
  rescue => e
    result = log_error_and_find(e, { platform: "Web" })
    assert "persisted with unicode", result.persisted?
    assert "message contains unicode", result.message.include?("Unicod")
  end
end

assert_no_crash("LogError with very long controller/action names") do
  begin
    raise RuntimeError, "long names test"
  rescue => e
    result = log_error_and_find(e, {
      controller_name: "a" * 500,
      action_name: "b" * 500,
      platform: "Web"
    })
    assert "persisted with long names", result.persisted?
  end
end
puts ""

# ---------------------------------------------------------------------------
# B3: SeverityClassifier edge cases
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("B3: SeverityClassifier edge cases")

sc = RailsErrorDashboard::Services::SeverityClassifier

assert_no_crash("classify(nil)") { assert "nil -> :low", sc.classify(nil) == :low }
assert_no_crash("classify('')") { assert "'' -> :low", sc.classify("") == :low }
assert_no_crash("classify(123)") { sc.classify(123) }
assert_no_crash("classify with whitespace") { sc.classify("  NoMethodError  ") }
assert_no_crash("critical?(nil)") { assert "critical?(nil) -> false", sc.critical?(nil) == false }
assert_no_crash("critical?('')") { assert "critical?('') -> false", sc.critical?("") == false }
assert_no_crash("classify very long string") { sc.classify("A" * 10_000) }
puts ""

# ---------------------------------------------------------------------------
# B4: PriorityScoreCalculator edge cases
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("B4: PriorityScoreCalculator edge cases")

calc = RailsErrorDashboard::Services::PriorityScoreCalculator

assert_no_crash("frequency_to_score(nil)") { assert "nil -> 10", calc.frequency_to_score(nil) == 10 }
assert_no_crash("frequency_to_score(0)") { assert "0 -> 10", calc.frequency_to_score(0) == 10 }
assert_no_crash("frequency_to_score(-100)") { assert "-100 -> 10", calc.frequency_to_score(-100) == 10 }
assert_no_crash("frequency_to_score(Float::INFINITY)") { calc.frequency_to_score(Float::INFINITY) }
assert_no_crash("frequency_to_score(Float::NAN)") { calc.frequency_to_score(Float::NAN) }
assert_no_crash("frequency_to_score('abc')") { calc.frequency_to_score("abc") }
assert_no_crash("frequency_to_score(999_999_999)") do
  score = calc.frequency_to_score(999_999_999)
  assert "huge count -> 100", score == 100
end
assert_no_crash("severity_to_score(nil)") { assert "nil -> 10", calc.severity_to_score(nil) == 10 }
assert_no_crash("severity_to_score(:bogus)") { assert ":bogus -> 10", calc.severity_to_score(:bogus) == 10 }
assert_no_crash("recency_to_score(nil)") { assert "nil -> 10", calc.recency_to_score(nil) == 10 }
assert_no_crash("recency_to_score(Time.at(0))") do
  score = calc.recency_to_score(Time.at(0))
  assert "epoch -> 10", score == 10
end
assert_no_crash("recency_to_score(1000.years.from_now)") do
  score = calc.recency_to_score(1000.years.from_now)
  assert "far future -> 100", score == 100
end
puts ""

# ---------------------------------------------------------------------------
# B5: ErrorHashGenerator edge cases
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("B5: ErrorHashGenerator edge cases")

ehg = RailsErrorDashboard::Services::ErrorHashGenerator

assert_no_crash("from_attributes all nil") do
  h = ehg.from_attributes(error_type: nil, message: nil, backtrace: nil, application_id: nil)
  assert "all nil -> valid hash", h.match?(/\A[0-9a-f]{16}\z/)
end

assert_no_crash("from_attributes all empty strings") do
  h = ehg.from_attributes(error_type: "", message: "", backtrace: "", controller_name: "", action_name: "")
  assert "all empty -> valid hash", h.match?(/\A[0-9a-f]{16}\z/)
end

assert_no_crash("from_attributes huge message") do
  h = ehg.from_attributes(error_type: "RuntimeError", message: "X" * 100_000)
  assert "huge message -> valid hash", h.match?(/\A[0-9a-f]{16}\z/)
end

assert_no_crash("from_attributes unicode") do
  h = ehg.from_attributes(error_type: "RuntimeError", message: "\u65e5\u672c\u8a9e\u30a8\u30e9\u30fc \u{1f525}")
  assert "unicode -> valid hash", h.match?(/\A[0-9a-f]{16}\z/)
end

assert_no_crash(".call with exception that has nil message") do
  e = RuntimeError.new(nil)
  e.set_backtrace([ "app/test.rb:1" ])
  h = ehg.call(e)
  assert ".call nil message -> valid hash", h.match?(/\A[0-9a-f]{16}\z/)
end

assert_no_crash(".call with exception that has empty backtrace") do
  e = RuntimeError.new("test")
  e.set_backtrace([])
  h = ehg.call(e)
  assert ".call empty backtrace -> valid hash", h.match?(/\A[0-9a-f]{16}\z/)
end
puts ""

# ---------------------------------------------------------------------------
# B6: ErrorBroadcaster edge cases
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("B6: ErrorBroadcaster edge cases")

eb = RailsErrorDashboard::Services::ErrorBroadcaster

assert_no_crash("broadcast_new(nil)") { eb.broadcast_new(nil) }
assert_no_crash("broadcast_update(nil)") { eb.broadcast_update(nil) }
assert_no_crash("broadcast_stats") { eb.broadcast_stats }
assert_no_crash("available? check") { eb.available? }
puts ""

# ---------------------------------------------------------------------------
# B7: AnalyticsCacheManager edge cases
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("B7: AnalyticsCacheManager edge cases")

acm = RailsErrorDashboard::Services::AnalyticsCacheManager

assert_no_crash("clear cache") { acm.clear }
assert_no_crash("clear cache twice rapidly") { acm.clear; acm.clear }
puts ""

# ---------------------------------------------------------------------------
# B8: Workflow commands with bad inputs
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("B8: Workflow commands with bad inputs")

test_error = begin
  raise RuntimeError, "workflow edge case #{SecureRandom.hex(4)}"
rescue => e
  log_error_and_find(e, { platform: "Web" })
end
eid = test_error.id

assert_no_crash("AssignError with empty string") do
  RailsErrorDashboard::Commands::AssignError.call(eid, assigned_to: "")
end

assert_no_crash("AssignError with very long name") do
  RailsErrorDashboard::Commands::AssignError.call(eid, assigned_to: "X" * 500)
end

assert_no_crash("UpdateErrorPriority with invalid level") do
  begin
    RailsErrorDashboard::Commands::UpdateErrorPriority.call(eid, priority_level: "P99")
  rescue => e
    assert "invalid priority raises validation", e.is_a?(StandardError)
  end
end

snooze_error = begin
  raise RuntimeError, "snooze edge case #{SecureRandom.hex(4)}"
rescue => e
  log_error_and_find(e, { platform: "Web" })
end
snooze_eid = snooze_error.id

assert_no_crash("SnoozeError with 0 hours") do
  RailsErrorDashboard::Commands::SnoozeError.call(snooze_eid, hours: 0, reason: "zero hours")
end

assert_no_crash("SnoozeError with negative hours") do
  RailsErrorDashboard::Commands::SnoozeError.call(snooze_eid, hours: -1, reason: "negative")
end

assert_no_crash("AddErrorComment with empty body raises validation") do
  begin
    RailsErrorDashboard::Commands::AddErrorComment.call(eid, author_name: "Tester", body: "")
    assert "should have raised", false
  rescue ActiveRecord::RecordInvalid => e
    assert "empty body rejected by validation", e.message.include?("Body")
  end
end

assert_no_crash("AddErrorComment with nil author raises validation") do
  begin
    RailsErrorDashboard::Commands::AddErrorComment.call(eid, author_name: nil, body: "test comment")
    assert "should have raised", false
  rescue ActiveRecord::RecordInvalid => e
    assert "nil author rejected by validation", e.message.include?("Author")
  end
end

assert_no_crash("AddErrorComment with unicode") do
  RailsErrorDashboard::Commands::AddErrorComment.call(eid, author_name: "\u65e5\u672c\u8a9e", body: "\u30c6\u30b9\u30c8 \u{1f525}\u{1f4a5}")
end

assert_no_crash("UpdateErrorStatus with invalid status") do
  begin
    RailsErrorDashboard::Commands::UpdateErrorStatus.call(eid, status: "bogus_status")
  rescue => e
    assert "invalid status raises error", e.is_a?(StandardError)
  end
end

assert_no_crash("BatchResolveErrors with empty array") do
  result = RailsErrorDashboard::Commands::BatchResolveErrors.call([])
  assert "empty batch returns result", result.is_a?(Hash)
end

assert_no_crash("BatchResolveErrors with non-existent IDs") do
  RailsErrorDashboard::Commands::BatchResolveErrors.call([ "999999", "999998" ])
end

assert_no_crash("BatchDeleteErrors with empty array") do
  result = RailsErrorDashboard::Commands::BatchDeleteErrors.call([])
  assert "empty delete returns result", result.is_a?(Hash)
end
puts ""

# ---------------------------------------------------------------------------
# B9: Query edge cases (empty database scenarios)
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("B9: Query edge cases")

assert_no_crash("DashboardStats with non-existent app") do
  stats = RailsErrorDashboard::Queries::DashboardStats.call(application_id: 999999)
  assert "stats returns hash", stats.is_a?(Hash)
end

assert_no_crash("AnalyticsStats with 0 days") do
  RailsErrorDashboard::Queries::AnalyticsStats.call(0)
end

assert_no_crash("AnalyticsStats with negative days") do
  RailsErrorDashboard::Queries::AnalyticsStats.call(-1)
end

assert_no_crash("ErrorsList with all filters") do
  RailsErrorDashboard::Queries::ErrorsList.call(
    error_type: "NonExistentError",
    platform: "NonExistentPlatform",
    severity: "critical",
    status: "new",
    search: "zzzzzzzzz",
    timeframe: "24h",
    sort_by: "occurred_at",
    sort_direction: "asc"
  )
end

assert_no_crash("FilterOptions with non-existent app") do
  RailsErrorDashboard::Queries::FilterOptions.call(application_id: 999999)
end

if RailsErrorDashboard.configuration.enable_platform_comparison
  assert_no_crash("PlatformComparison with 0 days") do
    RailsErrorDashboard::Queries::PlatformComparison.new(days: 0).error_rate_by_platform
  end
end

if RailsErrorDashboard.configuration.enable_error_correlation
  assert_no_crash("ErrorCorrelation with 0 days") do
    c = RailsErrorDashboard::Queries::ErrorCorrelation.new(days: 0)
    c.errors_by_version
    c.time_correlated_errors
    c.multi_error_users
  end
end

assert_no_crash("RecurringIssues with 0 days") do
  RailsErrorDashboard::Queries::RecurringIssues.call(0)
end

assert_no_crash("MttrStats with 0 days") do
  RailsErrorDashboard::Queries::MttrStats.call(0)
end
puts ""

# ---------------------------------------------------------------------------
# B10: Rapid-fire error creation (stress test)
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("B10: Rapid-fire error creation (50 errors in quick succession)")

start_time = Time.now
50.times do |i|
  begin
    raise RuntimeError, "rapid fire #{i} #{SecureRandom.hex(4)}"
  rescue => e
    RailsErrorDashboard::Commands::LogError.call(e, {
      controller_name: "stress_test",
      platform: %w[Web iOS Android API Background].sample
    })
  end
end
elapsed = Time.now - start_time
assert "50 errors created in < 10 seconds", elapsed < 10, "took #{elapsed.round(2)}s"
assert "50 errors created in < 5 seconds", elapsed < 5, "took #{elapsed.round(2)}s"
puts ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
exit_code = PreReleaseTestHarness.summary("PHASE B")
exit(exit_code)
