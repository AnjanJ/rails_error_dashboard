# frozen_string_literal: true

module SystemHelpers
  def dashboard_username
    RailsErrorDashboard.configuration.dashboard_username
  end

  def dashboard_password
    RailsErrorDashboard.configuration.dashboard_password
  end

  # Visit a dashboard path with HTTP Basic Auth credentials embedded in the URL.
  # Cuprite (real Chrome) needs credentials in the URL since it can't use
  # rack_test's basic_authorize.
  def visit_dashboard(path = "")
    full_path = "/error_dashboard#{path}"
    server = Capybara.current_session.server
    visit "http://#{dashboard_username}:#{dashboard_password}@#{server.host}:#{server.port}#{full_path}"
  end

  def visit_error(error)
    visit_dashboard("/errors/#{error.id}")
  end

  # Wait for the dashboard layout to fully render
  def wait_for_page_load
    expect(page).to have_css("nav.navbar", wait: 10)
  end
end

RSpec.configure do |config|
  config.include SystemHelpers, type: :system
end
