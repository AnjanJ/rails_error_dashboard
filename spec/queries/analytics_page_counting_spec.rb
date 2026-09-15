# frozen_string_literal: true

require "rails_helper"

# The Analytics page and the Overview must report the same totals for the same
# window. 0.12.0 corrected DashboardStats and UserImpactSummary to count EVENTS
# (sum of occurrence_count) but left AnalyticsStats counting GROUPS, so the two
# pages disagreed whenever any error recurred -- the same window reporting
# different numbers depending which page you opened.
#
# Two counting units, kept distinct on purpose:
#
#   events   sum(occurrence_count) -- exact, and includes storm count-only
#            events, which never create occurrence rows
#   groups   count of ErrorLog rows -- the unit for resolved/unresolved, since
#            a group is the thing that gets resolved and an event cannot be
RSpec.describe "analytics page counting units" do
  let(:analytics) { RailsErrorDashboard::Queries::AnalyticsStats }
  let(:dashboard) { RailsErrorDashboard::Queries::DashboardStats }
  let(:logs) { RailsErrorDashboard::ErrorLog }
  let!(:application) { create(:application, name: "Counting app") }

  before { Rails.cache.clear }
  after { Rails.cache.clear }

  # One group, five events -- the shape that made the two pages disagree.
  def recurring_group(count:, occurred_at: 2.hours.ago, **attrs)
    create(:error_log, application: application, occurrence_count: count, occurred_at: occurred_at, **attrs)
  end

  describe "agreement with the Overview" do
    before do
      recurring_group(count: 5, error_type: "RecurringError", platform: "Web")
      recurring_group(count: 3, error_type: "OtherError", platform: "iOS")
    end

    it "reports events, not groups, as the total" do
      expect(logs.count).to eq(2)
      expect(analytics.call(30, application_id: application.id)[:error_stats][:total]).to eq(8)
    end

    it "reports the same total the Overview reports for the same window" do
      overview_today = dashboard.call(application_id: application.id)[:total_today]
      page_total = analytics.call(30, application_id: application.id)[:error_stats][:total]

      expect(page_total).to eq(overview_today)
      expect(page_total).to eq(8)
    end

    it "still exposes the group count, which is a different number" do
      stats = analytics.call(30, application_id: application.id)[:error_stats]

      expect(stats[:total_groups]).to eq(2)
      expect(stats[:total]).to eq(8)
    end
  end

  describe "every volume dimension counts events" do
    before do
      recurring_group(count: 5, error_type: "RecurringError", platform: "Web", environment: "production")
      recurring_group(count: 3, error_type: "OtherError", platform: "iOS", environment: "staging")
    end

    let(:result) { analytics.call(30, application_id: application.id) }

    it "counts by_type in events" do
      expect(result[:error_stats][:by_type]).to eq({ "RecurringError" => 5, "OtherError" => 3 })
    end

    it "counts by_day in events" do
      expect(result[:error_stats][:by_day].values.sum).to eq(8)
    end

    it "counts errors_over_time in events" do
      expect(result[:errors_over_time].values.sum).to eq(8)
    end

    it "counts errors_by_type in events" do
      expect(result[:errors_by_type]).to eq({ "RecurringError" => 5, "OtherError" => 3 })
    end

    it "counts errors_by_platform in events" do
      expect(result[:errors_by_platform]).to eq({ "Web" => 5, "iOS" => 3 })
    end

    it "counts errors_by_environment in events" do
      expect(result[:errors_by_environment]).to eq({ "production" => 5, "staging" => 3 })
    end

    it "counts errors_by_hour in events" do
      expect(result[:errors_by_hour].values.sum).to eq(8)
    end

    it "counts mobile and api errors in events" do
      expect(result[:mobile_errors]).to eq(3)
      expect(result[:api_errors]).to eq(0)
    end

    # The chart's slices must add up to the headline figure, or the
    # percentage bars the view computes from them stop summing to 100%.
    it "keeps every breakdown summing to the headline total" do
      total = result[:error_stats][:total]

      expect(result[:errors_by_platform].values.sum).to eq(total)
      expect(result[:error_stats][:by_type].values.sum).to eq(total)
      expect(result[:errors_over_time].values.sum).to eq(total)
    end
  end

  # Volume is events, but resolving happens to a group. Dividing resolved
  # groups by total events would collapse the rate toward zero the moment any
  # error recurred; the Overview divides groups by groups, and so must this.
  describe "resolution rate" do
    it "is groups over groups, unaffected by how often an error recurred" do
      recurring_group(count: 100, resolved: true, status: "resolved")
      recurring_group(count: 1, resolved: false)

      expect(analytics.call(30, application_id: application.id)[:resolution_rate]).to eq(50.0)
    end

    it "matches the rate the Overview renders from the same rows" do
      recurring_group(count: 100, resolved: true, status: "resolved")
      recurring_group(count: 1, resolved: false)

      overview = dashboard.call(application_id: application.id)
      overview_rate = ((overview[:resolved].to_f / (overview[:resolved] + overview[:unresolved])) * 100).round(1)

      expect(analytics.call(30, application_id: application.id)[:resolution_rate]).to eq(overview_rate)
    end

    it "is zero when the window holds no groups at all" do
      expect(analytics.call(30, application_id: application.id)[:resolution_rate]).to eq(0)
    end
  end

  # The group's user_id is overwritten by each new occurrence, so grouping
  # ErrorLog by it attributed a whole group to whoever hit it last.
  describe "top affected users" do
    before { allow(RailsErrorDashboard.configuration).to receive(:user_model).and_return("User") }

    it "attributes events to the users who actually experienced them" do
      log = recurring_group(count: 3, user_id: 9)
      create(:error_occurrence, error_log: log, user_id: 7, occurred_at: 2.hours.ago)
      create(:error_occurrence, error_log: log, user_id: 8, occurred_at: 2.hours.ago)
      create(:error_occurrence, error_log: log, user_id: 8, occurred_at: 2.hours.ago)

      top = analytics.call(30, application_id: application.id)[:top_users]
      by_user = top.to_h { |entry| [ entry[:user_id], entry[:count] ] }

      expect(by_user[8]).to eq(2)
      expect(by_user[7]).to eq(1)
    end

    # Rows captured before occurrence tracking, and storm count-only events,
    # have no occurrence row. Dropping them would lose real users.
    it "still lists a user whose group has no occurrence rows at all" do
      recurring_group(count: 4, user_id: 42)

      top = analytics.call(30, application_id: application.id)[:top_users]

      expect(top.map { |entry| entry[:user_id] }).to include(42)
      expect(top.find { |entry| entry[:user_id] == 42 }[:count]).to eq(4)
    end
  end

  # Occurrence-derived figures are a floor when storm protection shed
  # per-event rows. The Overview labels that; so does this page.
  describe "incompleteness labelling" do
    it "is complete when every event has a recorded occurrence" do
      log = recurring_group(count: 2, user_id: 1)
      2.times { create(:error_occurrence, error_log: log, user_id: 1, occurred_at: 2.hours.ago) }

      expect(analytics.call(30, application_id: application.id)[:error_stats][:affected_users_incomplete]).to be false
    end

    it "says the affected-user figure is a floor when events outnumber occurrences" do
      recurring_group(count: 500, user_id: 1)

      expect(analytics.call(30, application_id: application.id)[:error_stats][:affected_users_incomplete]).to be true
    end
  end
end
