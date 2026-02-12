# frozen_string_literal: true

# ============================================================================
# CHAOS TEST PHASE C: Query & Analytics Verification
# Tests every Query object, analytics pipeline, and advanced analysis feature
# Run with: bin/rails runner test/pre_release/chaos/phase_c_queries.rb
# ============================================================================

harness_path = File.expand_path("../lib/test_harness.rb", __dir__)
require harness_path

PreReleaseTestHarness.reset!
PreReleaseTestHarness.header("CHAOS TEST PHASE C: QUERY & ANALYTICS VERIFICATION")

# ---------------------------------------------------------------------------
# Ensure we have seed data to test against
# ---------------------------------------------------------------------------
total_errors = RailsErrorDashboard::ErrorLog.count
puts "Found #{total_errors} errors in database"
if total_errors < 10
  puts "  Seeding test data for comprehensive testing..."
  # Create a variety of errors for testing
  error_types = [
    [ NoMethodError, "undefined method 'foo' for nil:NilClass" ],
    [ ArgumentError, "wrong number of arguments (given 2, expected 1)" ],
    [ RuntimeError, "something went wrong" ],
    [ TypeError, "no implicit conversion of String into Integer" ],
    [ NameError, "uninitialized constant Foo::Bar" ]
  ]
  platforms = %w[Web iOS Android API Background]

  20.times do |i|
    klass, msg = error_types[i % error_types.length]
    platform = platforms[i % platforms.length]
    begin
      raise klass, "#{msg} ##{SecureRandom.hex(4)}"
    rescue => e
      RailsErrorDashboard::Commands::LogError.call(e, {
        controller_name: "test_controller",
        action_name: "index",
        platform: platform,
        user_id: (i % 5 + 1).to_s
      })
    end
  end
  puts "  Seeded #{RailsErrorDashboard::ErrorLog.count} errors"
end
puts ""

# ---------------------------------------------------------------------------
# C1: DashboardStats query
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("C1: DashboardStats")

stats = assert_no_crash("DashboardStats.call") do
  RailsErrorDashboard::Queries::DashboardStats.call
end

if stats
  assert "returns hash", stats.is_a?(Hash)
  assert "has unresolved", stats.key?(:unresolved)
  assert "has total_today", stats.key?(:total_today)

  app = RailsErrorDashboard::Application.first
  if app
    assert_no_crash("DashboardStats with app filter #{app.name}") do
      RailsErrorDashboard::Queries::DashboardStats.call(application_id: app.id)
    end
  end
end
puts ""

# ---------------------------------------------------------------------------
# C2: ErrorsList query with all filter combinations
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("C2: ErrorsList with various filters")

assert_no_crash("ErrorsList no filters") { RailsErrorDashboard::Queries::ErrorsList.call({}).count }

filters = {
  error_type: RailsErrorDashboard::ErrorLog.distinct.pluck(:error_type).first,
  platform: RailsErrorDashboard::ErrorLog.distinct.pluck(:platform).compact.first,
  severity: "critical",
  status: "new",
  timeframe: "24h",
  unresolved: "true",
  hide_snoozed: "true",
  sort_by: "occurred_at",
  sort_direction: "desc",
  search: "error"
}

filters.each do |key, value|
  next unless value
  assert_no_crash("ErrorsList filter #{key}=#{value.to_s.truncate(30)}") do
    RailsErrorDashboard::Queries::ErrorsList.call({ key => value })
  end
end

%w[1h 24h 7d 30d 90d all].each do |tf|
  assert_no_crash("ErrorsList timeframe=#{tf}") do
    RailsErrorDashboard::Queries::ErrorsList.call({ timeframe: tf })
  end
end

%w[occurred_at occurrence_count error_type priority_score].each do |sort|
  %w[asc desc].each do |dir|
    assert_no_crash("ErrorsList sort #{sort} #{dir}") do
      RailsErrorDashboard::Queries::ErrorsList.call({ sort_by: sort, sort_direction: dir })
    end
  end
end

assert_no_crash("ErrorsList combined filters") do
  RailsErrorDashboard::Queries::ErrorsList.call({
    severity: "high",
    timeframe: "30d",
    unresolved: "true",
    sort_by: "priority_score",
    sort_direction: "desc"
  })
end

