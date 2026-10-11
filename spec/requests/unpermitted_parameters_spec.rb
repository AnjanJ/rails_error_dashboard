# frozen_string_literal: true

require "rails_helper"

# The index built its filter hash with params.permit(*FILTERABLE_PARAMS), which
# judges every key in the request. A stray utm_source, or the page and locale
# keys the dashboard itself appends, was an "unpermitted parameter" on every
# request: a log line by default, a 500 in a host that sets
# action_on_unpermitted_parameters = :raise.
RSpec.describe "Unknown query parameters", type: :request do
  before { RailsErrorDashboard.configuration.authenticate_with = -> { true } }

  after { RailsErrorDashboard.configuration.authenticate_with = nil }

  around do |example|
    previous = ActionController::Parameters.action_on_unpermitted_parameters
    ActionController::Parameters.action_on_unpermitted_parameters = :raise
    example.run
  ensure
    ActionController::Parameters.action_on_unpermitted_parameters = previous
  end

  it "renders the errors index under action_on_unpermitted_parameters = :raise" do
    create(:error_log, error_type: "NoMethodError")

    get "/error_dashboard/errors", params: { utm_source: "newsletter", page: 1, severity: "high", locale: "de" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("NoMethodError")
  end

  it "ignores a non-scalar value for a filter key instead of raising" do
    get "/error_dashboard/errors", params: { severity: { nested: "high" }, status: [ "new" ] }

    expect(response).to have_http_status(:ok)
  end

  it "renders the pages that build links from the filter params" do
    create(:application)

    %w[/error_dashboard /error_dashboard/errors/releases /error_dashboard/errors/analytics].each do |path|
      get path, params: { utm_campaign: "x" }
      expect(response).to have_http_status(:ok), "#{path} answered #{response.status}"
    end
  end
end
