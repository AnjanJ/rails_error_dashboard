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

  # Wait for the dashboard layout to fully render.
  #
  # The navbar assertion only proves the HTML arrived. Bootstrap's JS is loaded
  # from a CDN (see the layout's <script> tag), so `data-bs-*` behaviour —
  # modals, tooltips, dropdowns — stays inert until that script executes. A
  # click that lands in the gap silently does nothing, which surfaces later as
  # a confusing `Unable to find css "#someModal.show"`.
  #
  # Waiting for `window.bootstrap` closes that race for every interaction that
  # depends on Bootstrap behaviour.
  def wait_for_page_load
    expect(page).to have_css("header.red-navbar, nav.navbar", wait: 10)
    wait_for_bootstrap
    wait_for_content_fade_in
  end

  # `main { animation: contentFadeIn 0.15s ease; }` starts the page content at
  # opacity 0. Capybara treats an opacity-0 ancestor as invisible, so any
  # assertion that lands inside those 150ms sees nothing — `first(".local-time")`
  # returns nil and the caller skips rather than fails, which is the worst
  # possible way for this to surface.
  #
  # This never used to bite because every page spent about a second waiting on
  # CDN assets, which is far longer than the animation. Once #183 removed the
  # network from the critical path the suite got fast enough to outrun its own
  # fade-in. The animation is real behaviour, so the specs wait for it rather
  # than the layout dropping it.
  def wait_for_content_fade_in(timeout: 2)
    deadline = Time.now + timeout
    loop do
      settled = page.evaluate_script(<<~JS)
        (function() {
          var m = document.querySelector('main');
          if (!m) return true;
          return parseFloat(getComputedStyle(m).opacity) >= 1;
        })()
      JS
      return true if settled
      break if Time.now > deadline

      sleep 0.02
    end
    false
  rescue StandardError
    # Mid-navigation evaluate_script can raise; the caller's own assertion gives
    # the better message.
    false
  end

  # Block until Bootstrap's bundle has executed and registered its global.
  # Tolerates pages that legitimately never load it (rendered before the CDN
  # script, or a failure page) by falling through after the timeout rather
  # than raising — the caller's own assertion gives the better message.
  def wait_for_bootstrap(timeout: 10)
    deadline = Time.now + timeout
    loop do
      return true if page.evaluate_script("typeof window.bootstrap !== 'undefined' && !!window.bootstrap.Modal")
      break if Time.now > deadline

      sleep 0.05
    end
    false
  rescue StandardError
    # evaluate_script can raise if the page is mid-navigation; not worth failing
    # the example over — the subsequent Capybara assertion will report properly.
    false
  end

  # Expand the advanced filters section (collapsed by default)
  def expand_advanced_filters
    click_button "More filters"
  end
end

RSpec.configure do |config|
  config.include SystemHelpers, type: :system
end