assert_no_crash("ErrorsList frequency=high") do
  RailsErrorDashboard::Queries::ErrorsList.call({ frequency: "high" })
end
assert_no_crash("ErrorsList frequency=medium") do
  RailsErrorDashboard::Queries::ErrorsList.call({ frequency: "medium" })
end
assert_no_crash("ErrorsList frequency=low") do
  RailsErrorDashboard::Queries::ErrorsList.call({ frequency: "low" })
end
puts ""

# ---------------------------------------------------------------------------
# C3: AnalyticsStats query
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("C3: AnalyticsStats")

[ 7, 14, 30, 60, 90 ].each do |days|
  analytics = assert_no_crash("AnalyticsStats(#{days} days)") do
    RailsErrorDashboard::Queries::AnalyticsStats.call(days)
  end

  if analytics && days == 30
    assert "has error_stats", analytics.key?(:error_stats)
    assert "has errors_over_time", analytics.key?(:errors_over_time)
    assert "has errors_by_type", analytics.key?(:errors_by_type)
    assert "has errors_by_platform", analytics.key?(:errors_by_platform)
    assert "has errors_by_hour", analytics.key?(:errors_by_hour)
    assert "has top_users", analytics.key?(:top_users)
    assert "has resolution_rate", analytics.key?(:resolution_rate)
  end
end
puts ""

# ---------------------------------------------------------------------------
# C4: FilterOptions query
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("C4: FilterOptions")

opts = assert_no_crash("FilterOptions.call") do
  RailsErrorDashboard::Queries::FilterOptions.call
end

if opts
  assert "has error_types", opts.key?(:error_types)
  assert "has platforms", opts.key?(:platforms)
  assert "has assignees", opts.key?(:assignees)
end
puts ""

# ---------------------------------------------------------------------------
# C5: CriticalAlerts query
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("C5: CriticalAlerts")

alerts = assert_no_crash("CriticalAlerts.call") do
  RailsErrorDashboard::Queries::CriticalAlerts.call
end

if alerts
  assert "returns enumerable", alerts.respond_to?(:each)
end
puts ""

# ---------------------------------------------------------------------------
# C6: RecurringIssues query
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("C6: RecurringIssues")

recurring = assert_no_crash("RecurringIssues.call(30)") do
  RailsErrorDashboard::Queries::RecurringIssues.call(30)
end

if recurring
  assert "returns hash", recurring.is_a?(Hash)
end
puts ""

# ---------------------------------------------------------------------------
# C7: MttrStats query
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("C7: MttrStats")

mttr = assert_no_crash("MttrStats.call(30)") do
  RailsErrorDashboard::Queries::MttrStats.call(30)
end

if mttr
  assert "returns hash", mttr.is_a?(Hash)
  assert "has overall_mttr", mttr.key?(:overall_mttr)
  assert "has mttr_by_platform", mttr.key?(:mttr_by_platform)
end
puts ""

# ---------------------------------------------------------------------------
# C8: PlatformComparison query (if enabled)
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("C8: PlatformComparison")

if RailsErrorDashboard.configuration.enable_platform_comparison
  [ 7, 14, 30 ].each do |days|
    assert_no_crash("PlatformComparison(#{days} days)") do
      pc = RailsErrorDashboard::Queries::PlatformComparison.new(days: days)
      pc.error_rate_by_platform
      pc.severity_distribution_by_platform
      pc.resolution_time_by_platform
      pc.top_errors_by_platform
      pc.platform_stability_scores
      pc.cross_platform_errors
      pc.daily_trend_by_platform
      pc.platform_health_summary
    end
  end
else
  puts "  SKIP: Platform comparison disabled"
end
puts ""

# ---------------------------------------------------------------------------
# C9: ErrorCorrelation query (if enabled)
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("C9: ErrorCorrelation")

if RailsErrorDashboard.configuration.enable_error_correlation
  [ 7, 14, 30 ].each do |days|
    assert_no_crash("ErrorCorrelation(#{days} days)") do
      ec = RailsErrorDashboard::Queries::ErrorCorrelation.new(days: days)
      ec.errors_by_version
      ec.errors_by_git_sha
      ec.problematic_releases
      ec.multi_error_users(min_error_types: 2)
      ec.time_correlated_errors
      ec.period_comparison
      ec.platform_specific_errors
    end
  end
