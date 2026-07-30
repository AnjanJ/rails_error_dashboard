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
    # The dashboard layout pulls nine assets from jsdelivr on EVERY page load
    # (see the layout's <head> and footer). Cuprite waits for all in-flight
    # requests before `visit` returns, so a slow or flaky CDN surfaced as
    # `Ferrum::PendingConnectionsError` / `Ferrum::TimeoutError` — the root
    # cause of the intermittent system-spec failures, and of the modal
    # failures downstream of them (Bootstrap's JS comes from the same CDN).
    #
    # Blocking the purely decorative assets removes that network dependency.
    # Charts, syntax highlighting, icon fonts, and Stimulus are not asserted on
    # by any system spec; they degrade gracefully by design (see CLAUDE.md —
    # the layout must work with CDNs unavailable).
    #
    # bootstrap.bundle.min.js is deliberately NOT blocked: the modal specs need
    # real Bootstrap behaviour. See ModalHelpers for the timing guards that
    # cover its load latency.
    url_blacklist: [
      %r{cdn\.jsdelivr\.net/npm/chart\.js},
      %r{cdn\.jsdelivr\.net/npm/chartjs-adapter-date-fns},
      %r{cdn\.jsdelivr\.net/npm/chartkick},
      %r{cdn\.jsdelivr\.net/npm/bootstrap-icons},
      %r{cdn\.jsdelivr\.net/npm/@catppuccin},
      %r{cdn\.jsdelivr\.net/gh/highlightjs},
      %r{cdn\.jsdelivr\.net/npm/highlightjs-line-numbers},
      %r{cdn\.jsdelivr\.net/npm/@hotwired/stimulus}
    ],
    process_timeout: 15,
    timeout: 30,
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
