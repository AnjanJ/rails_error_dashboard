# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Commands::FindOrCreateApplication do
  describe ".call" do
    context "when application does not exist" do
      it "creates a new application" do
        expect {
          described_class.call("MyNewApp")
        }.to change(RailsErrorDashboard::Application, :count).by(1)
      end

      it "returns the new application" do
        result = described_class.call("MyNewApp")

        expect(result).to be_a(RailsErrorDashboard::Application)
        expect(result.name).to eq("MyNewApp")
      end

      it "caches the application ID" do
        result = described_class.call("CachedApp")

        cached_id = Rails.cache.read("error_dashboard/application_id/CachedApp")
        expect(cached_id).to eq(result.id)
      end
    end

    context "when application already exists" do
      let!(:existing_app) { create(:application, name: "ExistingApp") }

      it "returns the existing application" do
        result = described_class.call("ExistingApp")

        expect(result.id).to eq(existing_app.id)
      end

      it "does not create a duplicate" do
        expect {
          described_class.call("ExistingApp")
        }.not_to change(RailsErrorDashboard::Application, :count)
      end

      it "caches the application ID for future lookups" do
        described_class.call("ExistingApp")

        cached_id = Rails.cache.read("error_dashboard/application_id/ExistingApp")
        expect(cached_id).to eq(existing_app.id)
      end
    end

    context "when application ID is cached" do
      let!(:existing_app) { create(:application, name: "CachedLookup") }

      before do
        Rails.cache.write("error_dashboard/application_id/CachedLookup", existing_app.id, expires_in: 1.hour)
      end

      it "returns the application from cache without DB query for find_by name" do
        result = described_class.call("CachedLookup")

        expect(result.id).to eq(existing_app.id)
      end
    end

    context "when cached ID is stale (record deleted)" do
      before do
        Rails.cache.write("error_dashboard/application_id/StaleApp", 999_999, expires_in: 1.hour)
      end

      it "clears stale cache and creates new application" do
        result = described_class.call("StaleApp")

        expect(result).to be_a(RailsErrorDashboard::Application)
        expect(result.name).to eq("StaleApp")

        # Cache should be updated with new ID
        cached_id = Rails.cache.read("error_dashboard/application_id/StaleApp")
        expect(cached_id).to eq(result.id)
      end
    end
  end
end
