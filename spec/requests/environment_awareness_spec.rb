# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Environment awareness in the dashboard", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    ActionController::Base.allow_forgery_protection = false
  end

  after do
    RailsErrorDashboard.reset_configuration!
    ActionController::Base.allow_forgery_protection = true
  end

  describe "errors index" do
    it "shows no environment select, column or chip when only one environment exists" do
      create(:error_log, application: application, environment: "production")
      get "/error_dashboard/errors"
      expect(response.body).not_to include("All Environments")
      expect(response.body).not_to include('data-environment-badge')
    end

    it "offers the environment select and column when two environments exist" do
      create(:error_log, application: application, environment: "production")
      create(:error_log, application: application, environment: "staging")
      get "/error_dashboard/errors"
      expect(response.body).to include("All Environments")
      expect(response.body).to include('data-environment-badge="production"')
      expect(response.body).to include('data-environment-badge="staging"')
    end

    it "filters by environment and renders the chip" do
      create(:error_log, application: application, environment: "production", message: "prod only boom")
      create(:error_log, application: application, environment: "staging", message: "staging only boom")
      get "/error_dashboard/errors", params: { environment: "staging" }
      expect(response.body).to include("staging only boom")
      expect(response.body).not_to include("prod only boom")
      expect(response.body).to include("Environment: staging")
    end
  end

  describe "error detail sidebar" do
    it "links the environment badge to the filtered index" do
      error = create(:error_log, application: application, environment: "staging")
      get "/error_dashboard/errors/#{error.id}"
      expect(response.body).to include("View all staging errors")
      expect(response.body).to include("environment=staging")
    end

    it "omits the environment block for a legacy row" do
      error = create(:error_log, application: application, environment: nil)
      get "/error_dashboard/errors/#{error.id}"
      expect(response.body).not_to include("View all  errors")
      expect(response.body).not_to include('data-environment-badge')
    end
  end

  describe "analytics" do
    it "renders the environment chart only with more than one environment" do
      create(:error_log, application: application, environment: "production", occurred_at: 1.hour.ago)
      Rails.cache.clear
      get "/error_dashboard/errors/analytics"
      expect(response.body).not_to include("errors-by-environment-chart")

      create(:error_log, application: application, environment: "staging", occurred_at: 1.hour.ago)
      Rails.cache.clear
      get "/error_dashboard/errors/analytics"
      expect(response.body).to include("errors-by-environment-chart")
      expect(response.body).to include("Errors by Environment")
    end
  end

  describe "settings" do
    it "lists environment and notification_environments" do
      RailsErrorDashboard.configuration.environment = "uat"
      RailsErrorDashboard.configuration.notification_environments = %w[production uat]
      RailsErrorDashboard.configuration.authenticate_with = -> { true }
      get "/error_dashboard/settings"
      expect(response.body).to include("uat")
      expect(response.body).to include("notification_environments")
    end
  end
end
