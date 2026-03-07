# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rack Attack Summary page", type: :request do
  let!(:application) { create(:application) }

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

    context "when breadcrumbs are disabled" do
      before do
        RailsErrorDashboard.configuration.enable_rack_attack_tracking = true
        RailsErrorDashboard.configuration.enable_breadcrumbs = false
      end

      it "redirects to errors index with alert" do
        get "/error_dashboard/errors/rack_attack_summary"
        expect(response).to redirect_to("/error_dashboard/errors")
        follow_redirect!
        expect(response.body).to include("Rack Attack tracking is not enabled")
      end
    end

    context "when both flags are enabled" do
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

      it "shows rack_attack events from breadcrumbs" do
        create(:error_log,
          application: application,
          breadcrumbs: [
            { "c" => "rack_attack", "m" => "throttle: login/ip (1.2.3.4) POST /login",
              "meta" => { "rule" => "login/ip", "type" => "throttle",
                          "discriminator" => "1.2.3.4", "path" => "/login", "method" => "POST" } }
          ].to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/rack_attack_summary"
        expect(response.body).to include("login/ip")
        expect(response.body).to include("bg-warning") # throttle badge
      end

      it "displays summary cards" do
        create(:error_log,
          application: application,
          breadcrumbs: [
            { "c" => "rack_attack", "m" => "throttle: test (1.1.1.1) GET /",
              "meta" => { "rule" => "test", "type" => "throttle",
                          "discriminator" => "1.1.1.1", "path" => "/", "method" => "GET" } }
          ].to_json,
          occurred_at: 1.day.ago)

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
        create(:error_log,
          application: application,
          breadcrumbs: [
            { "c" => "rack_attack", "m" => "throttle: x (1.1.1.1) GET /",
              "meta" => { "rule" => "x", "type" => "throttle",
                          "discriminator" => "1.1.1.1", "path" => "/", "method" => "GET" } }
          ].to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/rack_attack_summary"
        expect(response.body).to include("github.com/rack/rack-attack")
      end

      it "color-codes blocklist type as danger" do
        create(:error_log,
          application: application,
          breadcrumbs: [
            { "c" => "rack_attack", "m" => "blocklist: bad_ips (10.0.0.1) GET /admin",
              "meta" => { "rule" => "bad_ips", "type" => "blocklist",
                          "discriminator" => "10.0.0.1", "path" => "/admin", "method" => "GET" } }
          ].to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/rack_attack_summary"
        expect(response.body).to include("bg-danger")
        expect(response.body).to include("blocklist")
      end
    end
  end
end
