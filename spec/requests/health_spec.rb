# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Health check endpoint", type: :request do
  after { RailsErrorDashboard.reset_configuration! }

  def body
    JSON.parse(response.body)
  end

  describe "without credentials" do
    it "refuses like every other dashboard route" do
      get "/error_dashboard/health"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "with authenticate_with accepting" do
    before { RailsErrorDashboard.configuration.authenticate_with = -> { true } }

    it "answers 200 with the JSON report" do
      get "/error_dashboard/health"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(body["status"]).to eq("ok")
      expect(body["version"]).to eq(RailsErrorDashboard::VERSION)
      expect(body["checks"].keys).to contain_exactly("database", "errors", "queue", "storm_protection")
      expect(body["checks"]["database"]["status"]).to eq("ok")
    end

    it "is never cached by a proxy" do
      get "/error_dashboard/health"

      expect(response.headers["Cache-Control"]).to eq("no-store")
    end

    it "answers 503 when the error database is unreachable" do
      allow(RailsErrorDashboard::ErrorLogsRecord).to receive(:connection_pool)
        .and_raise(ActiveRecord::ConnectionNotEstablished)

      get "/error_dashboard/health"

      expect(response).to have_http_status(:service_unavailable)
      expect(body["status"]).to eq("down")
      expect(body["checks"]["database"]["error"]).to eq("ActiveRecord::ConnectionNotEstablished")
    end

    it "answers 200 and degraded while a storm is being shed" do
      RailsErrorDashboard.configuration.enable_storm_protection = true
      allow(RailsErrorDashboard::Services::StormProtection::Gate).to receive(:state).and_return(:open)

      get "/error_dashboard/health"

      expect(response).to have_http_status(:ok)
      expect(body["status"]).to eq("degraded")
      expect(body["checks"]["storm_protection"]["state"]).to eq("open")
    end

    it "answers JSON 503, not the HTML error page, if the query itself blows up" do
      allow(RailsErrorDashboard::Queries::HealthStatus).to receive(:call).and_raise(RuntimeError, "boom")
      allow(Rails.logger).to receive(:error)

      get "/error_dashboard/health"

      expect(response).to have_http_status(:service_unavailable)
      expect(response.media_type).to eq("application/json")
      expect(body).to include("status" => "down", "error" => "RuntimeError")
    end
  end

  describe "with Basic auth" do
    around do |example|
      config = RailsErrorDashboard.configuration
      user, pass = config.dashboard_username, config.dashboard_password
      config.dashboard_username = "monitor"
      config.dashboard_password = "a-long-monitoring-password"
      example.run
    ensure
      config.dashboard_username = user
      config.dashboard_password = pass
    end

    it "accepts the dashboard credentials, as an uptime monitor would send them" do
      get "/error_dashboard/health",
          headers: { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("monitor", "a-long-monitoring-password") }

      expect(response).to have_http_status(:ok)
      expect(body["status"]).to eq("ok")
    end
  end
end
