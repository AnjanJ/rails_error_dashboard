# frozen_string_literal: true

require "rails_helper"

# An ErrorLog row is a GROUP, not an event. Its occurrence_count says how many
# times that error actually happened, so counting rows reported five users
# hitting one exception as "1 error today, 1 affected user".
#
# Two counting units, kept distinct on purpose:
#
#   events          sum(occurrence_count) -- exact, and includes storm
#                   count-only events, which never create occurrence rows
#   affected users  distinct user_id on OCCURRENCE rows -- the group's own
#                   user_id is overwritten by each new occurrence, so counting
#                   it distinct across groups yields at most one per group.
#                   Storm shedding makes this a floor, which the page says.
RSpec.describe "analytics counting units" do
  let(:stats) { RailsErrorDashboard::Queries::DashboardStats }
  let(:impact) { RailsErrorDashboard::Queries::UserImpactSummary }
  let(:logs) { RailsErrorDashboard::ErrorLog }
  let(:log_error) { RailsErrorDashboard::Commands::LogError }

  before do
    RailsErrorDashboard.reset_configuration!
    config = RailsErrorDashboard.configuration
    config.enable_storm_protection = false
    config.async_logging = false
    config.sampling_rate = 1.0
    allow(RailsErrorDashboard::Services::ErrorBroadcaster).to receive(:available?).and_return(false)
    Rails.cache.clear
  end

  after do
    RailsErrorDashboard.reset_configuration!
    Rails.cache.clear
  end

  def boom(message = "counting boom")
    StandardError.new(message).tap do |error|
      error.set_backtrace([ "#{Rails.root}/app/models/audit.rb:12:in 'run'" ])
    end
  end

  describe "five users hitting one error" do
    before { 5.times { |i| log_error.call(boom, user_id: i + 1) } }

    it "is one group but five events" do
      expect(logs.count).to eq(1)
      expect(logs.sole.occurrence_count).to eq(5)
      expect(stats.call[:total_today]).to eq(5)
    end

    it "is five affected users, not one" do
      expect(stats.call[:affected_users_today]).to eq(5)
    end

    it "reports five unique users and five events in the impact summary" do
      entry = impact.call[:entries].sole

      expect(entry[:unique_users]).to eq(5)
      expect(entry[:total_occurrences]).to eq(5)
    end

    # This grouped by each row's own id and counted DISTINCT user_id within
    # that single row, which can only be zero or one.
    it "scores impact from distinct users x events" do
      top = stats.call[:top_errors_by_impact].first

      expect(top[:affected_users]).to eq(5)
      expect(top[:impact_score]).to eq(25)
    end
  end

  it "counts a user who hit two error types once in the global total" do
    other = StandardError.new("second kind")
    other.set_backtrace([ "#{Rails.root}/app/models/other.rb:3:in 'go'" ])

    log_error.call(boom, user_id: 42)
    log_error.call(other, user_id: 42)

    expect(impact.call[:summary][:total_unique_users_affected]).to eq(1)
  end

  describe "the error rate" do
    # It rendered with a "%" against a scale that called one error per hour
    # "1%", capped at 100 -- so 4,000 errors/hour displayed as "100%".
    it "is a rate per hour, uncapped, with no percentage anywhere" do
      travel_to Time.current.beginning_of_day + 10.hours do
        logs.create!(
          application_id: RailsErrorDashboard::Application.find_or_create_by_name("rate").id,
          error_type: "StandardError", message: "many", error_hash: SecureRandom.hex(8),
          occurrence_count: 4_000, occurred_at: Time.current, resolved: false
        )

        expect(stats.call[:error_rate]).to eq(400.0)
      end
    end

    it "is zero when nothing happened today" do
      expect(stats.call[:error_rate]).to eq(0.0)
    end
  end

  describe "honesty flags" do
    it "reports data as available and complete on a normal day" do
      log_error.call(boom, user_id: 1)

      result = stats.call
      expect(result[:data_unavailable]).to be false
      expect(result[:affected_users_incomplete]).to be false
    end

    # Zero errors and "the query failed" are different states. Rescuing to
    # zeros made a broken dashboard look like a quiet one.
    it "says so when the statistics cannot be read at all" do
      allow(RailsErrorDashboard::ErrorLog).to receive(:all).and_raise(ActiveRecord::StatementInvalid, "boom")

      result = stats.call

      expect(result[:data_unavailable]).to be true
      expect(result[:total_today]).to eq(0)
    end

    # Storm count-only events raise occurrence_count without creating an
    # occurrence row, so the affected-user figure is a floor.
    it "flags affected users as incomplete when events outnumber occurrence rows" do
      application = RailsErrorDashboard::Application.find_or_create_by_name("storm counting")
      logs.create!(
        application_id: application.id, error_type: "StandardError", message: "shed",
        error_hash: SecureRandom.hex(8), occurrence_count: 500,
        occurred_at: Time.current, resolved: false
      )

      expect(stats.call[:affected_users_incomplete]).to be true
    end
  end

  describe "event counts include storm-shed events" do
    it "counts every occurrence, not just those with a recorded row" do
      application = RailsErrorDashboard::Application.find_or_create_by_name("shed events")
      logs.create!(
        application_id: application.id, error_type: "StandardError", message: "shed",
        error_hash: SecureRandom.hex(8), occurrence_count: 250,
        occurred_at: Time.current, resolved: false
      )

      result = stats.call
      expect(result[:total_today]).to eq(250)
      expect(result[:top_errors]["StandardError"]).to eq(250)
      expect(result[:errors_trend_7d].values.sum).to eq(250)
    end
  end
end
