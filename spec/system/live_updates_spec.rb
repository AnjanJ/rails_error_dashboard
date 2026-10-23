# frozen_string_literal: true

require "rails_helper"

# The browser half of live updates. Until 0.16.x no layer loaded the index in a
# browser and waited for a row: the delivery spec proved the server broadcast,
# and the index rendered stream tags, but the layout loaded no client to
# connect them, so nothing ever arrived.
#
# ActionCable runs on the in-process async adapter, and the turbo-rails client
# is the vendored copy served for its CDN URL under the same integrity check a
# browser applies in production (spec/support/capybara.rb).
RSpec.describe "Live updates in the browser", type: :system do
  let!(:application) { create(:application) }

  before do
    skip "turbo-rails is not loaded" unless defined?(Turbo::StreamsChannel)

    @original_cable = ActionCable.server.config.cable
    ActionCable.server.config.cable = { "adapter" => "async" }
    ActionCable.server.instance_variable_set(:@pubsub, nil)
    RailsErrorDashboard::Services::ErrorBroadcaster.instance_variable_set(:@broadcast_unavailable_until, nil)
    RailsErrorDashboard.configuration.enable_live_updates = true

    create(:error_log, application: application, occurred_at: 1.hour.ago)
  end

  after do
    RailsErrorDashboard.configuration.enable_live_updates = false
    ActionCable.server.config.cable = @original_cable
    ActionCable.server.instance_variable_set(:@pubsub, nil)
  end

  # Letters only: grouping normalises digits and hex, so a marker made of them
  # could join another group instead of making a new row.
  let(:marker) { "arrived live #{Array.new(8) { ('g'..'z').to_a.sample }.join}" }

  def open_index_and_wait_for_subscriptions
    visit_dashboard("/errors")
    wait_for_page_load
    # turbo-rails marks each source `connected` once its subscription is
    # confirmed; broadcasting before that would race the subscribe.
    expect(page).to have_css("turbo-cable-stream-source[connected]", visible: :all, minimum: 2, wait: 10)
  end

  def capture_new_error
    RailsErrorDashboard::Commands::LogError.call(RuntimeError.new(marker), {})
  end

  it "shows a newly captured error without a reload (live-updates-client/REQ-5)" do
    open_index_and_wait_for_subscriptions
    page.execute_script("window.__redSamePage = true")

    capture_new_error

    expect(page).to have_content(marker, wait: 10)
    expect(page.evaluate_script("window.__redSamePage")).to be true
  end

  it "still switches a local time to UTC and back on click (live-updates-client/REQ-7)" do
    open_index_and_wait_for_subscriptions
    time = first(".local-time")
    local_text = time.text

    time.click
    expect(time).to have_text("UTC")

    time.click
    expect(time).to have_text(local_text)
  end

  it "keeps Turbo Drive off: a sidebar link does a full page load (live-updates-client/REQ-8)" do
    open_index_and_wait_for_subscriptions
    page.execute_script("window.__redSamePage = true")

    find("a.nav-link[href*='/errors/analytics']", match: :first).click
    expect(page).to have_current_path(%r{/errors/analytics})
    wait_for_page_load

    expect(page.evaluate_script("window.__redSamePage")).to be_nil
  end

  it "formats a streamed row's relative time like the page's own rows (live-updates-client/REQ-13)" do
    open_index_and_wait_for_subscriptions

    capture_new_error
    row = find("tr", text: marker, wait: 10)

    # Only the layout's formatter sets data-showing-relative; the server
    # renders a bare time_ago_in_words in the host app's locale.
    expect(row).to have_css(".local-time-ago[data-showing-relative='true']")

    # A click inside a row also navigates to the error (the row handler on
    # document), for page rows too. A non-bubbling click reaches only the
    # element's own listener, which is the part that must be wired.
    page.execute_script(
      "arguments[0].dispatchEvent(new MouseEvent('click', { bubbles: false }))",
      row.find(".local-time-ago")
    )
    expect(row).to have_css(".local-time-ago[data-showing-relative='false']")
  end

  # Tokens that live 4 seconds, so the page renews every 2 seconds, and its
  # first tokens expire while the example runs.
  describe "renewing subscriptions" do
    let(:lifetime) { 4 }

    before { stub_const("RailsErrorDashboard::Services::LiveStreamToken::LIFETIME", lifetime.seconds) }

    def source_tokens
      page.evaluate_script(<<~JS)
        Array.prototype.map.call(document.querySelectorAll('turbo-cable-stream-source'),
          function(source) { return source.getAttribute('signed-stream-name'); })
      JS
    end

    # live-updates-hardening-0-17/REQ-8
    it "keeps showing new errors after the page's first tokens have expired, without a reload" do
      opened_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      open_index_and_wait_for_subscriptions
      first_tokens = source_tokens
      page.execute_script("window.__redSamePage = true")

      first_tokens.each do |token|
        expect(page).to have_no_css("turbo-cable-stream-source[signed-stream-name='#{token}']", visible: :all, wait: 10)
      end
      # Past the first tokens' expiry: the channel delivers nothing to them now.
      remaining = opened_at + lifetime + 0.5 - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      sleep(remaining) if remaining.positive?
      expect(page).to have_css("turbo-cable-stream-source[connected]", visible: :all, minimum: 2, wait: 10)

      capture_new_error

      expect(page).to have_content(marker, wait: 10)
      expect(page.evaluate_script("window.__redSamePage")).to be true
      expect(source_tokens & first_tokens).to be_empty
    end

    # live-updates-hardening-0-17/REQ-9
    it "hides the Live badge while renewal fails, and shows it again once renewal works" do
      open_index_and_wait_for_subscriptions
      expect(page).to have_css("#red-live-badge", visible: :visible)

      RailsErrorDashboard.configuration.enable_live_updates = false # renewals now answer 404
      expect(page).to have_css("#red-live-badge", visible: :hidden, wait: 10)

      RailsErrorDashboard.configuration.enable_live_updates = true
      expect(page).to have_css("#red-live-badge", visible: :visible, wait: 10)
    end

    # live-updates-hardening-0-17/REQ-3, end to end through a real Action
    # Cable server: once renewal is refused, the page keeps its first
    # subscriptions, and the channel stops delivering to them at expiry.
    it "stops delivering to subscriptions whose tokens have expired" do
      opened_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      open_index_and_wait_for_subscriptions
      RailsErrorDashboard.configuration.authenticate_with = -> { false }

      capture_new_error # control: the tokens are still valid
      expect(page).to have_content(marker, wait: 10)

      remaining = opened_at + lifetime + 0.5 - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      sleep(remaining) if remaining.positive?
      expect(page).to have_css("turbo-cable-stream-source[connected]", visible: :all, minimum: 2)
      late = "arrived late #{Array.new(8) { ('g'..'z').to_a.sample }.join}"
      RailsErrorDashboard::Commands::LogError.call(RuntimeError.new(late), {})

      expect(page).to have_no_content(late, wait: 5)
    ensure
      RailsErrorDashboard.configuration.authenticate_with = nil
    end

    # live-updates-hardening-0-17/REQ-9: a refusal is not retried on a timer.
    # With Basic auth every refused fetch can raise the browser's login prompt,
    # so the page waits until the viewer comes back to the tab.
    it "stops renewing once the dashboard refuses the viewer" do
      open_index_and_wait_for_subscriptions
      renewals = []
      counter = ->(*, payload) { renewals << payload[:status] if payload[:action] == "live_streams" }

      ActiveSupport::Notifications.subscribed(counter, "process_action.action_controller") do
        RailsErrorDashboard.configuration.authenticate_with = -> { false }
        expect(page).to have_css("#red-live-badge", visible: :hidden, wait: 10)
        refused = renewals.size

        sleep(3 * lifetime / 2.0) # three renewal periods

        expect(renewals.size).to eq(refused)
      end
    ensure
      RailsErrorDashboard.configuration.authenticate_with = nil
    end
  end
end
