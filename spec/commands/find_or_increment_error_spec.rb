# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Commands::FindOrIncrementError do
  let(:application) { RailsErrorDashboard::Application.find_or_create_by_name("Test App") }
  let(:error_hash) { "abc123def456" }
  let(:base_attributes) do
    {
      application_id: application.id,
      error_type: "NoMethodError",
      message: "undefined method 'name' for nil",
      backtrace: "app/models/user.rb:42:in 'name'",
      occurred_at: Time.current,
      error_hash: error_hash
    }
  end

  after do
    RailsErrorDashboard::ErrorLog.delete_all
  end

  describe ".call" do
    context "when no matching error exists" do
      it "creates a new error record" do
        expect {
          described_class.call(error_hash, base_attributes)
        }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
      end

      it "sets occurrence_count to 1" do
        error = described_class.call(error_hash, base_attributes)
        expect(error.occurrence_count).to eq(1)
      end

      it "sets resolved to false" do
        error = described_class.call(error_hash, base_attributes)
        expect(error.resolved).to be false
      end
    end

    context "when an unresolved match exists within 24h" do
      let!(:existing) do
        RailsErrorDashboard::ErrorLog.create!(
          base_attributes.merge(
            resolved: false,
            occurrence_count: 3,
            first_seen_at: 2.hours.ago,
            last_seen_at: 1.hour.ago
          )
        )
      end

      it "increments occurrence_count" do
        result = described_class.call(error_hash, base_attributes)
        expect(result.id).to eq(existing.id)
        expect(result.occurrence_count).to eq(4)
      end

      it "updates last_seen_at" do
        freeze_time do
          result = described_class.call(error_hash, base_attributes)
          expect(result.last_seen_at).to be_within(1.second).of(Time.current)
        end
      end

      it "does not create a new record" do
        expect {
          described_class.call(error_hash, base_attributes)
        }.not_to change(RailsErrorDashboard::ErrorLog, :count)
      end
    end

    context "when a resolved match exists" do
      let!(:resolved_error) do
        RailsErrorDashboard::ErrorLog.create!(
          base_attributes.merge(
            resolved: true,
            status: "resolved",
            resolved_at: 1.day.ago,
            occurrence_count: 5,
            first_seen_at: 1.week.ago,
            last_seen_at: 1.day.ago
          )
        )
      end

      it "reopens the resolved error instead of creating a new one" do
        expect {
          described_class.call(error_hash, base_attributes)
        }.not_to change(RailsErrorDashboard::ErrorLog, :count)
      end

      it "sets resolved to false" do
        result = described_class.call(error_hash, base_attributes)
        expect(result.id).to eq(resolved_error.id)
        expect(result.resolved).to be false
      end

      it "sets status back to new" do
        result = described_class.call(error_hash, base_attributes)
        expect(result.status).to eq("new")
      end

      it "clears resolved_at" do
        result = described_class.call(error_hash, base_attributes)
        expect(result.resolved_at).to be_nil
      end

      it "increments occurrence_count" do
        result = described_class.call(error_hash, base_attributes)
        expect(result.occurrence_count).to eq(6)
      end

      it "updates last_seen_at" do
        freeze_time do
          result = described_class.call(error_hash, base_attributes)
          expect(result.last_seen_at).to be_within(1.second).of(Time.current)
        end
      end

      it "preserves first_seen_at" do
        original_first_seen = resolved_error.first_seen_at
        result = described_class.call(error_hash, base_attributes)
        expect(result.first_seen_at).to be_within(1.second).of(original_first_seen)
      end

      it "sets just_reopened flag" do
        result = described_class.call(error_hash, base_attributes)
        expect(result.just_reopened).to be true
      end

      it "sets reopened_at timestamp" do
        freeze_time do
          result = described_class.call(error_hash, base_attributes)
          if RailsErrorDashboard::ErrorLog.column_names.include?("reopened_at")
            expect(result.reopened_at).to be_within(1.second).of(Time.current)
          end
        end
      end

      it "reopens even if resolved more than 24h ago" do
        resolved_error.update!(occurred_at: 1.month.ago, last_seen_at: 1.month.ago)

        result = described_class.call(error_hash, base_attributes)
        expect(result.id).to eq(resolved_error.id)
        expect(result.resolved).to be false
      end
    end

    context "when a wont_fix match exists" do
      let!(:wont_fix_error) do
        RailsErrorDashboard::ErrorLog.create!(
          base_attributes.merge(
            resolved: true,
            status: "wont_fix",
            resolved_at: 1.day.ago,
            occurrence_count: 2,
            first_seen_at: 1.week.ago,
            last_seen_at: 1.day.ago
          )
        )
      end

      it "reopens the wont_fix error" do
        result = described_class.call(error_hash, base_attributes)
        expect(result.id).to eq(wont_fix_error.id)
        expect(result.resolved).to be false
        expect(result.status).to eq("new")
      end
    end

    context "when both unresolved and resolved matches exist" do
      let!(:unresolved_error) do
        RailsErrorDashboard::ErrorLog.create!(
          base_attributes.merge(
            resolved: false,
            status: "new",
            occurrence_count: 2,
            first_seen_at: 1.hour.ago,
            last_seen_at: 30.minutes.ago
          )
        )
      end

      let!(:resolved_error) do
        RailsErrorDashboard::ErrorLog.create!(
          base_attributes.merge(
            error_hash: error_hash,
            resolved: true,
            status: "resolved",
            resolved_at: 1.day.ago,
            occurrence_count: 10,
            first_seen_at: 1.week.ago,
            last_seen_at: 1.day.ago
          )
        )
      end

      it "prefers the unresolved match over resolved" do
        result = described_class.call(error_hash, base_attributes)
        expect(result.id).to eq(unresolved_error.id)
        expect(result.occurrence_count).to eq(3)
      end
    end
  end
end
