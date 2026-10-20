# frozen_string_literal: true

require "rails_helper"

# audit-fixes-0-16-1/REQ-11: platform names are brand values stored as written.
# Ruby's capitalize made chart labels "Ios" and "Api", and CSS text-capitalize
# made headings and badges "IOS" in some engines.
RSpec.describe "Platform names as stored", type: :request do
  let(:config) { RailsErrorDashboard.configuration }
  let(:platforms) { %w[iOS API] }

  around do |example|
    saved = [ config.authenticate_with, config.enable_platform_comparison, config.enable_error_correlation ]
    config.authenticate_with = -> { true }
    config.enable_platform_comparison = true
    config.enable_error_correlation = true
    example.run
  ensure
    config.authenticate_with, config.enable_platform_comparison, config.enable_error_correlation = saved
  end

  before do
    # Release 2.0.0 has five times the average release's errors, so
    # Correlation lists it as a problematic release, with its platforms
    platforms.each do |platform|
      5.times do
        create(:error_log, platform: platform, error_type: "NoMethodError", app_version: "2.0.0",
                           occurred_at: 2.days.ago, resolved_at: 1.day.ago)
      end
    end
    create(:error_log, platform: "iOS", error_type: "ArgumentError", app_version: "1.0.0", occurred_at: 2.days.ago)
    create(:error_log, platform: "iOS", error_type: "ArgumentError", app_version: "1.1.0", occurred_at: 2.days.ago)
  end

  def expect_names_as_stored(path, rendered_at_least:)
    get path
    expect(response).to have_http_status(:ok)

    doc = Nokogiri::HTML(response.body)
    shown = doc.css("h5, h6, .badge").map { |node| node.xpath("text()").text.strip }
    platforms.each { |platform| expect(shown.count(platform)).to be >= rendered_at_least }

    capitalized = doc.css(".text-capitalize").map { |node| node.xpath("text()").text.strip }
    expect(capitalized & platforms).to be_empty

    # Chart labels are JSON in the page's scripts
    expect(response.body.scan(/"(?:Ios|Api)"/)).to be_empty
  end

  it "audit-fixes-0-16-1/REQ-11 shows iOS and API as stored on Platform Comparison and Correlation" do
    # A health card heading, a severity heading and a cross-platform badge each
    expect_names_as_stored("/error_dashboard/errors/platform_comparison", rendered_at_least: 3)
    expect(response.body).to include('"iOS"', '"API"')

    # A problematic-release badge and a platform-specific heading each
    expect_names_as_stored("/error_dashboard/errors/correlation", rendered_at_least: 2)
  end
end
