# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Commands::UpsertBaseline do
  let(:stats) do
    { mean: 7.2, std_dev: 2.1, percentile_95: 11.0, percentile_99: 13.5 }
  end

  let(:base_params) do
    {
      error_type: "NoMethodError",
      platform: "Web",
      baseline_type: "daily",
      period_start: 12.weeks.ago.beginning_of_day,
      period_end: Time.current.beginning_of_day,
      stats: stats,
      count: 50,
      sample_size: 7
    }
  end

  describe ".call" do
    context "when baseline does not exist" do
      it "creates a new baseline record" do
        expect {
          described_class.call(**base_params)
        }.to change { RailsErrorDashboard::ErrorBaseline.count }.by(1)
      end

      it "sets all statistical fields" do
        baseline = described_class.call(**base_params)

        expect(baseline.mean).to eq(7.2)
        expect(baseline.std_dev).to eq(2.1)
        expect(baseline.percentile_95).to eq(11.0)
        expect(baseline.percentile_99).to eq(13.5)
        expect(baseline.count).to eq(50)
        expect(baseline.sample_size).to eq(7)
      end

      it "sets identification fields" do
        baseline = described_class.call(**base_params)

        expect(baseline.error_type).to eq("NoMethodError")
        expect(baseline.platform).to eq("Web")
        expect(baseline.baseline_type).to eq("daily")
      end

      it "sets period fields" do
        baseline = described_class.call(**base_params)

        expect(baseline.period_start).to be_within(1.second).of(base_params[:period_start])
        expect(baseline.period_end).to be_within(1.second).of(base_params[:period_end])
      end
    end

    context "when baseline already exists" do
      let!(:existing) do
        RailsErrorDashboard::ErrorBaseline.create!(
          error_type: "NoMethodError",
          platform: "Web",
          baseline_type: "daily",
          period_start: base_params[:period_start],
          period_end: 1.day.ago,
          count: 30,
          mean: 5.0,
          std_dev: 1.5,
          percentile_95: 8.0,
          percentile_99: 10.0,
          sample_size: 5
        )
      end

      it "does not create a new record" do
        expect {
          described_class.call(**base_params)
        }.not_to change { RailsErrorDashboard::ErrorBaseline.count }
      end

      it "updates statistical fields" do
        described_class.call(**base_params)
        existing.reload

        expect(existing.mean).to eq(7.2)
        expect(existing.std_dev).to eq(2.1)
        expect(existing.count).to eq(50)
        expect(existing.sample_size).to eq(7)
      end

      it "updates period_end" do
        described_class.call(**base_params)
        existing.reload

        expect(existing.period_end).to be_within(1.second).of(base_params[:period_end])
      end
    end

    context "with missing stats keys" do
      it "persists with nil for missing stat fields" do
        baseline = described_class.call(**base_params.merge(stats: { mean: 5.0 }))

        expect(baseline).to be_persisted
        expect(baseline.mean).to eq(5.0)
        expect(baseline.std_dev).to be_nil
        expect(baseline.percentile_95).to be_nil
        expect(baseline.percentile_99).to be_nil
      end

      it "persists with empty stats hash" do
        baseline = described_class.call(**base_params.merge(stats: {}))

        expect(baseline).to be_persisted
        expect(baseline.mean).to be_nil
      end
    end

    context "with zero count and sample_size" do
      it "persists zero count" do
        baseline = described_class.call(**base_params.merge(count: 0, sample_size: 0))

        expect(baseline).to be_persisted
        expect(baseline.count).to eq(0)
        expect(baseline.sample_size).to eq(0)
      end
    end

    context "with different baseline types" do
      it "creates hourly baseline" do
        baseline = described_class.call(**base_params.merge(baseline_type: "hourly"))
        expect(baseline.baseline_type).to eq("hourly")
      end

      it "creates weekly baseline" do
        baseline = described_class.call(**base_params.merge(baseline_type: "weekly"))
        expect(baseline.baseline_type).to eq("weekly")
      end
    end
  end
end
