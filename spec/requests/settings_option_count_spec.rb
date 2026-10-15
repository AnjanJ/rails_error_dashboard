# frozen_string_literal: true

require "rails_helper"

# audit-fixes-0-16-0/REQ-13: each group's "N options" counted every row it
# defines, including the ones its show_if flags hide.
RSpec.describe "Settings option counts", type: :request do
  let(:config) { RailsErrorDashboard.configuration }

  around do |example|
    saved = [ config.authenticate_with, config.async_logging, config.enable_rate_limiting ]
    config.authenticate_with = -> { true }
    example.run
  ensure
    config.authenticate_with, config.async_logging, config.enable_rate_limiting = saved
  end

  # The Performance group: async_logging, async_adapter (shown with async
  # logging), enable_rate_limiting, rate_limit_per_minute (shown with it)
  def performance_header
    get "/error_dashboard/settings"
    Nokogiri::HTML(response.body).css("button[data-red-action='toggle-next']")
      .find { |button| button.at_css("i.bi-lightning-charge") }.text
  end

  it "counts only the options the group shows" do
    config.async_logging = false
    config.enable_rate_limiting = false
    expect(performance_header).to include("2 options")

    config.enable_rate_limiting = true
    expect(performance_header).to include("3 options")
  end
end
