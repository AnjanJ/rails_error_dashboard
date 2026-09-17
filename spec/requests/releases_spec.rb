# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Releases page", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
  end

  describe "GET /error_dashboard/errors/releases" do
    it "returns 200" do
      get "/error_dashboard/errors/releases"
      expect(response).to have_http_status(:ok)
    end

    it "shows empty state when no version data exists" do
      get "/error_dashboard/errors/releases"
      expect(response.body).to include("No Release Data Found")
      expect(response.body).to include("config.app_version")
    end

    it "shows release timeline when version data exists" do
      create(:error_log, :with_version, application: application,
        app_version: "1.0.0", git_sha: "abc123", occurred_at: 5.days.ago)
      create(:error_log, :with_version, application: application,
        app_version: "1.1.0", git_sha: "def456", occurred_at: 2.days.ago)

      get "/error_dashboard/errors/releases"
      expect(response.body).to include("1.0.0")
      expect(response.body).to include("1.1.0")
      expect(response.body).to include("Release Timeline")
      expect(response.body).to include("Current Release")
    end

    # The summary cards describe every release, not the 25 on the page in view.
    context "with more releases than fit on one page" do
      before do
        30.times do |i|
          create(:error_log, :with_version, application: application,
            app_version: format("9.%02d.0", i), occurred_at: (40 - i).hours.ago)
        end
      end

      it "still shows the current release card on page 2" do
        get "/error_dashboard/errors/releases", params: { page: 2 }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Current Release")
        expect(response.body).to match(%r{Current Release:\s*<strong>9\.29\.0</strong>})
      end

      it "counts problematic releases across every page" do
        # The newest release (page 1) has far more than twice the average.
        10.times { create(:error_log, :with_version, application: application, app_version: "9.29.0", occurred_at: 1.hour.ago) }

        get "/error_dashboard/errors/releases", params: { page: 2 }

        expect(response.body).to match(%r{<div class="display-6 text-danger">1</div>})
      end

      it "shows the same current release card on page 1" do
        get "/error_dashboard/errors/releases"

        expect(response.body).to match(%r{Current Release:\s*<strong>9\.29\.0</strong>})
      end
    end

    it "displays summary cards" do
      create(:error_log, :with_version, application: application,
        app_version: "1.0.0", occurred_at: 5.days.ago)

      get "/error_dashboard/errors/releases"
      expect(response.body).to include("Releases")
      expect(response.body).to include("Avg Errors / Release")
      expect(response.body).to include("Problematic Releases")
    end

    it "accepts days parameter" do
      get "/error_dashboard/errors/releases", params: { days: 7 }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("7 Days")
    end

    it "defaults to 30 days when no days param" do
      get "/error_dashboard/errors/releases"
      expect(response).to have_http_status(:ok)
    end

    it "handles non-numeric days parameter gracefully" do
      get "/error_dashboard/errors/releases", params: { days: "abc" }
      expect(response).to have_http_status(:ok)
    end

    it "shows stability badges" do
      create(:error_log, :with_version, application: application,
        app_version: "1.0.0", occurred_at: 5.days.ago)

      get "/error_dashboard/errors/releases"
      expect(response.body).to include("Green")
    end

    it "shows new error badges" do
      create(:error_log, :with_version, application: application,
        app_version: "1.0.0", error_hash: "hash_a", occurred_at: 5.days.ago)

      get "/error_dashboard/errors/releases"
      expect(response.body).to match(/\d+ new|0 new/)
    end

    it "includes stability legend in footer" do
      create(:error_log, :with_version, application: application,
        app_version: "1.0.0", occurred_at: 5.days.ago)

      get "/error_dashboard/errors/releases"
      expect(response.body).to include("avg errors")
    end
  end
end
