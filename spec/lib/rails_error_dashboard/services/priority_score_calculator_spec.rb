# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::PriorityScoreCalculator do
  describe ".compute" do
    let(:error_log) do
      create(:error_log,
             error_type: "NoMethodError",
             occurrence_count: 10,
             occurred_at: 1.hour.ago,
             user_id: nil)
    end

    it "returns an integer score" do
      score = described_class.compute(error_log)
      expect(score).to be_a(Integer)
    end

    it "returns score between 0 and 100" do
      score = described_class.compute(error_log)
      expect(score).to be_between(0, 100)
    end

    it "scores critical errors higher than low errors" do
      critical = create(:error_log, error_type: "SecurityError", occurrence_count: 1, occurred_at: 1.day.ago)
      low = create(:error_log, error_type: "StandardError", occurrence_count: 1, occurred_at: 1.day.ago)

      expect(described_class.compute(critical)).to be > described_class.compute(low)
    end

    it "scores frequent errors higher than infrequent" do
      frequent = create(:error_log, error_type: "StandardError", occurrence_count: 100, occurred_at: 1.day.ago)
      rare = create(:error_log, error_type: "StandardError", occurrence_count: 1, occurred_at: 1.day.ago)

      expect(described_class.compute(frequent)).to be > described_class.compute(rare)
    end

    it "scores recent errors higher than old errors" do
      recent = create(:error_log, error_type: "StandardError", occurrence_count: 1, occurred_at: 30.minutes.ago)
      old = create(:error_log, error_type: "StandardError", occurrence_count: 1, occurred_at: 60.days.ago)

      expect(described_class.compute(recent)).to be > described_class.compute(old)
    end
  end

  describe ".severity_to_score" do
    it "returns 100 for critical" do
      expect(described_class.severity_to_score(:critical)).to eq(100)
    end

    it "returns 75 for high" do
      expect(described_class.severity_to_score(:high)).to eq(75)
    end

    it "returns 50 for medium" do
      expect(described_class.severity_to_score(:medium)).to eq(50)
    end

    it "returns 25 for low" do
      expect(described_class.severity_to_score(:low)).to eq(25)
    end

    it "returns 10 for unknown" do
      expect(described_class.severity_to_score(:unknown)).to eq(10)
    end

    it "returns 10 for nil severity" do
      expect(described_class.severity_to_score(nil)).to eq(10)
    end
  end

  describe ".frequency_to_score" do
    it "returns 10 for count of 1" do
      expect(described_class.frequency_to_score(1)).to eq(10)
    end

    it "returns 100 for count of 1000+" do
      expect(described_class.frequency_to_score(1000)).to eq(100)
      expect(described_class.frequency_to_score(5000)).to eq(100)
    end

    it "scales logarithmically" do
      score_10 = described_class.frequency_to_score(10)
      score_100 = described_class.frequency_to_score(100)

      expect(score_10).to be > 10
      expect(score_100).to be > score_10
    end

    it "handles nil count safely" do
      expect(described_class.frequency_to_score(nil)).to eq(10)
    end

    it "handles zero count" do
      expect(described_class.frequency_to_score(0)).to eq(10)
    end

    it "handles negative count safely" do
      expect(described_class.frequency_to_score(-5)).to eq(10)
    end

    it "handles Float::INFINITY safely" do
      expect(described_class.frequency_to_score(Float::INFINITY)).to eq(10)
    end

    it "handles Float::NAN safely" do
      expect(described_class.frequency_to_score(Float::NAN)).to eq(10)
    end

    it "handles string count safely" do
      expect(described_class.frequency_to_score("abc")).to eq(10)
    end
  end

  describe ".recency_to_score" do
    it "returns 100 for errors within the last hour" do
      expect(described_class.recency_to_score(30.minutes.ago)).to eq(100)
    end

    it "returns 80 for errors within the last 24 hours" do
      expect(described_class.recency_to_score(12.hours.ago)).to eq(80)
    end

    it "returns 50 for errors within the last week" do
      expect(described_class.recency_to_score(3.days.ago)).to eq(50)
    end

    it "returns 10 for very old errors" do
      expect(described_class.recency_to_score(60.days.ago)).to eq(10)
    end

    it "returns 10 for nil time" do
      expect(described_class.recency_to_score(nil)).to eq(10)
    end

    it "returns 100 for future timestamps" do
      expect(described_class.recency_to_score(1.hour.from_now)).to eq(100)
    end
  end

  describe ".user_impact_to_score" do
    it "returns 0 when no user_id" do
      error = create(:error_log, user_id: nil)
      expect(described_class.user_impact_to_score(error)).to eq(0)
    end

    it "returns score > 0 when user_id present and users affected" do
      error = create(:error_log, user_id: 1, error_type: "TestImpactError")
      expect(described_class.user_impact_to_score(error)).to be > 0
    end
  end

  describe ".unique_users_affected" do
    it "counts distinct users with unresolved errors" do
      3.times { |i| create(:error_log, error_type: "CountTestError", user_id: i + 1, resolved: false) }
      create(:error_log, error_type: "CountTestError", user_id: 1, resolved: false) # duplicate user

      expect(described_class.unique_users_affected("CountTestError")).to eq(3)
    end

    it "excludes resolved errors" do
      create(:error_log, error_type: "ResolvedCountError", user_id: 1, resolved: false)
      create(:error_log, :resolved, error_type: "ResolvedCountError", user_id: 2)

      expect(described_class.unique_users_affected("ResolvedCountError")).to eq(1)
    end
  end
end
