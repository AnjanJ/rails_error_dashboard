# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Test Error action", type: :request do
  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    ActionController::Base.allow_forgery_protection = false
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    ActionController::Base.allow_forgery_protection = true
  end

  describe "POST /error_dashboard/errors/test_error" do
    it "creates a RailsErrorDashboard::TestError in the error log" do
      expect {
        post "/error_dashboard/errors/test_error"
      }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)

      error = RailsErrorDashboard::ErrorLog.last
      expect(error.error_type).to eq("RailsErrorDashboard::TestError")
      expect(error.message).to include("[RED Test]")
      expect(error.message).to include("safe to resolve or delete")
    end

    it "redirects to the errors index with a success flash" do
      post "/error_dashboard/errors/test_error"
      expect(response).to redirect_to("/error_dashboard/errors")
      follow_redirect!
      expect(response.body).to include("Test error logged successfully")
    end

    it "preserves application_id context" do
      app = create(:application, name: "TestApp")
      post "/error_dashboard/errors/test_error", params: { application_id: app.id }
      expect(response).to redirect_to("/error_dashboard/errors?application_id=#{app.id}")
    end
  end
end
