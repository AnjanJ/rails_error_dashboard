# frozen_string_literal: true

require "capybara/rspec"
require "capybara/cuprite"

# Register Cuprite driver (Chrome DevTools Protocol — no Selenium/chromedriver needed)
Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [ 1400, 900 ],
    browser_options: {
      "no-sandbox" => nil,
      "disable-gpu" => nil,
      "disable-dev-shm-usage" => nil
    },
    process_timeout: 15,
    timeout: 10,
    inspector: ENV["INSPECTOR"].present?,
    headless: ENV.fetch("HEADLESS", "true") != "false"
  )
end

# Default driver for non-system specs (no browser needed)
Capybara.default_driver = :rack_test
Capybara.javascript_driver = :cuprite
Capybara.default_max_wait_time = 5

# Use Puma as the test server (silent mode to suppress request logs)
Capybara.server = :puma, { Silent: true }

RSpec.configure do |config|
  # System specs always use Cuprite (real browser)
  config.before(:each, type: :system) do
    driven_by :cuprite
  end

  # Allow CDN requests for system specs (Bootstrap, Chart.js loaded via CDN)
  config.before(:each, type: :system) do
    WebMock.disable_net_connect!(
      allow_localhost: true,
      allow: [
        "cdn.jsdelivr.net",
        "cdnjs.cloudflare.com",
        "127.0.0.1"
      ]
    )
  end

  config.after(:each, type: :system) do
    WebMock.disable_net_connect!(allow_localhost: true)
  end
end
