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
    # NO SYSTEM SPEC MAY TOUCH THE NETWORK (issue #183).
    #
    # The dashboard layout pulls assets from three external hosts on every page
    # load. Cuprite waits for all in-flight requests before `visit` returns, so
    # any slow response surfaced as `Ferrum::PendingConnectionsError` /
    # `Ferrum::TimeoutError` on a spec with nothing wrong with it.
    #
    # Two earlier attempts fixed instances rather than the class. de6d077 listed
    # eight jsdelivr PATHS and missed the font hosts; adding those then exposed
    # `bootstrap-icons.woff2`, a sub-resource of an already-blocked stylesheet.
    # Enumerating paths cannot win: every asset can pull further assets, and any
    # version bump in the layout rots the list.
    #
    # So the blocklist is now HOST-level and total. Charts, syntax highlighting,
    # icon fonts, webfonts and Stimulus are not asserted on by any system spec
    # and degrade gracefully by design (CLAUDE.md — the layout must work with
    # CDNs unavailable).
    #
    # bootstrap.bundle.min.js is the one asset that cannot simply be blocked:
    # wait_for_page_load calls wait_for_bootstrap, so EVERY system spec waits on
    # `window.bootstrap` before it does anything. Blocking it would hang every
    # spec for the full 10s timeout; leaving it on the network is what kept this
    # suite dependent on a CDN.
    #
    # url_blacklist is NOT used, because it cannot express "serve this one from
    # disk". Cuprite implements it as its own `page.on(:request)` handler that
    # aborts on match, and a second handler cannot un-abort — both run, and the
    # abort wins. EXTERNAL_REQUEST_HANDLER below replaces it with a single
    # handler that respond/abort/continues, which can.
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

# The scripts specs actually execute, vendored so the suite never fetches them.
# Everything else the layout loads is decorative and simply aborted.
#
# Each is pinned to the version the layout requests. If a <script> tag in
# app/views/layouts/rails_error_dashboard.html.erb is bumped, re-download the
# matching file here or the specs will exercise a different library than
# production ships. The regexes below deliberately accept ANY version so a bump
# keeps working (with the vendored copy) rather than silently falling through to
# an abort, which would turn assertions into skips.
VENDORED_SCRIPTS = {
  # Modal specs need real Bootstrap behaviour, and wait_for_page_load blocks on
  # `window.bootstrap` for EVERY system spec.
  %r{cdn\.jsdelivr\.net/npm/bootstrap@[\d.]+/dist/js/bootstrap\.bundle\.min\.js} =>
    "bootstrap.bundle.min.js",
  # chart_date_locale_spec asks Chart.js what it drew to verify the localized
  # date adapter (#178); without these it skips instead of asserting.
  %r{cdn\.jsdelivr\.net/npm/chart\.js@[\d.]+/dist/chart\.umd\.min\.js} =>
    "chart.umd.min.js",
  %r{cdn\.jsdelivr\.net/npm/chartjs-adapter-date-fns@[\d.]+/dist/chartjs-adapter-date-fns\.bundle\.min\.js} =>
    "chartjs-adapter-date-fns.bundle.min.js",
  %r{cdn\.jsdelivr\.net/npm/chartkick@[\d.]+/dist/chartkick\.min\.js} =>
    "chartkick.min.js"
}.freeze

VENDORED_SCRIPT_BODIES = VENDORED_SCRIPTS.to_h do |pattern, filename|
  path = File.expand_path("vendor/#{filename}", __dir__)
  raise "Missing vendored script #{path} — see spec/support/vendor/README.md" unless File.exist?(path)

  [ pattern, File.read(path).freeze ]
end.freeze

# Every host the layout reaches for. Host-level, so a version bump or a new
# sub-resource cannot slip through the way bootstrap-icons.woff2 did (#183).
EXTERNAL_ASSET_HOSTS = %r{\Ahttps?://(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|fonts\.googleapis\.com|fonts\.gstatic\.com)}

RSpec.configure do |config|
  # System specs always use Cuprite (real browser)
  config.before(:each, type: :system) do
    driven_by :cuprite

    # One handler, registered per example because Capybara hands out a fresh
    # page after each reset. Serve Bootstrap from disk, abort every other
    # external asset, let localhost through.
    page.driver.browser.network.intercept
    page.driver.browser.page.on(:request) do |request|
      vendored = VENDORED_SCRIPT_BODIES.find { |pattern, _| request.match?(pattern) }

      if vendored
        request.respond(
          responseCode: 200,
          body: vendored.last,
          responseHeaders: { "Content-Type" => "application/javascript" }
        )
      elsif request.url.match?(EXTERNAL_ASSET_HOSTS)
        request.abort
      else
        request.continue
      end
    end
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
