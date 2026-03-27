# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::UserImpactSummary do
  let!(:app) { create(:application) }

  describe ".call" do
    it "returns entries and summary keys" do
      result = described_class.call(30)
      expect(result).to have_key(:entries)
      expect(result).to have_key(:summary)
    end

    it "returns empty results when no errors with user_id exist" do
      create(:error_log, application: app, user_id: nil)

      result = described_class.call(30)
      expect(result[:entries]).to be_empty
      expect(result[:summary][:total_error_types_with_users]).to eq(0)
    end

    context "with user-attributed errors" do
      before do
        # NoMethodError: 3 unique users (1, 2, 3)
        create(:error_log, application: app, error_type: "NoMethodError", user_id: 1, occurred_at: 5.days.ago)
        create(:error_log, application: app, error_type: "NoMethodError", user_id: 2, occurred_at: 4.days.ago)
        create(:error_log, application: app, error_type: "NoMethodError", user_id: 3, occurred_at: 3.days.ago)
        create(:error_log, application: app, error_type: "NoMethodError", user_id: 1, occurred_at: 2.days.ago) # duplicate user

        # TypeError: 1 unique user (1) but 3 occurrences
        create(:error_log, application: app, error_type: "TypeError", user_id: 1, occurred_at: 5.days.ago)
        create(:error_log, application: app, error_type: "TypeError", user_id: 1, occurred_at: 4.days.ago)
        create(:error_log, application: app, error_type: "TypeError", user_id: 1, occurred_at: 3.days.ago)
      end

      it "ranks errors by unique users affected (not occurrence count)" do
        result = described_class.call(30, application_id: app.id)
        expect(result[:entries].first[:error_type]).to eq("NoMethodError")
        expect(result[:entries].first[:unique_users]).to eq(3)
      end

      it "includes total occurrences alongside unique users" do
        result = described_class.call(30, application_id: app.id)
        nme = result[:entries].find { |e| e[:error_type] == "NoMethodError" }
        expect(nme[:total_occurrences]).to eq(4)
      end

      it "distinguishes between user impact and occurrence frequency" do
        result = described_class.call(30, application_id: app.id)
        # TypeError has 3 occurrences but only 1 unique user
        te = result[:entries].find { |e| e[:error_type] == "TypeError" }
        expect(te[:unique_users]).to eq(1)
        expect(te[:total_occurrences]).to eq(3)
      end

      it "returns summary stats" do
        result = described_class.call(30, application_id: app.id)
        expect(result[:summary][:total_error_types_with_users]).to eq(2)
        expect(result[:summary][:most_impactful]).to eq("NoMethodError")
      end

      it "includes severity and last_seen" do
        result = described_class.call(30, application_id: app.id)
        entry = result[:entries].first
        expect(entry).to have_key(:severity)
        expect(entry).to have_key(:last_seen)
        expect(entry).to have_key(:id)
      end
    end

    context "filters" do
      it "respects the days parameter" do
        create(:error_log, application: app, error_type: "OldError", user_id: 1, occurred_at: 40.days.ago)
        create(:error_log, application: app, error_type: "RecentError", user_id: 2, occurred_at: 5.days.ago)

        result = described_class.call(30, application_id: app.id)
        types = result[:entries].map { |e| e[:error_type] }
        expect(types).to include("RecentError")
        expect(types).not_to include("OldError")
      end

      it "filters by application_id" do
        other_app = create(:application, name: "other-app")
        create(:error_log, application: app, error_type: "AppError", user_id: 1, occurred_at: 5.days.ago)
        create(:error_log, application: other_app, error_type: "OtherError", user_id: 2, occurred_at: 5.days.ago)

        result = described_class.call(30, application_id: app.id)
        types = result[:entries].map { |e| e[:error_type] }
        expect(types).to include("AppError")
        expect(types).not_to include("OtherError")
      end
    end

    context "error handling" do
      it "rescues and returns safe defaults" do
        allow(RailsErrorDashboard::ErrorLog).to receive(:where).and_raise(StandardError, "boom")

        result = described_class.call(30)
        expect(result[:entries]).to be_empty
        expect(result[:summary][:total_error_types_with_users]).to eq(0)
      end
    end
  end
end
