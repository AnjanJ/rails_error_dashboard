# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::CriticalAlerts do
  describe ".call" do
    let!(:application) { create(:application) }

    context "with critical/high priority recent errors" do
      let!(:critical_error) do
        create(:error_log,
          application: application,
          priority_level: 4,
          resolved_at: nil,
          occurred_at: 30.minutes.ago)
      end

      let!(:high_error) do
        create(:error_log,
          application: application,
          priority_level: 3,
          resolved_at: nil,
          occurred_at: 45.minutes.ago)
      end

      it "returns unresolved critical/high priority errors from the last hour" do
        result = described_class.call

        expect(result).to include(critical_error, high_error)
      end

      it "orders by occurred_at desc" do
        result = described_class.call

        expect(result.first).to eq(critical_error)
        expect(result.second).to eq(high_error)
      end
    end

    context "with resolved errors" do
      let!(:resolved_critical) do
        create(:error_log,
          priority_level: 4,
          resolved_at: Time.current,
          occurred_at: 30.minutes.ago)
      end

      it "excludes resolved errors" do
        result = described_class.call

        expect(result).not_to include(resolved_critical)
      end
    end

    context "with old errors" do
      let!(:old_critical) do
        create(:error_log,
          priority_level: 4,
          resolved_at: nil,
          occurred_at: 2.hours.ago)
      end

      it "excludes errors older than 1 hour" do
        result = described_class.call

        expect(result).not_to include(old_critical)
      end
    end

    context "with low priority errors" do
      let!(:low_priority) do
        create(:error_log,
          priority_level: 1,
          resolved_at: nil,
          occurred_at: 30.minutes.ago)
      end

      it "excludes low/medium priority errors" do
        result = described_class.call

        expect(result).not_to include(low_priority)
      end
    end

    context "with application_id filter" do
      let!(:app1) { create(:application) }
      let!(:app2) { create(:application) }

      let!(:app1_error) do
        create(:error_log,
          application: app1,
          priority_level: 4,
          resolved_at: nil,
          occurred_at: 30.minutes.ago)
      end

      let!(:app2_error) do
        create(:error_log,
          application: app2,
          priority_level: 4,
          resolved_at: nil,
          occurred_at: 30.minutes.ago)
      end

      it "filters by application_id when provided" do
        result = described_class.call(application_id: app1.id)

        expect(result).to include(app1_error)
        expect(result).not_to include(app2_error)
      end

      it "returns all applications when application_id is nil" do
        result = described_class.call

        expect(result).to include(app1_error, app2_error)
      end
    end

    context "with limit" do
      before do
        12.times do |i|
          create(:error_log,
            priority_level: 4,
            resolved_at: nil,
            occurred_at: (i + 1).minutes.ago)
        end
      end

      it "defaults to 10 results" do
        result = described_class.call

        expect(result.size).to eq(10)
      end

      it "respects custom limit" do
        result = described_class.call(limit: 5)

        expect(result.size).to eq(5)
      end
    end

    context "with no matching errors" do
      it "returns empty relation" do
        result = described_class.call

        expect(result).to be_empty
      end
    end
  end
end
