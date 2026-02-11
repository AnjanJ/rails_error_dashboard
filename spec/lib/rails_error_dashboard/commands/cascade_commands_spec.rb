# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cascade Commands" do
  describe RailsErrorDashboard::Commands::IncrementCascadeDetection do
    describe ".call" do
      it "increments frequency" do
        pattern = create(:cascade_pattern, frequency: 3)
        expect { described_class.call(pattern, 20.0) }.to change { pattern.frequency }.from(3).to(4)
      end

      it "updates average delay using incremental formula" do
        pattern = create(:cascade_pattern, frequency: 3, avg_delay_seconds: 15.0)
        described_class.call(pattern, 27.0)
        # New avg = ((15.0 * 3) + 27.0) / 4 = (45 + 27) / 4 = 72 / 4 = 18.0
        expect(pattern.avg_delay_seconds).to eq(18.0)
      end

      it "sets avg_delay_seconds if not present" do
        pattern = create(:cascade_pattern, avg_delay_seconds: nil)
        described_class.call(pattern, 25.0)
        expect(pattern.avg_delay_seconds).to eq(25.0)
      end

      it "updates last_detected_at" do
        pattern = create(:cascade_pattern, last_detected_at: 1.day.ago)
        expect { described_class.call(pattern, 20.0) }.to change { pattern.last_detected_at }
      end

      it "persists changes" do
        pattern = create(:cascade_pattern, frequency: 3)
        described_class.call(pattern, 20.0)
        pattern.reload
        expect(pattern.frequency).to eq(4)
      end

      it "returns the updated pattern" do
        pattern = create(:cascade_pattern, frequency: 3)
        result = described_class.call(pattern, 20.0)
        expect(result).to eq(pattern)
      end
    end
  end

  describe RailsErrorDashboard::Commands::CalculateCascadeProbability do
    describe ".call" do
      it "calculates cascade probability based on parent occurrences" do
        parent = create(:error_log)
        child = create(:error_log)
        pattern = create(:cascade_pattern, parent_error: parent, child_error: child, frequency: 7)

        # Create 10 occurrences for parent
        10.times { create(:error_occurrence, error_log: parent, occurred_at: 1.hour.ago) }

        described_class.call(pattern)
        # Probability = 7 / 10 = 0.7
        expect(pattern.cascade_probability).to eq(0.7)
      end

      it "does not calculate if parent has no occurrences" do
        pattern = create(:cascade_pattern, frequency: 5, cascade_probability: nil)
        described_class.call(pattern)
        expect(pattern.cascade_probability).to be_nil
      end

      it "rounds to 3 decimal places" do
        parent = create(:error_log)
        child = create(:error_log)
        pattern = create(:cascade_pattern, parent_error: parent, child_error: child, frequency: 2)

        # Create 3 occurrences for parent
        3.times { create(:error_occurrence, error_log: parent, occurred_at: 1.hour.ago) }

        described_class.call(pattern)
        # Probability = 2 / 3 = 0.667
        expect(pattern.cascade_probability).to eq(0.667)
      end

      it "persists the probability" do
        parent = create(:error_log)
        child = create(:error_log)
        pattern = create(:cascade_pattern, parent_error: parent, child_error: child, frequency: 5)

        5.times { create(:error_occurrence, error_log: parent, occurred_at: 1.hour.ago) }

        described_class.call(pattern)
        pattern.reload
        expect(pattern.cascade_probability).to eq(1.0)
      end

      it "returns the updated pattern" do
        parent = create(:error_log)
        child = create(:error_log)
        pattern = create(:cascade_pattern, parent_error: parent, child_error: child, frequency: 5)

        5.times { create(:error_occurrence, error_log: parent, occurred_at: 1.hour.ago) }

        result = described_class.call(pattern)
        expect(result).to eq(pattern)
      end

      it "returns nil when parent has zero occurrences" do
        pattern = create(:cascade_pattern, frequency: 5, cascade_probability: nil)
        result = described_class.call(pattern)
        expect(result).to be_nil
      end
    end
  end
end
