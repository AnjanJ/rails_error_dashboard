# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::DashboardStats do
  describe ".call" do
    # Freeze at noon to avoid midnight boundary flakes with relative times
    around { |example| travel_to(Time.current.noon) { example.run } }

    let!(:error_today1) { create(:error_log, occurred_at: 2.hours.ago, resolved: false) }
    let!(:error_today2) { create(:error_log, occurred_at: 1.hour.ago, resolved: true) }
    let!(:error_this_week) { create(:error_log, occurred_at: 3.days.ago, resolved: false) }
    let!(:error_this_month) { create(:error_log, occurred_at: 15.days.ago, resolved: true) }
    let!(:error_old) { create(:error_log, occurred_at: 45.days.ago, resolved: false) }

    it "returns hash with all statistics" do
      result = described_class.call

      expect(result).to be_a(Hash)
      expect(result.keys).to include(
        :total_today, :total_week, :total_month,
        :unresolved, :resolved,
        :by_platform, :top_errors
      )
    end

    describe "time-based counts" do
      it "counts errors from today" do
        result = described_class.call

        expect(result[:total_today]).to eq(2)
      end

      it "counts errors from last 7 days" do
        result = described_class.call

        expect(result[:total_week]).to eq(3)
      end

      it "counts errors from last 30 days" do
        result = described_class.call

        expect(result[:total_month]).to eq(4)
      end
    end

    describe "resolution status counts" do
      it "counts unresolved errors" do
        result = described_class.call

        expect(result[:unresolved]).to eq(3)
      end

      it "counts resolved errors" do
        result = described_class.call

        expect(result[:resolved]).to eq(2)
      end
    end

    describe "grouping by platform" do
      let!(:ios_error) { create(:error_log, platform: "iOS") }
      let!(:android_error1) { create(:error_log, platform: "Android") }
      let!(:android_error2) { create(:error_log, platform: "Android") }
      let!(:api_error) { create(:error_log, platform: "API") }

      it "groups errors by platform" do
        result = described_class.call

        expect(result[:by_platform]).to be_a(Hash)
        expect(result[:by_platform]["iOS"]).to eq(1)
        expect(result[:by_platform]["Android"]).to eq(2)
        expect(result[:by_platform]["API"]).to eq(1)
      end
    end

    describe "top errors" do
      let!(:error1) { create(:error_log, error_type: "NoMethodError", occurred_at: 1.day.ago) }
      let!(:error2) { create(:error_log, error_type: "NoMethodError", occurred_at: 2.days.ago) }
      let!(:error3) { create(:error_log, error_type: "NoMethodError", occurred_at: 3.days.ago) }
      let!(:error4) { create(:error_log, error_type: "ArgumentError", occurred_at: 1.day.ago) }
      let!(:error5) { create(:error_log, error_type: "ArgumentError", occurred_at: 2.days.ago) }
      let!(:error6) { create(:error_log, error_type: "TypeError", occurred_at: 1.day.ago) }

      it "returns top 10 error types from last 7 days" do
        result = described_class.call

        expect(result[:top_errors]).to be_a(Hash)
        expect(result[:top_errors].length).to be <= 10
      end

      it "sorts errors by count descending" do
        result = described_class.call

        error_counts = result[:top_errors].values
        expect(error_counts).to eq(error_counts.sort.reverse)
      end

      it "includes error counts" do
        result = described_class.call

        expect(result[:top_errors]["NoMethodError"]).to eq(3)
        expect(result[:top_errors]["ArgumentError"]).to eq(2)
        expect(result[:top_errors]["TypeError"]).to eq(1)
      end

      it "excludes errors older than 7 days" do
        create(:error_log, error_type: "OldError", occurred_at: 10.days.ago)

        result = described_class.call

        expect(result[:top_errors]).not_to have_key("OldError")
      end

      context "with more than 10 error types" do
        before do
          11.times do |i|
            create(:error_log, error_type: "Error#{i}", occurred_at: 1.day.ago)
          end
        end

        it "limits to 10 error types" do
          result = described_class.call

          expect(result[:top_errors].length).to eq(10)
        end
      end
    end

    context "with no errors" do
      before do
        RailsErrorDashboard::ErrorLog.destroy_all
      end

      it "returns zero counts" do
        result = described_class.call

        expect(result[:total_today]).to eq(0)
        expect(result[:total_week]).to eq(0)
        expect(result[:total_month]).to eq(0)
        expect(result[:unresolved]).to eq(0)
        expect(result[:resolved]).to eq(0)
      end

      it "returns empty hashes for groupings" do
        result = described_class.call

        expect(result[:by_platform]).to eq({})
        expect(result[:top_errors]).to eq({})
      end
    end

    context "at different times of day" do
      it "counts errors occurring on current day boundary" do
        create(:error_log, occurred_at: Time.current.beginning_of_day)

        result = described_class.call

        expect(result[:total_today]).to be >= 1
      end
    end
  end
end
