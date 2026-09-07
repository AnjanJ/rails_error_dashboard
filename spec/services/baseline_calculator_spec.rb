# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RailsErrorDashboard::Services::BaselineCalculator do
  describe "#calculate_for_error_type" do
    let(:error_type) { "NoMethodError" }
    let(:platform) { "iOS" }

    before do
      # Create errors over the past weeks — each capture is a group row plus
      # the occurrence the calculator actually counts
      30.times do |i|
        log = create(:error_log, error_type: error_type, platform: platform, occurred_at: i.days.ago)
        create(:error_occurrence, error_log: log, occurred_at: i.days.ago)
      end
    end

    it "calculates hourly, daily, and weekly baselines" do
      result = described_class.calculate_for_error_type(error_type, platform)

      expect(result[:hourly]).to be_a(RailsErrorDashboard::ErrorBaseline)
      expect(result[:daily]).to be_a(RailsErrorDashboard::ErrorBaseline)
      expect(result[:weekly]).to be_a(RailsErrorDashboard::ErrorBaseline)
    end

    it "sets correct baseline_type for each" do
      result = described_class.calculate_for_error_type(error_type, platform)

      expect(result[:hourly].baseline_type).to eq("hourly")
      expect(result[:daily].baseline_type).to eq("daily")
      expect(result[:weekly].baseline_type).to eq("weekly")
    end

    it "calculates statistical metrics" do
      result = described_class.calculate_for_error_type(error_type, platform)
      baseline = result[:daily]

      expect(baseline.mean).to be_present
      expect(baseline.std_dev).to be_present
      expect(baseline.percentile_95).to be_present
      expect(baseline.percentile_99).to be_present
      expect(baseline.sample_size).to be > 0
    end
  end

  describe "sampling unit" do
    let(:error_type) { "ReviewBaselineError" }
    let(:platform) { "API" }

    it "treats each calendar hour as one sample, zero hours included" do
      log = create(:error_log, error_type: error_type, platform: platform, occurred_at: 1.day.ago)
      7.times do |i|
        create(:error_occurrence, error_log: log, occurred_at: (i + 1).days.ago.beginning_of_day + 12.hours)
      end

      hourly = described_class.new.send(:calculate_hourly_baseline, error_type, platform)

      expect(hourly.sample_size).to eq(4 * 7 * 24)   # every hour of the four-week lookback
      expect(hourly.count).to eq(7)
      expect(hourly.mean).to eq((7.0 / (4 * 7 * 24)).round(2))
    end

    it "treats each calendar day as one sample" do
      log = create(:error_log, error_type: error_type, platform: platform, occurred_at: 1.day.ago)
      7.times { |i| create(:error_occurrence, error_log: log, occurred_at: (i + 1).days.ago.noon) }

      daily = described_class.new.send(:calculate_daily_baseline, error_type, platform)

      expect(daily.sample_size).to eq(12 * 7)
      expect(daily.count).to eq(7)
    end

    it "buckets weeks on the same day Rails does, so a Sunday and a Monday event land in different weeks" do
      Time.use_zone("UTC") do
        log = create(:error_log, error_type: error_type, platform: platform, occurred_at: 1.day.ago)
        create(:error_occurrence, error_log: log, occurred_at: Time.zone.parse("2026-08-09 12:00")) # Sunday
        create(:error_occurrence, error_log: log, occurred_at: Time.zone.parse("2026-08-10 12:00")) # Monday
        start_at = Time.zone.parse("2026-08-03 00:00") # a Monday, as Rails' beginning_of_week gives
        end_at = Time.zone.parse("2026-08-17 00:00")

        counts = described_class.new.send(:bucket_counts, error_type, platform, :week, start_at, end_at)
        expect(counts).to eq([ 1, 1 ])
      end
    end

    it "scopes the counting relation to one application when asked" do
      quiet = create(:application, name: "Quiet baseline app")
      busy = create(:application, name: "Busy baseline app")
      log = create(:error_log, application: busy, error_type: error_type, platform: platform)
      3.times { create(:error_occurrence, error_log: log, occurred_at: Time.current) }

      expect(described_class.counting_relation(error_type, platform, application_id: quiet.id).count).to eq(0)
      expect(described_class.counting_relation(error_type, platform, application_id: busy.id).count).to eq(3)
      expect(described_class.counting_relation(error_type, platform).count).to eq(3)
    end

    it "counts occurrences, not group rows" do
      log = create(:error_log, error_type: error_type, platform: platform, occurred_at: 1.day.ago)
      3.times { create(:error_occurrence, error_log: log, occurred_at: 1.day.ago.noon) }

      daily = described_class.new.send(:calculate_daily_baseline, error_type, platform)
      expect(daily.count).to eq(3)
    end

    it "returns nil when there were no events in the lookback" do
      expect(described_class.new.send(:calculate_hourly_baseline, "NeverSeen", platform)).to be_nil
    end

    it "does not embed adapter-specific SQL" do
      source = File.read(RailsErrorDashboard::Engine.root.join("lib/rails_error_dashboard/services/baseline_calculator.rb"))
      expect(source).not_to include("strftime")
    end
  end

  describe "#calculate_all_baselines" do
    it "calculates baselines for all error type/platform combinations" do
      a = create(:error_log, error_type: "NoMethodError", platform: "iOS", occurred_at: 1.day.ago)
      b = create(:error_log, error_type: "ArgumentError", platform: "Android", occurred_at: 1.day.ago)
      create(:error_occurrence, error_log: a, occurred_at: 1.day.ago)
      create(:error_occurrence, error_log: b, occurred_at: 1.day.ago)

      result = described_class.calculate_all_baselines

      expect(result[:calculated]).to be > 0
    end
  end
end
