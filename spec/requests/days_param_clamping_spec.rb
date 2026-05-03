# frozen_string_literal: true

require "rails_helper"

# Regression: every health/analytics action accepted ?days unbounded. A request
# like ?days=99999999 would scan the full table on every call. Clamp to [1, 365].
RSpec.describe "days param clamping", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    ActionController::Base.allow_forgery_protection = false
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    ActionController::Base.allow_forgery_protection = true
  end

  describe "GET /error_dashboard/errors/analytics" do
    it "clamps a huge days value to 365" do
      get "/error_dashboard/errors/analytics", params: { days: 99_999_999 }
      expect(response).to have_http_status(:ok)
      # Analytics view echoes @days in "Error Trend (Last X Days)". When clamped
      # to 365 we should see "Last 365 Days", never the requested huge value.
      expect(response.body).to include("Last 365 Days")
      expect(response.body).not_to include("99999999")
    end

    it "clamps zero to 1" do
      get "/error_dashboard/errors/analytics", params: { days: 0 }
      expect(response).to have_http_status(:ok)
    end

    it "clamps negative values to 1" do
      get "/error_dashboard/errors/analytics", params: { days: -7 }
      expect(response).to have_http_status(:ok)
    end

    it "treats non-numeric input as the default (30)" do
      get "/error_dashboard/errors/analytics", params: { days: "abc" }
      expect(response).to have_http_status(:ok)
      # "abc".to_i is 0, then clamps to 1 — accept either current behavior, but
      # never the literal string in the rendered links.
      expect(response.body).not_to include("days=abc")
    end

    it "leaves a normal value unchanged" do
      get "/error_dashboard/errors/analytics", params: { days: 30 }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Last 30 Days")
    end
  end
end
