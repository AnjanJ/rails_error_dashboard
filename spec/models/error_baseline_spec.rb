# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RailsErrorDashboard::ErrorBaseline, type: :model do
  describe "validations" do
    it "validates presence of error_type" do
      baseline = build(:error_baseline, error_type: nil)
      expect(baseline).not_to be_valid
      expect(baseline.errors[:error_type]).to include("can't be blank")
    end

    it "validates presence of platform" do
      baseline = build(:error_baseline, platform: nil)
      expect(baseline).not_to be_valid
      expect(baseline.errors[:platform]).to include("can't be blank")
    end

    it "validates baseline_type is in BASELINE_TYPES" do
      baseline = build(:error_baseline, baseline_type: "invalid")
      expect(baseline).not_to be_valid
      expect(baseline.errors[:baseline_type]).to include("is not included in the list")
    end

    it "validates period_end is after period_start" do
      baseline = build(:error_baseline, period_start: Time.current, period_end: 1.day.ago)
      expect(baseline).not_to be_valid
      expect(baseline.errors[:period_end]).to include("must be after period_start")
    end
  end

  describe "scopes" do
    let!(:ios_error) { create(:error_baseline, error_type: "NoMethodError", platform: "iOS") }
    let!(:android_error) { create(:error_baseline, error_type: "ArgumentError", platform: "Android") }
    let!(:hourly) { create(:error_baseline, :hourly) }
    let!(:weekly) { create(:error_baseline, :weekly) }

    it ".for_error_type filters by error type" do
      results = described_class.for_error_type("NoMethodError")
      expect(results).to include(ios_error, hourly)
      expect(results).not_to include(android_error)
    end

    it ".for_platform filters by platform" do
      results = described_class.for_platform("iOS")
      expect(results).to include(ios_error, hourly)
      expect(results).not_to include(android_error)
    end

    it ".hourly filters hourly baselines" do
      results = described_class.hourly
      expect(results).to include(hourly)
      expect(results).not_to include(ios_error, weekly)
    end

    it ".daily filters daily baselines" do
      results = described_class.daily
      expect(results).to include(ios_error, android_error)
    end

    it ".weekly filters weekly baselines" do
      results = described_class.weekly
      expect(results).to include(weekly)
    end
  end

  describe "#anomaly_level" do
    let(:baseline) { create(:error_baseline, mean: 10.0, std_dev: 2.0) }

    it "returns nil for count at or below mean" do
      expect(baseline.anomaly_level(10)).to be_nil
      expect(baseline.anomaly_level(8)).to be_nil
    end

    it "returns :elevated for 2-3 std devs above mean" do
      # mean + 2.5*std_dev = 10 + 5 = 15
      expect(baseline.anomaly_level(15)).to eq(:elevated)
    end

    it "returns :high for 3-4 std devs above mean" do
      # mean + 3.5*std_dev = 10 + 7 = 17
      expect(baseline.anomaly_level(17)).to eq(:high)
    end

    it "returns :critical for 4+ std devs above mean" do
      # mean + 5*std_dev = 10 + 10 = 20
      expect(baseline.anomaly_level(20)).to eq(:critical)
    end

    it "accepts custom sensitivity parameter" do
      # With sensitivity=3, need 3 std devs for elevated
      expect(baseline.anomaly_level(17, sensitivity: 3)).to eq(:elevated)
    end

    # A flat history has no spread to measure a spike against. Dividing by a
    # zero std_dev gave Infinity, so ANY count above a perfectly steady mean
    # was reported as :critical.
    it "returns nil when std_dev is zero, however far above the mean" do
      flat = build(:error_baseline, mean: 3.0, std_dev: 0.0)

      expect(flat.anomaly_level(10)).to be_nil
      expect(flat.anomaly_level(10_000)).to be_nil
    end

    it "returns nil when mean or std_dev is missing" do
      expect(build(:error_baseline, mean: nil, std_dev: 1.0).anomaly_level(10)).to be_nil
      expect(build(:error_baseline, mean: 1.0, std_dev: nil).anomaly_level(10)).to be_nil
    end

    # mean 0, std_dev 1: the count IS the number of standard deviations. Each
    # band is half-open, [lower, upper): a boundary value belongs to the band
    # it opens. Inclusive ranges tried top-down used to give 3.0 to :elevated
    # and 4.0 to :high.
    describe "band boundaries" do
      let(:unit) { build(:error_baseline, mean: 0.0, std_dev: 1.0) }

      {
        1.99 => nil, 2.0 => :elevated, 2.99 => :elevated,
        3.0 => :high, 3.5 => :high, 3.99 => :high,
        4.0 => :critical, 4.5 => :critical, 1_000_000 => :critical
      }.each do |sigma, level|
        it "maps #{sigma} sigma to #{level.inspect} at the default sensitivity" do
          expect(unit.anomaly_level(sigma)).to eq(level)
        end
      end

      {
        2.99 => nil, 3.0 => :elevated, 3.99 => :elevated,
        4.0 => :high, 4.99 => :high, 5.0 => :critical
      }.each do |sigma, level|
        it "maps #{sigma} sigma to #{level.inspect} at sensitivity 3" do
          expect(unit.anomaly_level(sigma, sensitivity: 3)).to eq(level)
        end
      end

      it "returns nil at or below the mean" do
        expect(unit.anomaly_level(0)).to be_nil
        expect(unit.anomaly_level(-5)).to be_nil
      end
    end
  end

  describe "#exceeds_baseline?" do
    let(:baseline) { create(:error_baseline, mean: 10.0, std_dev: 2.0) }

    it "returns true when count exceeds baseline + sensitivity*std_dev" do
      # Threshold = 10 + 2*2 = 14
      expect(baseline.exceeds_baseline?(15)).to be true
    end

    it "returns false when count is below threshold" do
      expect(baseline.exceeds_baseline?(13)).to be false
    end
  end

  describe "#threshold" do
    let(:baseline) { create(:error_baseline, mean: 10.0, std_dev: 2.0) }

    it "returns mean + sensitivity*std_dev" do
      expect(baseline.threshold).to eq(14.0) # 10 + 2*2
    end

    it "accepts custom sensitivity" do
      expect(baseline.threshold(sensitivity: 3)).to eq(16.0) # 10 + 3*2
    end
  end

  describe "#std_devs_above_mean" do
    let(:baseline) { create(:error_baseline, mean: 10.0, std_dev: 2.0) }

    it "calculates standard deviations above mean" do
      expect(baseline.std_devs_above_mean(14)).to eq(2.0)
    end

    it "returns nil if std_dev is zero" do
      baseline.update(std_dev: 0)
      expect(baseline.std_devs_above_mean(14)).to be_nil
    end
  end
end
