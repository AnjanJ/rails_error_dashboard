# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::StatisticalClassifier do
  describe ".correlation_strength" do
    it "returns :strong for >= 0.8" do
      expect(described_class.correlation_strength(0.85)).to eq(:strong)
      expect(described_class.correlation_strength(0.8)).to eq(:strong)
      expect(described_class.correlation_strength(1.0)).to eq(:strong)
    end

    it "returns :moderate for 0.5..0.8" do
      expect(described_class.correlation_strength(0.5)).to eq(:moderate)
      expect(described_class.correlation_strength(0.65)).to eq(:moderate)
      expect(described_class.correlation_strength(0.79)).to eq(:moderate)
    end

    it "returns :weak for < 0.5" do
      expect(described_class.correlation_strength(0.3)).to eq(:weak)
      expect(described_class.correlation_strength(0.0)).to eq(:weak)
    end

    it "uses absolute value for negative correlations" do
      expect(described_class.correlation_strength(-0.9)).to eq(:strong)
      expect(described_class.correlation_strength(-0.6)).to eq(:moderate)
      expect(described_class.correlation_strength(-0.2)).to eq(:weak)
    end
  end

  describe ".trend_direction" do
    it "returns :increasing_significantly for > 20%" do
      expect(described_class.trend_direction(25.0)).to eq(:increasing_significantly)
      expect(described_class.trend_direction(100.0)).to eq(:increasing_significantly)
    end

    it "returns :increasing for 5..20%" do
      expect(described_class.trend_direction(10.0)).to eq(:increasing)
      expect(described_class.trend_direction(5.1)).to eq(:increasing)
    end

    it "returns :stable for -5..5%" do
      expect(described_class.trend_direction(0.0)).to eq(:stable)
      expect(described_class.trend_direction(5.0)).to eq(:stable)
      expect(described_class.trend_direction(-5.0)).to eq(:stable)
    end

    it "returns :decreasing for -20..-5%" do
      expect(described_class.trend_direction(-10.0)).to eq(:decreasing)
      expect(described_class.trend_direction(-5.1)).to eq(:decreasing)
    end

    it "returns :decreasing_significantly for < -20%" do
      expect(described_class.trend_direction(-25.0)).to eq(:decreasing_significantly)
      expect(described_class.trend_direction(-50.0)).to eq(:decreasing_significantly)
    end
  end

  describe ".spike_severity" do
    it "returns :normal for < 2x" do
      expect(described_class.spike_severity(1.0)).to eq(:normal)
      expect(described_class.spike_severity(1.5)).to eq(:normal)
    end

    it "returns :elevated for 2x..5x" do
      expect(described_class.spike_severity(2.0)).to eq(:elevated)
      expect(described_class.spike_severity(3.5)).to eq(:elevated)
      expect(described_class.spike_severity(4.9)).to eq(:elevated)
    end

    it "returns :high for 5x..10x" do
      expect(described_class.spike_severity(5.0)).to eq(:high)
      expect(described_class.spike_severity(7.0)).to eq(:high)
      expect(described_class.spike_severity(9.9)).to eq(:high)
    end

    it "returns :critical for >= 10x" do
      expect(described_class.spike_severity(10.0)).to eq(:critical)
      expect(described_class.spike_severity(50.0)).to eq(:critical)
    end
  end
end
