# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rack Attack Summary page", type: :request do
  let!(:application) { create(:application) }

  def create_event(rule:, match_type: "throttle", discriminator: "1.2.3.4",
                   path: "/login", http_method: "POST", count: 1)
    RailsErrorDashboard::RackAttackEvent.create!(
      rule: rule,
      match_type: match_type,
      discriminator: discriminator,
      path: path,
      http_method: http_method,
      event_count: count,
      period_hour: 1.day.ago.beginning_of_hour,
      last_seen_at: 1.day.ago
    )
  end

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.enable_breadcrumbs = false
    RailsErrorDashboard.configuration.enable_rack_attack_tracking = false
  end

  describe "GET /error_dashboard/errors/rack_attack_summary" do
    context "when rack_attack tracking is disabled" do
      before do
        RailsErrorDashboard.configuration.enable_rack_attack_tracking = false
        RailsErrorDashboard.configuration.enable_breadcrumbs = true
      end

      it "redirects to errors index with alert" do
        get "/error_dashboard/errors/rack_attack_summary"
        expect(response).to redirect_to("/error_dashboard/errors")
        follow_redirect!
        expect(response.body).to include("Rack Attack tracking is not enabled")
      end
    end

    # Breadcrumbs are no longer a prerequisite — events persist independently
    # of error capture (issue #143).
    context "when tracking is enabled but breadcrumbs are disabled" do
      before do
        RailsErrorDashboard.configuration.enable_rack_attack_tracking = true
        RailsErrorDashboard.configuration.enable_breadcrumbs = false
      end

      it "still renders the page" do
        get "/error_dashboard/errors/rack_attack_summary"
        expect(response).to have_http_status(:ok)
      end

      it "shows recorded events" do
        create_event(rule: "logins/ip")

        get "/error_dashboard/errors/rack_attack_summary"
        expect(response.body).to include("logins/ip")
      end
    end

    context "when tracking is enabled" do
      before do
        RailsErrorDashboard.configuration.enable_breadcrumbs = true
        RailsErrorDashboard.configuration.enable_rack_attack_tracking = true
      end

      it "returns 200" do
        get "/error_dashboard/errors/rack_attack_summary"
        expect(response).to have_http_status(:ok)
      end

      it "shows empty state when no rack_attack events exist" do
        get "/error_dashboard/errors/rack_attack_summary"
        expect(response.body).to include("No Rate Limit Events Found")
      end

      it "shows recorded rack_attack events" do
        create_event(rule: "login/ip")

        get "/error_dashboard/errors/rack_attack_summary"
        expect(response.body).to include("login/ip")
        expect(response.body).to include("bg-warning") # throttle badge
      end

      it "displays summary cards" do
        create_event(rule: "test", discriminator: "1.1.1.1", path: "/", http_method: "GET")

        get "/error_dashboard/errors/rack_attack_summary"
        expect(response.body).to include("Unique Rules")
        expect(response.body).to include("Total Events")
        expect(response.body).to include("Unique IPs")
      end

      it "accepts days parameter" do
        get "/error_dashboard/errors/rack_attack_summary", params: { days: 7 }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("7 Days")
      end

      it "includes Rack Attack docs link" do
        create_event(rule: "x", discriminator: "1.1.1.1", path: "/", http_method: "GET")

        get "/error_dashboard/errors/rack_attack_summary"
        expect(response.body).to include("github.com/rack/rack-attack")
      end

      it "color-codes blocklist type as danger" do
        create_event(rule: "bad_ips", match_type: "blocklist",
                     discriminator: "10.0.0.1", path: "/admin", http_method: "GET")

        get "/error_dashboard/errors/rack_attack_summary"
        expect(response.body).to include("bg-danger")
        expect(response.body).to include("blocklist")
      end
    end
  end
end
