# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Storm history page + banner", type: :request do
  let!(:application) { create(:application) }
  let(:auth) { {} }

  before { RailsErrorDashboard.configuration.authenticate_with = -> { true } }
  after { RailsErrorDashboard.reset_configuration! }

  describe "GET /errors/storms" do
    it "renders the empty state when no storms have occurred" do
      get "/error_dashboard/errors/storms", headers: auth

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No Storms Recorded")
    end

    it "lists recorded storm episodes with exact counts" do
      RailsErrorDashboard::StormEvent.create!(
        started_at: 2.hours.ago, ended_at: 1.hour.ago,
        peak_rate_per_minute: 4200, reached_open: true,
        events_counted_only: 48_231, events_overflow: 120,
        fingerprints_affected: 37,
        top_fingerprints: [ { "class" => "NoMethodError", "message" => "boom", "count" => 40_000 } ].to_json
      )

      get "/error_dashboard/errors/storms", headers: auth

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("48,231")
      expect(response.body).to include("count-only")
      expect(response.body).to include("NoMethodError")
    end

    it "flags an active storm" do
      RailsErrorDashboard::StormEvent.create!(started_at: 5.minutes.ago, peak_rate_per_minute: 900)

      get "/error_dashboard/errors/storms", headers: auth

      expect(response.body).to include("Storm in progress")
    end
  end

  describe "layout banner" do
    before { RailsErrorDashboard.configuration.enable_storm_protection = true }

    it "shows the active-storm banner on any dashboard page" do
      RailsErrorDashboard::StormEvent.create!(started_at: 5.minutes.ago, reached_open: true)

      get "/error_dashboard/errors", headers: auth

      expect(response.body).to include("Error storm in progress")
      expect(response.body).to include("count-only mode")
    end

    it "shows the recently-ended banner within 24 hours" do
      RailsErrorDashboard::StormEvent.create!(
        started_at: 3.hours.ago, ended_at: 2.hours.ago, events_counted_only: 500
      )

      get "/error_dashboard/errors", headers: auth

      expect(response.body).to include("Storm protection engaged recently")
    end

    it "shows no banner for old storms" do
      RailsErrorDashboard::StormEvent.create!(
        started_at: 3.days.ago, ended_at: 2.days.ago
      )

      get "/error_dashboard/errors", headers: auth

      expect(response.body).not_to include("storm-banner")
    end

    it "shows no banner when storm protection is disabled" do
      RailsErrorDashboard.configuration.enable_storm_protection = false
      RailsErrorDashboard::StormEvent.create!(started_at: 5.minutes.ago)

      get "/error_dashboard/errors", headers: auth

      expect(response.body).not_to include("storm-banner")
    end
  end
end
