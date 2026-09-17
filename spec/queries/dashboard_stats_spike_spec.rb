# frozen_string_literal: true

require "rails_helper"

# Spike detection runs inside DashboardStats, and DashboardStats runs from the
# capture path (the live stats broadcast). Its baseline check used to issue
# about six queries per distinct (error_type, platform) pair, twice per call.
RSpec.describe "DashboardStats spike detection" do
  let(:application) { create(:application) }
  let(:stats_class) { RailsErrorDashboard::Queries::DashboardStats }
  let(:baseline_stats) { RailsErrorDashboard::Queries::BaselineStats }

  def occurrence_for(error, at: Time.current)
    RailsErrorDashboard::ErrorOccurrence.create!(error_log: error, occurred_at: at)
  end

  def error_with_events(type, platform: "API", events: 1, app: application, at: Time.current)
    error = create(:error_log, application: app, error_type: type, platform: platform,
                   occurred_at: at, occurrence_count: events)
    events.times { occurrence_for(error, at: at) }
    error
  end

  def baseline(type, platform: "API", kind: "hourly", mean: 1.0, std_dev: 1.0, period_start: 2.weeks.ago)
    create(:error_baseline, error_type: type, platform: platform, baseline_type: kind,
           mean: mean, std_dev: std_dev, period_start: period_start, period_end: 1.hour.ago)
  end

  def sql_statements
    statements = []
    counter = lambda do |_name, _start, _finish, _id, payload|
      next if %w[SCHEMA TRANSACTION].include?(payload[:name])
      next if payload[:sql].match?(/\A\s*(SAVEPOINT|RELEASE)/i)

      statements << payload[:sql]
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    statements
  end

  describe "cost" do
    before do
      50.times { |i| error_with_events("CostError#{i}", platform: i.even? ? "API" : "iOS") }
      10.times { |i| baseline("CostError#{i}", platform: i.even? ? "API" : "iOS") }
    end

    it "checks baselines in at most 3 queries however many (type, platform) pairs exist" do
      statements = sql_statements { baseline_stats.current_anomalies }

      expect(statements.size).to be <= 3, statements.join("\n")
    end

    it "evaluates spike_detected? once per call" do
      query = stats_class.new
      allow(baseline_stats).to receive(:current_anomalies).and_call_original

      query.call

      expect(baseline_stats).to have_received(:current_anomalies).once
    end

    it "does not grow with the number of pairs" do
      few = sql_statements { stats_class.new.call }.size
      50.times { |i| error_with_events("MoreCostError#{i}") }
      Rails.cache.clear

      many = sql_statements { stats_class.new.call }.size

      expect(many).to eq(few)
    end
  end

  describe "detection" do
    it "detects a seeded spike against the hourly baseline" do
      error_with_events("SpikeError", events: 12)
      baseline("SpikeError", mean: 2.0, std_dev: 1.0)

      stats = stats_class.call

      expect(stats[:spike_detected]).to be true
      expect(stats[:spike_info]).to include(baseline_detected: true, anomaly_error_type: "SpikeError",
                                            anomaly_platform: "API", anomaly_level: :critical)
    end

    it "reports the worst anomaly when there are several" do
      error_with_events("MildError", events: 5)
      baseline("MildError", mean: 2.0, std_dev: 1.0)
      error_with_events("WorstError", events: 40)
      baseline("WorstError", mean: 2.0, std_dev: 1.0)

      expect(stats_class.call[:spike_info]).to include(anomaly_error_type: "WorstError", std_devs_above: 38.0)
    end

    it "is false when there are no baselines and no 2x jump" do
      7.times { |d| error_with_events("SteadyError#{d}", events: 3, at: d.days.ago.beginning_of_day + 1.hour) }

      expect(stats_class.call[:spike_detected]).to be false
    end

    it "is false when the count is inside the baseline" do
      7.times { |d| error_with_events("NormalError#{d}", events: 3, at: d.days.ago.beginning_of_day + 1.hour) }
      baseline("NormalError0", mean: 5.0, std_dev: 2.0)

      expect(stats_class.call[:spike_detected]).to be false
    end

    it "uses the most recent baseline of a type, not an older one" do
      error_with_events("DriftError", events: 12)
      baseline("DriftError", mean: 2.0, std_dev: 1.0, period_start: 8.weeks.ago)
      baseline("DriftError", mean: 50.0, std_dev: 5.0, period_start: 1.week.ago)

      expect(baseline_stats.current_anomalies).to be_empty
    end

    it "prefers hourly over daily over weekly, each against its own window" do
      error = error_with_events("WindowError", events: 0)
      20.times { occurrence_for(error, at: Time.current.beginning_of_day + 1.minute) } # today, maybe not this hour
      baseline("WindowError", kind: "daily", mean: 2.0, std_dev: 1.0)

      anomaly = baseline_stats.current_anomalies.find { |a| a[:error_type] == "WindowError" }

      expect(anomaly).to include(baseline_type: "daily")
      expect(anomaly[:count]).to be >= 20
    end

    # A flat history has no spread to measure against; dividing by it made every
    # count above the mean infinitely anomalous.
    it "treats a zero standard deviation as no signal" do
      error_with_events("FlatError", events: 10)
      baseline("FlatError", mean: 3.0, std_dev: 0.0)

      expect(baseline_stats.current_anomalies).to be_empty
    end

    it "scopes the current counts to the application" do
      other = create(:application)
      error_with_events("ScopedError", events: 12, app: other)
      baseline("ScopedError", mean: 2.0, std_dev: 1.0)

      expect(baseline_stats.current_anomalies(application_id: application.id)).to be_empty
      expect(baseline_stats.current_anomalies(application_id: other.id).map { |a| a[:error_type] }).to eq([ "ScopedError" ])
      expect(stats_class.call(application_id: application.id)[:spike_info]&.dig(:baseline_detected)).to be_nil
    end

    it "agrees with the per-pair check it replaces" do
      error_with_events("AgreeA", events: 12)
      baseline("AgreeA", mean: 2.0, std_dev: 1.0)
      error_with_events("AgreeB", platform: "iOS", events: 4)
      baseline("AgreeB", platform: "iOS", kind: "weekly", mean: 1.0, std_dev: 1.0)
      error_with_events("AgreeC", events: 2)
      baseline("AgreeC", mean: 9.0, std_dev: 1.0)
      error_with_events("AgreeD", events: 30) # no baseline at all

      per_pair = RailsErrorDashboard::ErrorLog.distinct.pluck(:error_type, :platform).filter_map do |type, platform|
        result = baseline_stats.new(type, platform).check_current_anomaly(sensitivity: 2)
        [ type, platform, result[:level], result[:current_count], result[:baseline_type] ] if result[:anomaly]
      end
      bulk = baseline_stats.current_anomalies.map do |a|
        [ a[:error_type], a[:platform], a[:level], a[:count], a[:baseline_type] ]
      end

      expect(bulk).to match_array(per_pair)
      expect(bulk.map(&:first)).to contain_exactly("AgreeA", "AgreeB")
    end

    it "never raises: a failing baseline check reads as no anomaly" do
      allow(RailsErrorDashboard::ErrorBaseline).to receive(:table_exists?).and_raise(RuntimeError, "db down")

      expect(baseline_stats.current_anomalies).to eq([])
    end
  end
end
