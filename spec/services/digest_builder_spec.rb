# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::DigestBuilder do
  let!(:app) { create(:application) }

  describe ".call" do
    it "returns expected keys" do
      result = described_class.call
      expect(result).to have_key(:period)
      expect(result).to have_key(:period_label)
      expect(result).to have_key(:generated_at)
      expect(result).to have_key(:stats)
      expect(result).to have_key(:top_errors)
      expect(result).to have_key(:critical_unresolved)
      expect(result).to have_key(:comparison)
    end

    it "returns empty stats when no errors exist" do
      result = described_class.call
      expect(result[:stats][:new_errors]).to eq(0)
      expect(result[:top_errors]).to be_empty
      expect(result[:critical_unresolved]).to be_empty
    end

    context "with error data" do
      before do
        # NoMethodError is classified as :high by SeverityClassifier
        create(:error_log, application: app, error_type: "NoMethodError",
          occurred_at: 12.hours.ago, occurrence_count: 1)
        create(:error_log, application: app, error_type: "NoMethodError",
          occurred_at: 6.hours.ago, occurrence_count: 5)
        # TypeError is classified as :high by SeverityClassifier
        create(:error_log, application: app, error_type: "TypeError",
          occurred_at: 3.hours.ago, occurrence_count: 1)
        create(:error_log, :resolved, application: app, error_type: "RuntimeError",
          occurred_at: 2.hours.ago, occurrence_count: 1)
      end

      it "counts new errors (occurrence_count <= 1)" do
        result = described_class.call(period: :daily)
        expect(result[:stats][:new_errors]).to eq(3)
      end

      it "sums total occurrences" do
        result = described_class.call(period: :daily)
        expect(result[:stats][:total_occurrences]).to eq(8)
      end

      it "counts resolved and unresolved" do
        result = described_class.call(period: :daily)
        expect(result[:stats][:resolved]).to eq(1)
        expect(result[:stats][:unresolved]).to eq(3)
      end

      it "counts critical and high severity errors" do
        result = described_class.call(period: :daily)
        # NoMethodError (2) + TypeError (1) are HIGH severity
        expect(result[:stats][:critical_high]).to eq(3)
      end

      it "calculates resolution rate" do
        result = described_class.call(period: :daily)
        expect(result[:stats][:resolution_rate]).to eq(25.0) # 1 resolved out of 4
      end

      it "returns top unresolved errors by count" do
        result = described_class.call(period: :daily)
        expect(result[:top_errors]).not_to be_empty
        expect(result[:top_errors].first[:error_type]).to eq("NoMethodError")
      end

      it "returns critical/high unresolved errors" do
        result = described_class.call(period: :daily)
        expect(result[:critical_unresolved]).not_to be_empty
        types = result[:critical_unresolved].map { |e| e[:severity] }
        expect(types).to all(be_in([ :critical, :high ]))
      end
    end

    context "period filtering" do
      it "defaults to daily" do
        result = described_class.call
        expect(result[:period]).to eq(:daily)
        expect(result[:period_label]).to eq("Last 24 hours")
      end

      it "supports weekly period" do
        result = described_class.call(period: :weekly)
        expect(result[:period]).to eq(:weekly)
        expect(result[:period_label]).to eq("Last 7 days")
      end

      it "falls back to daily for unknown period" do
        result = described_class.call(period: :monthly)
        expect(result[:period]).to eq(:daily)
      end

      it "excludes errors outside the time window" do
        create(:error_log, application: app, occurred_at: 3.days.ago, occurrence_count: 1)
        create(:error_log, application: app, occurred_at: 6.hours.ago, occurrence_count: 1)

        result = described_class.call(period: :daily)
        expect(result[:stats][:new_errors]).to eq(1)
      end
    end

    context "application filter" do
      it "filters by application_id" do
        other_app = create(:application, name: "other-app")
        create(:error_log, application: app, occurred_at: 6.hours.ago, occurrence_count: 1)
        create(:error_log, application: other_app, occurred_at: 6.hours.ago, occurrence_count: 1)

        result = described_class.call(application_id: app.id)
        expect(result[:stats][:new_errors]).to eq(1)
      end
    end

    context "comparison" do
      it "calculates delta from previous period" do
        # Previous period (1-2 days ago): 2 errors
        create(:error_log, application: app, occurred_at: 36.hours.ago)
        create(:error_log, application: app, occurred_at: 30.hours.ago)

        # Current period (last 24h): 3 errors
        3.times { create(:error_log, application: app, occurred_at: 6.hours.ago) }

        result = described_class.call(period: :daily)
        expect(result[:comparison][:current_count]).to eq(3)
        expect(result[:comparison][:previous_count]).to eq(2)
        expect(result[:comparison][:error_delta]).to eq(1)
        expect(result[:comparison][:error_delta_percentage]).to eq(50.0)
      end
    end

    context "error handling" do
      it "rescues and returns safe defaults" do
        allow(RailsErrorDashboard::ErrorLog).to receive(:where).and_raise(StandardError, "boom")

        result = described_class.call
        expect(result[:stats][:new_errors]).to eq(0)
        expect(result[:top_errors]).to be_empty
      end
    end
  end
end
