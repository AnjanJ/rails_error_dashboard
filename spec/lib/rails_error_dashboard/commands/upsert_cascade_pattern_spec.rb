# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Commands::UpsertCascadePattern do
  let(:parent_error) { create(:error_log, error_type: "DatabaseError") }
  let(:child_error) { create(:error_log, error_type: "NoMethodError") }

  describe ".call" do
    context "when pattern does not exist" do
      it "creates a new cascade pattern" do
        expect {
          described_class.call(
            parent_error_id: parent_error.id,
            child_error_id: child_error.id,
            frequency: 5,
            avg_delay_seconds: 30.0
          )
        }.to change { RailsErrorDashboard::CascadePattern.count }.by(1)
      end

      it "sets frequency and avg_delay_seconds" do
        result = described_class.call(
          parent_error_id: parent_error.id,
          child_error_id: child_error.id,
          frequency: 5,
          avg_delay_seconds: 30.0
        )

        pattern = result[:pattern]
        expect(pattern.frequency).to eq(5)
        expect(pattern.avg_delay_seconds).to eq(30.0)
      end

      it "sets last_detected_at" do
        result = described_class.call(
          parent_error_id: parent_error.id,
          child_error_id: child_error.id,
          frequency: 5,
          avg_delay_seconds: 30.0
        )

        expect(result[:pattern].last_detected_at).to be_within(1.second).of(Time.current)
      end

      it "returns created: true" do
        result = described_class.call(
          parent_error_id: parent_error.id,
          child_error_id: child_error.id,
          frequency: 5,
          avg_delay_seconds: 30.0
        )

        expect(result[:created]).to be true
      end

      it "calculates probability" do
        # Create parent occurrences so probability can be calculated
        10.times { create(:error_occurrence, error_log: parent_error) }

        result = described_class.call(
          parent_error_id: parent_error.id,
          child_error_id: child_error.id,
          frequency: 5,
          avg_delay_seconds: 30.0
        )

        expect(result[:pattern].cascade_probability).to eq(0.5)
      end
    end

    context "when pattern already exists" do
      let!(:existing_pattern) do
        RailsErrorDashboard::CascadePattern.create!(
          parent_error: parent_error,
          child_error: child_error,
          frequency: 3,
          avg_delay_seconds: 25.0,
          last_detected_at: 1.hour.ago
        )
      end

      it "does not create a new record" do
        expect {
          described_class.call(
            parent_error_id: parent_error.id,
            child_error_id: child_error.id,
            frequency: 5,
            avg_delay_seconds: 30.0
          )
        }.not_to change { RailsErrorDashboard::CascadePattern.count }
      end

      it "increments frequency via IncrementCascadeDetection" do
        described_class.call(
          parent_error_id: parent_error.id,
          child_error_id: child_error.id,
          frequency: 5,
          avg_delay_seconds: 30.0
        )

        existing_pattern.reload
        expect(existing_pattern.frequency).to eq(4) # 3 + 1 from increment
      end

      it "returns created: false" do
        result = described_class.call(
          parent_error_id: parent_error.id,
          child_error_id: child_error.id,
          frequency: 5,
          avg_delay_seconds: 30.0
        )

        expect(result[:created]).to be false
      end

      it "updates last_detected_at" do
        old_time = existing_pattern.last_detected_at

        described_class.call(
          parent_error_id: parent_error.id,
          child_error_id: child_error.id,
          frequency: 5,
          avg_delay_seconds: 30.0
        )

        existing_pattern.reload
        expect(existing_pattern.last_detected_at).to be > old_time
      end
    end
  end
end
