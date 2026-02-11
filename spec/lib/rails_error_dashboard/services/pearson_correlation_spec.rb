# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::PearsonCorrelation do
  describe ".call" do
    it "returns 1.0 for perfectly correlated series" do
      expect(described_class.call([ 1, 2, 3, 4, 5 ], [ 2, 4, 6, 8, 10 ])).to eq(1.0)
    end

    it "returns -1.0 for perfectly inversely correlated series" do
      expect(described_class.call([ 1, 2, 3, 4, 5 ], [ 10, 8, 6, 4, 2 ])).to eq(-1.0)
    end

    it "returns 0.0 for uncorrelated series" do
      # Alternating pattern vs constant should have low correlation
      result = described_class.call([ 1, -1, 1, -1 ], [ 1, 1, 1, 1 ])
      expect(result).to eq(0.0)
    end

    it "returns 0.0 for empty arrays" do
      expect(described_class.call([], [])).to eq(0.0)
    end

    it "returns 0.0 when first series sums to zero" do
      expect(described_class.call([ 0, 0, 0 ], [ 1, 2, 3 ])).to eq(0.0)
    end

    it "returns 0.0 when second series sums to zero" do
      expect(described_class.call([ 1, 2, 3 ], [ 0, 0, 0 ])).to eq(0.0)
    end

    it "calculates moderate positive correlation" do
      result = described_class.call(
        [ 1, 2, 3, 4, 5, 6 ],
        [ 2, 1, 4, 3, 6, 5 ]
      )
      expect(result).to be_between(0.5, 1.0)
    end

    it "handles single-element arrays" do
      # Single element with itself — std_dev is zero, so returns 0.0
      expect(described_class.call([ 5 ], [ 5 ])).to eq(0.0)
    end

    it "rounds to 3 decimal places" do
      result = described_class.call([ 1, 3, 5, 7 ], [ 2, 5, 6, 9 ])
      decimal_places = result.to_s.split(".").last.length
      expect(decimal_places).to be <= 3
    end
  end
end
