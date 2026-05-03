# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::AnalyticsStats do
  describe ".call" do
    let!(:error1) { create(:error_log, occurred_at: 1.day.ago, resolved: false, platform: "iOS") }
    let!(:error2) { create(:error_log, occurred_at: 2.days.ago, resolved: true, platform: "Android") }
    let!(:error3) { create(:error_log, occurred_at: 5.days.ago, resolved: false, platform: "API") }
    let!(:old_error) { create(:error_log, occurred_at: 45.days.ago, resolved: false) }

    it "returns hash with all analytics data" do
      result = described_class.call

      expect(result).to be_a(Hash)
      expect(result.keys).to include(
        :days, :error_stats, :errors_over_time,
        :errors_by_type, :errors_by_platform,
        :errors_by_hour, :top_users, :resolution_rate,
        :mobile_errors, :api_errors
      )
    end

    it "includes the number of days" do
      result = described_class.call(30)

      expect(result[:days]).to eq(30)
    end

    describe "error statistics" do
      it "includes total count" do
        result = described_class.call(30)

        expect(result[:error_stats][:total]).to eq(3)
      end

      it "includes unresolved count" do
        result = described_class.call(30)

        expect(result[:error_stats][:unresolved]).to eq(2)
      end

      it "groups by error type" do
        result = described_class.call(30)

        expect(result[:error_stats][:by_type]).to be_a(Hash)
      end

      it "groups by day" do
        result = described_class.call(30)

        expect(result[:error_stats][:by_day]).to be_a(Hash)
      end

      it "sorts error types by count descending" do
        # Parent context has 3 StandardError instances (error1, error2, error3)
        # Create 3 NoMethodError to outnumber them
        create(:error_log, error_type: "NoMethodError", occurred_at: 1.day.ago)
        create(:error_log, error_type: "NoMethodError", occurred_at: 2.days.ago)
        create(:error_log, error_type: "NoMethodError", occurred_at: 3.days.ago)
        create(:error_log, error_type: "NoMethodError", occurred_at: 4.days.ago)
        create(:error_log, error_type: "ArgumentError", occurred_at: 1.day.ago)

        result = described_class.call(30)

        error_types = result[:error_stats][:by_type].keys
        expect(error_types.first).to eq("NoMethodError")
      end
    end

    describe "errors over time" do
      it "groups errors by day" do
        result = described_class.call(30)

        expect(result[:errors_over_time]).to be_a(Hash)
      end

      it "includes dates as keys" do
        result = described_class.call(30)

        expect(result[:errors_over_time].keys.first).to be_a(Date)
      end
    end

    describe "errors by type" do
      it "returns top 10 error types" do
        result = described_class.call(30)

        expect(result[:errors_by_type]).to be_a(Hash)
        expect(result[:errors_by_type].length).to be <= 10
      end

      it "sorts by count descending" do
        create(:error_log, error_type: "Error1", occurred_at: 1.day.ago)
        create(:error_log, error_type: "Error1", occurred_at: 2.days.ago)
        create(:error_log, error_type: "Error2", occurred_at: 1.day.ago)

        result = described_class.call(30)

        counts = result[:errors_by_type].values
        expect(counts).to eq(counts.sort.reverse)
      end

      context "with more than 10 error types" do
        before do
          12.times do |i|
            create(:error_log, error_type: "Error#{i}", occurred_at: 1.day.ago)
          end
        end

        it "limits to 10 types" do
          result = described_class.call(30)

          expect(result[:errors_by_type].length).to eq(10)
        end
      end
    end

    describe "errors by platform" do
      it "groups errors by platform" do
        result = described_class.call(30)

        expect(result[:errors_by_platform]).to be_a(Hash)
        expect(result[:errors_by_platform]["iOS"]).to eq(1)
        expect(result[:errors_by_platform]["Android"]).to eq(1)
        expect(result[:errors_by_platform]["API"]).to eq(1)
      end
    end

    describe "errors by hour" do
      it "groups errors by hour of day" do
        result = described_class.call(30)

        expect(result[:errors_by_hour]).to be_a(Hash)
      end

      it "uses hour-of-day integer keys (0..23) so the chart shows diurnal patterns" do
        # Regression: was group_by_hour returning chronological Time keys; now
        # group_by_hour_of_day returns Integer 0..23 keys matching the chart's
        # "Errors by Hour of Day" title and x-axis label.
        result = described_class.call(30)
        keys = result[:errors_by_hour].keys

        unless keys.empty?
          expect(keys.first).to be_a(Integer)
          expect(keys).to all(be_between(0, 23))
        end
      end
    end

    describe "top affected users" do
      context "when User model is not defined" do
        it "returns empty array" do
          allow(RailsErrorDashboard.configuration).to receive(:user_model).and_return(nil)

          result = described_class.call(30)

          expect(result[:top_users]).to eq([])
        end
      end

      context "when errors have user_id" do
        let!(:user_error1) { create(:error_log, user_id: 1, occurred_at: 1.day.ago) }
        let!(:user_error2) { create(:error_log, user_id: 1, occurred_at: 2.days.ago) }
        let!(:user_error3) { create(:error_log, user_id: 2, occurred_at: 1.day.ago) }

        before do
          allow(RailsErrorDashboard.configuration).to receive(:user_model).and_return("User")
        end

        it "returns array of user data hashes" do
          result = described_class.call(30)

          expect(result[:top_users]).to be_a(Array)
          expect(result[:top_users].first).to have_key(:user_id)
          expect(result[:top_users].first).to have_key(:email)
          expect(result[:top_users].first).to have_key(:count)
        end

        it "limits to top 10 users" do
          15.times do |i|
            create(:error_log, user_id: i + 10, occurred_at: 1.day.ago)
          end

          result = described_class.call(30)

          expect(result[:top_users].length).to be <= 10
        end

        it "sorts by error count descending" do
          result = described_class.call(30)

          counts = result[:top_users].map { |u| u[:count] }
          expect(counts).to eq(counts.sort.reverse)
        end

        it "handles missing users gracefully" do
          result = described_class.call(30)

          emails = result[:top_users].map { |u| u[:email] }
          expect(emails).to all(match(/User #\d+/))
        end
      end
    end

    describe "resolution rate" do
      context "with no errors" do
        before do
          RailsErrorDashboard::ErrorLog.destroy_all
        end

        it "returns 0" do
          result = described_class.call(30)

          expect(result[:resolution_rate]).to eq(0)
        end
      end

      context "with errors" do
        # Note: Parent context has error1 (unresolved), error2 (resolved), error3 (unresolved) = 1 resolved, 2 unresolved
        # This context adds: resolved1, resolved2, unresolved = 2 resolved, 1 unresolved
        # Total: 3 resolved, 3 unresolved = 50%
        let!(:resolved1) { create(:error_log, occurred_at: 1.day.ago, resolved: true) }
        let!(:resolved2) { create(:error_log, occurred_at: 2.days.ago, resolved: true) }
        let!(:unresolved) { create(:error_log, occurred_at: 3.days.ago, resolved: false) }

        it "calculates percentage of resolved errors" do
          result = described_class.call(30)

          expect(result[:resolution_rate]).to be_within(0.1).of(50.0)
        end

        it "rounds to 1 decimal place" do
          result = described_class.call(30)

          expect(result[:resolution_rate].to_s.split(".").last.length).to be <= 1
        end
      end

      context "with all errors resolved" do
        before do
          RailsErrorDashboard::ErrorLog.update_all(resolved: true)
        end

        it "returns 100%" do
          result = described_class.call(30)

          expect(result[:resolution_rate]).to eq(100.0)
        end
      end
    end

    describe "mobile errors count" do
      it "counts iOS and Android errors" do
        result = described_class.call(30)

        expect(result[:mobile_errors]).to eq(2) # iOS + Android
      end

      it "excludes API errors" do
        create(:error_log, platform: "API", occurred_at: 1.day.ago)

        result = described_class.call(30)

        expect(result[:mobile_errors]).to eq(2)
      end
    end

    describe "API errors count" do
      it "counts API platform errors" do
        result = described_class.call(30)

        expect(result[:api_errors]).to eq(1)
      end

      it "includes errors with nil platform" do
        create(:error_log, platform: nil, occurred_at: 1.day.ago)

        result = described_class.call(30)

        expect(result[:api_errors]).to eq(2)
      end
    end

    describe "custom time range" do
      it "accepts custom days parameter" do
        result = described_class.call(7)

        expect(result[:days]).to eq(7)
      end

      it "filters errors by custom date range" do
        create(:error_log, occurred_at: 3.days.ago)
        create(:error_log, occurred_at: 10.days.ago)

        result = described_class.call(7)

        # Parent context has error1 (1 day), error2 (2 days), error3 (5 days) = 3 errors within 7 days
        # This test adds one at 3 days = 1 more within 7 days
        # Total: 4 errors within 7 days
        expect(result[:error_stats][:total]).to eq(4)
      end

      it "defaults to 30 days" do
        result = described_class.call

        expect(result[:days]).to eq(30)
      end
    end

    context "with no errors in time range" do
      before do
        RailsErrorDashboard::ErrorLog.destroy_all
      end

      it "returns zero counts" do
        result = described_class.call(30)

        expect(result[:error_stats][:total]).to eq(0)
        expect(result[:mobile_errors]).to eq(0)
        expect(result[:api_errors]).to eq(0)
      end

      it "returns empty hashes for groupings" do
        result = described_class.call(30)

        expect(result[:errors_by_type]).to eq({})
        expect(result[:errors_by_platform]).to eq({})
        expect(result[:top_users]).to eq([])
      end
    end
  end
end
