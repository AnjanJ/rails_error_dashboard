# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RailsErrorDashboard::Queries::BaselineStats do
  let(:error_type) { "NoMethodError" }
  let(:platform) { "iOS" }

  describe ".hourly_baseline" do
    it "returns most recent hourly baseline" do
      create(:error_baseline, :hourly, error_type: error_type, platform: platform, period_start: 2.weeks.ago)
      recent = create(:error_baseline, :hourly, error_type: error_type, platform: platform, period_start: 1.week.ago)

      result = described_class.hourly_baseline(error_type, platform)
      expect(result.id).to eq(recent.id)
    end
  end

  describe "#check_anomaly" do
    let!(:baseline) { create(:error_baseline, error_type: error_type, platform: platform, mean: 10.0, std_dev: 2.0) }
    let(:stats) { described_class.new(error_type, platform) }

    it "detects anomaly when count exceeds threshold" do
      result = stats.check_anomaly(15) # 10 + 2.5*2 = 15
      expect(result[:anomaly]).to be true
      expect(result[:level]).to be_in([ :elevated, :high, :critical ])
    end

    it "returns no anomaly for normal count" do
      result = stats.check_anomaly(10)
      expect(result[:anomaly]).to be false
    end

    it "includes threshold and std_devs_above in result" do
      result = stats.check_anomaly(15)
      expect(result[:threshold]).to be_present
      expect(result[:std_devs_above]).to be_present
    end
  end
  describe "#check_anomaly with per-unit counts" do
    let(:stats) { described_class.new(error_type, platform) }

    it "compares the current hour against the hourly baseline, not today's count" do
      create(:error_baseline, :hourly, error_type: error_type, platform: platform, mean: 1.0, std_dev: 0.5)

      quiet_hour_busy_day = stats.check_anomaly(hourly: 1, daily: 40, weekly: 200)
      expect(quiet_hour_busy_day[:anomaly]).to be false
      expect(quiet_hour_busy_day[:baseline_type]).to eq("hourly")
      expect(quiet_hour_busy_day[:current_count]).to eq(1)

      expect(stats.check_anomaly(hourly: 5, daily: 5, weekly: 5)[:anomaly]).to be true
    end

    it "falls through to the daily baseline with the daily count when there is no hourly baseline" do
      create(:error_baseline, error_type: error_type, platform: platform, mean: 10.0, std_dev: 2.0) # daily

      result = stats.check_anomaly(hourly: 100, daily: 10, weekly: 10)
      expect(result[:baseline_type]).to eq("daily")
      expect(result[:anomaly]).to be false
    end
  end

  describe "#current_counts and #check_current_anomaly" do
    let(:stats) { described_class.new(error_type, platform) }

    it "counts occurrences of this error type in the current hour, day and week" do
      log = create(:error_log, error_type: error_type, platform: platform)
      create(:error_occurrence, error_log: log, occurred_at: Time.current)
      create(:error_occurrence, error_log: log, occurred_at: Time.current.beginning_of_day + 1.second)
      create(:error_occurrence, error_log: log, occurred_at: Time.current.beginning_of_week + 1.second)

      counts = stats.current_counts
      expect(counts[:hourly]).to be_between(1, 3)
      expect(counts[:daily]).to be_between(2, 3)
      expect(counts[:weekly]).to eq(3)
    end

    it "does not report another application's spike on a quiet application" do
      create(:error_baseline, :hourly, error_type: error_type, platform: platform, mean: 0.1, std_dev: 0.1)
      quiet = create(:application, name: "Quiet app")
      busy = create(:application, name: "Busy app")
      log = create(:error_log, application: busy, error_type: error_type, platform: platform)
      5.times { create(:error_occurrence, error_log: log, occurred_at: Time.current) }

      expect(stats.check_current_anomaly(application_id: quiet.id)[:anomaly]).to be false
      expect(stats.check_current_anomaly(application_id: busy.id)[:anomaly]).to be true
    end

    it "feeds those counts to the matching baseline" do
      create(:error_baseline, :hourly, error_type: error_type, platform: platform, mean: 0.1, std_dev: 0.1)
      log = create(:error_log, error_type: error_type, platform: platform)
      4.times { create(:error_occurrence, error_log: log, occurred_at: Time.current) }

      result = stats.check_current_anomaly(sensitivity: 2)
      expect(result[:baseline_type]).to eq("hourly")
      expect(result[:anomaly]).to be true
      expect(result[:current_count]).to eq(4)
    end
  end
end
