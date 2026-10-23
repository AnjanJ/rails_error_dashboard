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
end
