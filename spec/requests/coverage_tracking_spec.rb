# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Coverage tracking", type: :request do
  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    ActionController::Base.allow_forgery_protection = false
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.enable_coverage_tracking = false
    ActionController::Base.allow_forgery_protection = true
    RailsErrorDashboard::Services::CoverageTracker.disable! if RailsErrorDashboard::Services::CoverageTracker.active?
  end

  describe "POST /error_dashboard/errors/enable_coverage" do
    context "when coverage tracking is enabled in config" do
      before do
        RailsErrorDashboard.configuration.enable_coverage_tracking = true
      end

      it "enables coverage and redirects" do
        post "/error_dashboard/errors/enable_coverage", headers: { "HTTP_REFERER" => "/error_dashboard/errors" }
        expect(response).to have_http_status(:redirect)
      end

      it "activates the coverage tracker" do
        post "/error_dashboard/errors/enable_coverage", headers: { "HTTP_REFERER" => "/error_dashboard/errors" }
        expect(RailsErrorDashboard::Services::CoverageTracker.active?).to be true
      end

      it "sets flash notice" do
        post "/error_dashboard/errors/enable_coverage", headers: { "HTTP_REFERER" => "/error_dashboard/errors" }
        follow_redirect!
        expect(flash[:notice]).to include("coverage enabled").or include("Coverage")
      end
    end

    context "when coverage tracking is disabled in config" do
      before do
        RailsErrorDashboard.configuration.enable_coverage_tracking = false
      end

      it "redirects to errors index with alert" do
        post "/error_dashboard/errors/enable_coverage"
        expect(response).to redirect_to("/error_dashboard/errors")
      end

      it "does not activate coverage" do
        post "/error_dashboard/errors/enable_coverage"
        expect(RailsErrorDashboard::Services::CoverageTracker.active?).to be false
      end
    end
  end

  describe "POST /error_dashboard/errors/disable_coverage" do
    before do
      RailsErrorDashboard.configuration.enable_coverage_tracking = true
      RailsErrorDashboard::Services::CoverageTracker.enable!
    end

    it "disables coverage and redirects" do
      post "/error_dashboard/errors/disable_coverage", headers: { "HTTP_REFERER" => "/error_dashboard/errors" }
      expect(response).to have_http_status(:redirect)
      expect(RailsErrorDashboard::Services::CoverageTracker.active?).to be false
    end

    it "is safe to call when already disabled" do
      RailsErrorDashboard::Services::CoverageTracker.disable!
      post "/error_dashboard/errors/disable_coverage", headers: { "HTTP_REFERER" => "/error_dashboard/errors" }
      expect(response).to have_http_status(:redirect)
    end
  end
end
