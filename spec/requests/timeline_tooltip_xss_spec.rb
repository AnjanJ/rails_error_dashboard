# frozen_string_literal: true

require "rails_helper"

# Regression: the resolved-badge tooltip on _timeline.html.erb had
# data-bs-html="true" and only escaped double-quotes via gsub('"', '&quot;').
# A resolution_comment containing HTML (e.g. <img src=x onerror=...>) would
# render as live HTML inside the Bootstrap tooltip on hover, executing
# stored XSS for any dashboard viewer.
#
# Fix: drop data-bs-html and let ERB's default attribute escaping handle the
# title. Tooltip displays the comment as plain text.
RSpec.describe "Timeline tooltip XSS protection", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    ActionController::Base.allow_forgery_protection = false
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    ActionController::Base.allow_forgery_protection = true
  end

  it "renders the tooltip without data-bs-html when the comment contains HTML" do
    create(:error_log, application: application,
                    error_type: "TestError",
                    resolved: true,
                    resolved_at: 1.hour.ago,
                    resolved_by_name: "tester",
                    resolution_comment: '<img src=x onerror="alert(1)">')

    # Visit a sibling error so the resolved one appears in related-errors timeline.
    sibling = create(:error_log, application: application, error_type: "TestError")

    get "/error_dashboard/errors/#{sibling.id}"
    expect(response).to have_http_status(:ok)

    # The tooltip badge MUST NOT carry data-bs-html="true" — that's what would
    # make Bootstrap render the title as innerHTML and execute the script.
    expect(response.body).not_to include('data-bs-html="true"')

    # The HTML payload must be rendered escaped in the title attribute
    expect(response.body).to include("&lt;img src=x onerror=")
    # And must NOT appear unescaped anywhere in the page
    expect(response.body).not_to include('<img src=x onerror="alert(1)">')
  end
end
