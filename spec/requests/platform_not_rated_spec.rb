# frozen_string_literal: true

require "rails_helper"

# audit-fixes-0-16-0/REQ-4: a lone platform is not rated, so both pages that
# show platform health must render a nil score as "Not rated", not compare it
# with a threshold.
RSpec.describe "Platform health for a lone platform", type: :request do
  let(:config) { RailsErrorDashboard.configuration }

  around do |example|
    saved = [ config.authenticate_with, config.enable_platform_comparison ]
    config.authenticate_with = -> { true }
    config.enable_platform_comparison = true
    example.run
  ensure
    config.authenticate_with, config.enable_platform_comparison = saved
  end

  before { 3.times { create(:error_log, platform: "iOS", occurred_at: 1.day.ago) } }

  it "shows Not rated on the overview" do
    get "/error_dashboard/overview"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Not rated")
  end

  it "shows Not rated on the platform comparison page, with no score" do
    get "/error_dashboard/errors/platform_comparison"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Not rated")
    # The score's own markup, not the raw body: an error link such as
    # /errors/1003 also contains "/100" once ids pass 100, which they do on
    # PostgreSQL and MySQL, where sequences survive the per-example rollback
    scores = Nokogiri::HTML(response.body).css("strong").map { |node| node.text.strip }
    expect(scores.grep(%r{\A\d+(\.\d+)?/100\z})).to be_empty
  end
end
