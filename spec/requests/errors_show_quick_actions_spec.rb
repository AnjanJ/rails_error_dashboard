# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Errors show — Quick Actions", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    ActionController::Base.allow_forgery_protection = false
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    ActionController::Base.allow_forgery_protection = true
  end

  describe "platform-filter quick action button" do
    # Regression: when error.platform is nil the button rendered with an empty
    # word ("View  Errors") and an essentially-broken filter link. Hide it
    # entirely instead — same pattern as the user_id button right above it.
    it "renders the button with the platform name when platform is set" do
      error = create(:error_log, application: application, platform: "iOS")
      get "/error_dashboard/errors/#{error.id}"
      expect(response.body).to include("View iOS Errors")
    end

    it "does not render the button when platform is nil" do
      error = create(:error_log, application: application, platform: nil)
      get "/error_dashboard/errors/#{error.id}"
      expect(response.body).not_to match(/View\s+Errors/)
    end

    it "does not render the button when platform is blank" do
      error = create(:error_log, application: application, platform: "")
      get "/error_dashboard/errors/#{error.id}"
      expect(response.body).not_to match(/View\s+Errors/)
    end
  end
end
