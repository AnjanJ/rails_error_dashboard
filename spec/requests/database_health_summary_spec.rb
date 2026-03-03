# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Database Health Summary page", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.enable_system_health = false
  end

  describe "GET /error_dashboard/errors/database_health_summary" do
    context "when system_health is disabled" do
      before do
        RailsErrorDashboard.configuration.enable_system_health = false
      end

      it "redirects to errors index with alert" do
        get "/error_dashboard/errors/database_health_summary"
        expect(response).to redirect_to("/error_dashboard/errors")
        follow_redirect!
        expect(response.body).to include("System health is not enabled")
      end
    end

    context "when system_health is enabled" do
      before do
        RailsErrorDashboard.configuration.enable_system_health = true
      end

      it "returns 200" do
        get "/error_dashboard/errors/database_health_summary"
        expect(response).to have_http_status(:ok)
      end

      it "shows empty state when no pool data exists" do
        get "/error_dashboard/errors/database_health_summary"
        expect(response.body).to include("No Connection Pool Data Found")
      end

      it "shows pool stats from system_health" do
        create(:error_log,
          application: application,
          error_type: "ActiveRecord::ConnectionTimeoutError",
          system_health: {
            "connection_pool" => {
              "size" => 10,
              "busy" => 8,
              "dead" => 1,
              "idle" => 1,
              "waiting" => 2
            }
          }.to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/database_health_summary"
        expect(response.body).to include("ActiveRecord::ConnectionTimeoutError")
        expect(response.body).to include("80.0%")
      end

      it "displays summary cards" do
        create(:error_log,
          application: application,
          system_health: {
            "connection_pool" => {
              "size" => 10,
              "busy" => 5,
              "dead" => 1,
              "idle" => 4,
              "waiting" => 0
            }
          }.to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/database_health_summary"
        expect(response.body).to include("Errors with Pool Data")
        expect(response.body).to include("Peak Utilization")
        expect(response.body).to include("Total Dead")
        expect(response.body).to include("Total Waiting")
      end

      it "accepts days parameter" do
        get "/error_dashboard/errors/database_health_summary", params: { days: 7 }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("7 Days")
      end

      it "links to error detail pages" do
        error = create(:error_log,
          application: application,
          system_health: {
            "connection_pool" => {
              "size" => 5,
              "busy" => 1,
              "dead" => 0,
              "idle" => 4,
              "waiting" => 0
            }
          }.to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/database_health_summary"
        expect(response.body).to include("/error_dashboard/errors/#{error.id}")
      end

      it "shows Database Guide link" do
        create(:error_log,
          application: application,
          system_health: {
            "connection_pool" => {
              "size" => 5,
              "busy" => 1,
              "dead" => 0,
              "idle" => 4,
              "waiting" => 0
            }
          }.to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/database_health_summary"
        expect(response.body).to include("guides.rubyonrails.org/configuring.html")
      end

      it "color-codes high utilization with danger" do
        create(:error_log,
          application: application,
          system_health: {
            "connection_pool" => {
              "size" => 10,
              "busy" => 9,
              "dead" => 0,
              "idle" => 1,
              "waiting" => 0
            }
          }.to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/database_health_summary"
        expect(response.body).to include("bg-danger")
      end

      it "shows non-PostgreSQL info banner on SQLite" do
        allow(ActiveRecord::Base.connection).to receive(:adapter_name).and_return("SQLite")

        get "/error_dashboard/errors/database_health_summary"
        expect(response.body).to include("Non-PostgreSQL adapter detected")
        expect(response.body).to include("SQLite")
      end

      it "displays live connection pool section" do
        get "/error_dashboard/errors/database_health_summary"
        expect(response.body).to include("Live Database Health")
        expect(response.body).to include("Pool Size")
      end
    end
  end
end
