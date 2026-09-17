# frozen_string_literal: true

require "rails_helper"

# application_id is echoed into every navigation link by the layout. A nested
# value (application_id[x]=1) cannot be turned into a query string, so url_for
# raised and every page answered 500.
RSpec.describe "A nested application_id parameter", type: :request do
  let!(:application) { create(:application) }

  before { RailsErrorDashboard.configuration.authenticate_with = -> { true } }
  after { RailsErrorDashboard.configuration.authenticate_with = nil }

  [ "/error_dashboard", "/error_dashboard/errors", "/error_dashboard/errors/analytics" ].each do |path|
    it "is ignored on #{path}" do
      get path, params: { application_id: { "x" => "1" } }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Something went wrong")
    end
  end

  it "still scopes to a plain application_id" do
    get "/error_dashboard/errors", params: { application_id: application.id }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("application_id=#{application.id}")
  end
end
