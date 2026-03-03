# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Authentication", type: :request do
  let!(:application) { create(:application) }

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
  end

  describe "default Basic Auth (authenticate_with = nil)" do
    before do
      RailsErrorDashboard.configuration.authenticate_with = nil
    end

    it "allows access with valid credentials" do
      get "/error_dashboard",
        headers: basic_auth_headers("gandalf", "youshallnotpass")
      expect(response).to have_http_status(:ok)
    end

    it "denies access with no credentials" do
      get "/error_dashboard"
      expect(response).to have_http_status(:unauthorized)
    end

    it "denies access with wrong credentials" do
      get "/error_dashboard",
        headers: basic_auth_headers("wrong", "wrong")
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "custom authentication (authenticate_with set)" do
    it "allows access when lambda returns true" do
      RailsErrorDashboard.configuration.authenticate_with = -> { true }
      get "/error_dashboard"
      expect(response).to have_http_status(:ok)
    end

    it "denies access with 403 when lambda returns false" do
      RailsErrorDashboard.configuration.authenticate_with = -> { false }
      get "/error_dashboard"
      expect(response).to have_http_status(:forbidden)
    end

    it "denies access with 403 when lambda returns nil" do
      RailsErrorDashboard.configuration.authenticate_with = -> { nil }
      get "/error_dashboard"
      expect(response).to have_http_status(:forbidden)
    end

    it "gives lambda access to controller context via instance_exec" do
      RailsErrorDashboard.configuration.authenticate_with = -> {
        request.headers["X-Admin-Token"] == "secret123"
      }

      get "/error_dashboard",
        headers: { "X-Admin-Token" => "secret123" }
      expect(response).to have_http_status(:ok)
    end

    it "denies access when lambda raises NameError (e.g. current_user undefined)" do
      RailsErrorDashboard.configuration.authenticate_with = -> { current_user.admin? }

      allow(Rails.logger).to receive(:error).and_call_original
      expect(Rails.logger).to receive(:error).with(
        /\[RailsErrorDashboard\] authenticate_with lambda raised NameError/
      ).once

      get "/error_dashboard"
      expect(response).to have_http_status(:forbidden)
    end

    it "denies access when lambda raises StandardError" do
      RailsErrorDashboard.configuration.authenticate_with = -> { raise "boom" }

      allow(Rails.logger).to receive(:error).and_call_original
      expect(Rails.logger).to receive(:error).with(
        /\[RailsErrorDashboard\] authenticate_with lambda raised RuntimeError: boom/
      ).once

      get "/error_dashboard"
      expect(response).to have_http_status(:forbidden)
    end

    it "lambda takes priority over basic auth credentials" do
      RailsErrorDashboard.configuration.authenticate_with = -> { false }

      get "/error_dashboard",
        headers: basic_auth_headers("gandalf", "youshallnotpass")
      expect(response).to have_http_status(:forbidden)
    end

    it "honors redirect_to from lambda (no double-render)" do
      RailsErrorDashboard.configuration.authenticate_with = -> {
        redirect_to "https://example.com/login", allow_other_host: true
      }

      get "/error_dashboard"
      expect(response).to have_http_status(:redirect)
      expect(response.location).to eq("https://example.com/login")
    end
  end

  private

  def basic_auth_headers(username, password)
    {
      "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(username, password)
    }
  end
end