else
  puts "  SKIP: Error correlation disabled"
end
puts ""

# ---------------------------------------------------------------------------
# C10: Error model analysis methods
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("C10: Error model analysis methods")

error = RailsErrorDashboard::ErrorLog.where.not(resolved: true).first || RailsErrorDashboard::ErrorLog.first

if error
  assert_no_crash("error.severity") { error.severity }
  assert_no_crash("error.critical?") { error.critical? }
  assert_no_crash("error.recent?") { error.recent? }
  assert_no_crash("error.stale?") { error.stale? }
  assert_no_crash("error.priority_label") { error.priority_label }
  assert_no_crash("error.priority_color") { error.priority_color }
  assert_no_crash("error.priority_emoji") { error.priority_emoji }
  assert_no_crash("error.status_badge_color") { error.status_badge_color }
  assert_no_crash("error.backtrace_frames") { error.backtrace_frames }
  assert_no_crash("error.related_errors") { error.related_errors(limit: 5) }

  if RailsErrorDashboard.configuration.enable_similar_errors
    assert_no_crash("error.similar_errors") { error.similar_errors }
  end

  if RailsErrorDashboard.configuration.enable_co_occurring_errors
    assert_no_crash("error.co_occurring_errors") { error.co_occurring_errors }
  end

  if RailsErrorDashboard.configuration.enable_error_cascades
    assert_no_crash("error.error_cascades") { error.error_cascades }
  end

  if error.respond_to?(:baselines)
    assert_no_crash("error.baselines") { error.baselines }
  end

  if error.respond_to?(:baseline_anomaly)
    assert_no_crash("error.baseline_anomaly") { error.baseline_anomaly }
  end

  if RailsErrorDashboard.configuration.enable_occurrence_patterns && error.respond_to?(:occurrence_pattern)
    assert_no_crash("error.occurrence_pattern") { error.occurrence_pattern }
  end

  if error.respond_to?(:error_bursts)
    assert_no_crash("error.error_bursts") { error.error_bursts }
  end

  assert_no_crash("error.can_transition_to?('resolved')") { error.can_transition_to?("resolved") }
  assert_no_crash("ErrorLog.priority_options (class method)") { RailsErrorDashboard::ErrorLog.priority_options }
else
  puts "  SKIP: No errors in database"
end
puts ""

# ---------------------------------------------------------------------------
# C11: UpsertBaseline command
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("C11: UpsertBaseline command")

assert_no_crash("UpsertBaseline creates baseline") do
  baseline = RailsErrorDashboard::Commands::UpsertBaseline.call(
    error_type: "ChaosTestError",
    platform: "Web",
    baseline_type: "daily",
    period_start: 12.weeks.ago.beginning_of_day,
    period_end: Time.current.beginning_of_day,
    stats: { mean: 5.0, std_dev: 1.5, percentile_95: 8.0, percentile_99: 10.0 },
    count: 42,
    sample_size: 7
  )
  assert "baseline persisted", baseline.persisted?
  assert "baseline mean correct", baseline.mean == 5.0
end

assert_no_crash("UpsertBaseline updates existing") do
  baseline = RailsErrorDashboard::Commands::UpsertBaseline.call(
    error_type: "ChaosTestError",
    platform: "Web",
    baseline_type: "daily",
    period_start: 12.weeks.ago.beginning_of_day,
    period_end: Time.current.beginning_of_day,
    stats: { mean: 10.0, std_dev: 3.0 },
    count: 100,
    sample_size: 14
  )
  assert "baseline mean updated", baseline.mean == 10.0
  assert "baseline count updated", baseline.count == 100
end
puts ""

# ---------------------------------------------------------------------------
# C12: Application model
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("C12: Application queries")

assert_no_crash("Application.ordered_by_name") do
  apps = RailsErrorDashboard::Application.ordered_by_name
  assert "returns relation", apps.respond_to?(:each)
end

app = RailsErrorDashboard::Application.first
if app
  assert_no_crash("Application#error_logs") { app.error_logs.count }
  assert_no_crash("Application#name present") { assert "has name", app.name.present? }
end
puts ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
exit_code = PreReleaseTestHarness.summary("PHASE C")
exit(exit_code)
