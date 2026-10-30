# frozen_string_literal: true

require "rails_helper"

# boot_crash and crash_capture live in the platform column, but they say how an
# error was captured, not where it ran.
RSpec.describe "Crash sources aren't platforms" do
  let(:crash_sources) { RailsErrorDashboard::Services::CrashCapture::PLATFORMS }
  let(:queries) { RailsErrorDashboard::Queries }

  before do
    [ "iOS", "API", nil, "boot_crash", "crash_capture" ].each_with_index do |platform, index|
      group = create(:error_log, platform: platform, error_type: "Error#{index}", app_version: "1.0.0", occurred_at: 1.hour.ago,
        resolved: true, resolved_at: Time.current)
      create(:error_occurrence, error_log: group, occurred_at: 1.hour.ago)
      # The model fills in "API", so a NULL takes writing it directly. Rows from
      # before that default have one.
      group.update_column(:platform, nil) if platform.nil?
    end
  end

  def expect_no_crash_source(platforms)
    expect(platforms & crash_sources).to be_empty
  end

  it "knows the two crash sources (small-fixes-0-18/REQ-1)" do
    expect(crash_sources).to contain_exactly("boot_crash", "crash_capture")
  end

  it "keeps them out of the filter dropdown (small-fixes-0-18/REQ-1)" do
    platforms = queries::FilterOptions.call[:platforms]

    expect_no_crash_source(platforms)
    expect(platforms).to include("iOS", "API")
  end

  it "keeps them out of the correlation breakdowns (small-fixes-0-18/REQ-1)" do
    correlation = queries::ErrorCorrelation.new(days: 30)

    expect_no_crash_source(correlation.errors_by_version.values.flat_map { |row| row[:platforms] })
    expect_no_crash_source(correlation.platform_specific_errors.keys)
    expect(correlation.platform_specific_errors.keys).to include("iOS")
  end

  it "keeps them out of resolution times (small-fixes-0-18/REQ-1)" do
    by_platform = queries::MttrStats.call(30)[:mttr_by_platform]

    expect_no_crash_source(by_platform.keys)
    expect(by_platform.keys).to include("iOS")
  end

  it "keeps them off the platform comparison page, on every part of it (small-fixes-0-18/REQ-1)" do
    comparison = queries::PlatformComparison.new(days: 30)

    [
      comparison.error_rate_by_platform, comparison.severity_distribution_by_platform,
      comparison.resolution_time_by_platform, comparison.top_errors_by_platform,
      comparison.platform_stability_scores, comparison.daily_trend_by_platform,
      comparison.platform_health_summary
    ].each { |breakdown| expect_no_crash_source(breakdown.keys) }

    expect(comparison.error_rate_by_platform.keys).to include("iOS")
    expect(comparison.platform_health_summary.keys).to include("iOS")
  end

  it "doesn't count a crash source as a second platform for an error (small-fixes-0-18/REQ-1)" do
    [ "iOS", "API", "boot_crash" ].each do |platform|
      group = create(:error_log, platform: platform, error_type: "SharedError", occurred_at: 1.hour.ago)
      create(:error_occurrence, error_log: group, occurred_at: 1.hour.ago)
    end

    shared = queries::PlatformComparison.new(days: 30).cross_platform_errors.find { |row| row[:error_type] == "SharedError" }

    expect(shared[:platforms]).to contain_exactly("API", "iOS")
  end

  it "keeps them out of the dashboard's breakdown, and NULL stays (small-fixes-0-18/REQ-1)" do
    by_platform = queries::DashboardStats.call[:by_platform]

    expect_no_crash_source(by_platform.keys)
    expect(by_platform).to include(nil => 1, "iOS" => 1)
  end

  it "keeps them out of the analytics breakdown (small-fixes-0-18/REQ-1)" do
    by_platform = queries::AnalyticsStats.call(30)[:errors_by_platform]

    expect_no_crash_source(by_platform.keys)
    expect(by_platform.keys).to include("iOS")
  end

  it "doesn't look for anomalies in them (small-fixes-0-18/REQ-1)" do
    pairs = queries::BaselineStats.send(:current_counts_by_pair).keys

    expect_no_crash_source(pairs.map(&:last))
    expect(pairs.map(&:last)).to include("iOS")
  end

  it "decides the live list's Platform column by the index's rule (small-fixes-0-18/REQ-1)" do
    errors = RailsErrorDashboard::ErrorLog
    errors.where.not(platform: crash_sources).or(errors.where(platform: nil)).update_all(platform: "iOS")
    allow(Rails.cache).to receive(:fetch).and_yield

    expect(queries::FilterOptions.call[:platforms].size).to eq(1)
    expect(RailsErrorDashboard::Services::ErrorBroadcaster.column_visibility(nil)[:platform]).to be(false)
  end

  it "keeps a row with no platform in the scope, which NOT IN alone would drop (small-fixes-0-18/REQ-1)" do
    expect(RailsErrorDashboard::ErrorLog.platform_listed.pluck(:platform)).to contain_exactly("iOS", "API", nil)
  end

  it "still lists crash errors in the error list (small-fixes-0-18/REQ-2)" do
    expect(queries::ErrorsList.call(unresolved: false).pluck(:platform)).to include("boot_crash", "crash_capture")
  end

  it "still shows boot crashes on Boot Errors (small-fixes-0-18/REQ-2)" do
    expect(queries::BootErrors.call(30).to_s).to include("Error3")
  end
end
