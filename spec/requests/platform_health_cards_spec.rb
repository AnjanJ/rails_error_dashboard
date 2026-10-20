# frozen_string_literal: true

require "rails_helper"

# audit-fixes-0-16-1: the platform health cards on the Overview and on Platform
# Comparison. Both pages read PlatformComparison#platform_health_summary.
RSpec.describe "Platform health cards", type: :request do
  let(:config) { RailsErrorDashboard.configuration }

  around do |example|
    saved = [ config.authenticate_with, config.enable_platform_comparison ]
    config.authenticate_with = -> { true }
    config.enable_platform_comparison = true
    example.run
  ensure
    config.authenticate_with, config.enable_platform_comparison = saved
  end

  # Platform name => the text of its health card on the Overview
  def overview_cards
    get "/error_dashboard/overview"
    expect(response).to have_http_status(:ok)

    section = Nokogiri::HTML(response.body).at_xpath(
      "//div[contains(concat(' ', normalize-space(@class), ' '), ' card ')][.//span[normalize-space() = 'Platform Health']]"
    )
    return {} unless section

    section.css("span.badge").to_h { |badge| [ badge.previous_element.text.strip, badge.parent.parent.text.squish ] }
  end

  # Platform name => the text of its health card on Platform Comparison
  def platform_comparison_cards
    get "/error_dashboard/errors/platform_comparison"
    expect(response).to have_http_status(:ok)

    Nokogiri::HTML(response.body).css("h5.card-title").to_h do |title|
      [ title.xpath("text()").text.strip, title.ancestors(".card").first.text.squish ]
    end
  end

  context "with a platform that has no errors in the window" do
    before do
      2.times { create(:error_log, platform: "iOS", occurred_at: 1.day.ago) }
      2.times { create(:error_log, platform: "Android", occurred_at: 1.day.ago) }
      create(:error_log, platform: "Web", occurred_at: 60.days.ago)
    end

    it "audit-fixes-0-16-1/REQ-8 shows no card for it on the Overview or Platform Comparison" do
      expect(overview_cards.keys).to contain_exactly("iOS", "Android")
      expect(platform_comparison_cards.keys).to contain_exactly("iOS", "Android")
    end
  end
end
