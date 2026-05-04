# frozen_string_literal: true

require "rails_helper"

# Regression: rescue_from Pagy::RangeError redirected to request.path which
# includes only the path component, dropping the entire query string. Users
# hitting an out-of-range page with active filters lost every filter on
# redirect.
RSpec.describe "Pagy out-of-range redirect", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    ActionController::Base.allow_forgery_protection = false
    create_list(:error_log, 3, application: application, error_type: "ArgumentError", resolved: false)
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    ActionController::Base.allow_forgery_protection = true
  end

  describe "GET /error_dashboard/errors with out-of-range page param" do
    it "redirects to page 1 of the same filter set, preserving the filters" do
      get "/error_dashboard/errors", params: {
        error_type: "ArgumentError",
        unresolved: "0",
        page: 999_999
      }
      expect(response).to have_http_status(:moved_permanently)
      expect(response.location).to include("error_type=ArgumentError")
      expect(response.location).to include("unresolved=0")
      expect(response.location).not_to include("page=999999")
      expect(response.location).not_to include("page=1") # not strictly required
    end

    it "redirects to bare path when no other params were provided" do
      get "/error_dashboard/errors", params: { page: 999_999 }
      expect(response).to have_http_status(:moved_permanently)
      expect(response.location).to end_with("/error_dashboard/errors")
    end

    it "drops per_page from the redirect target when per_page is invalid" do
      # Regression: an earlier version of this rescue preserved every query
      # param except :page. With per_page=-1 (Pagy::OptionError) the redirect
      # carried per_page=-1 forward, which re-triggered the same OptionError
      # on the next request — infinite redirect loop. Drop both :page and
      # :per_page when redirecting.
      get "/error_dashboard/errors", params: { per_page: "-1" }
      expect(response).to have_http_status(:moved_permanently)
      expect(response.location).not_to include("per_page=")
      # Following the redirect must reach 200, not loop.
      follow_redirect!
      expect(response).to have_http_status(:ok)
    end
  end
end
