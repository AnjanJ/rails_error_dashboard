# frozen_string_literal: true

require "rails_helper"

# The error page asks the issue tracker for the linked issue's state and
# comments, cached for 60 seconds. Only the happy path was actually cached: with
# no client configured, a failing API or a raising one, every page view asked
# again -- and a forge that is down answers slowly.
RSpec.describe "Issue tracker fetch caching", type: :request do
  let!(:application) { create(:application) }
  let(:error) { create(:error_log, application: application) }
  let(:config) { RailsErrorDashboard.configuration }
  let(:tracker) { RailsErrorDashboard::Services::IssueTrackerClient }
  let(:client) { instance_double(RailsErrorDashboard::Services::GitHubIssueClient) }

  around do |example|
    tracking = config.enable_issue_tracking
    config.authenticate_with = -> { true }
    config.enable_issue_tracking = true
    example.run
  ensure
    config.authenticate_with = nil
    config.enable_issue_tracking = tracking
  end

  before do
    # The dummy app's test cache is a null store; caching needs a real one.
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    error.update_columns(external_issue_url: "https://github.com/a/b/issues/1",
                         external_issue_number: 1, external_issue_provider: "github")
  end

  def view_twice
    2.times do
      get "/error_dashboard/errors/#{error.id}"
      expect(response).to have_http_status(:ok)
    end
  end

  it "asks for a client once per fetch, not once per page view, when none is configured" do
    allow(tracker).to receive(:for_error).and_return(nil)

    view_twice

    # One for the issue state, one for the comments.
    expect(tracker).to have_received(:for_error).twice
  end

  it "caches a failed API response" do
    allow(tracker).to receive(:for_error).and_return(client)
    allow(client).to receive(:fetch_issue).and_return({ success: false, error: "404" })
    allow(client).to receive(:fetch_comments).and_return({ success: false, error: "404" })

    view_twice

    expect(client).to have_received(:fetch_issue).once
    expect(client).to have_received(:fetch_comments).once
  end

  it "caches the failure when the client raises" do
    allow(tracker).to receive(:for_error).and_return(client)
    allow(client).to receive(:fetch_issue).and_raise(Timeout::Error)
    allow(client).to receive(:fetch_comments).and_raise(Timeout::Error)

    view_twice

    expect(client).to have_received(:fetch_issue).once
    expect(client).to have_received(:fetch_comments).once
  end

  it "still caches and renders a successful response" do
    allow(tracker).to receive(:for_error).and_return(client)
    allow(client).to receive(:fetch_issue).and_return({ success: true, state: "open", assignees: [], labels: [] })
    allow(client).to receive(:fetch_comments)
      .and_return({ success: true, comments: [ { author: "bob", body: "cached comment", created_at: "2026-01-01T00:00:00Z" } ] })

    view_twice

    expect(client).to have_received(:fetch_issue).once
    expect(client).to have_received(:fetch_comments).once
    expect(response.body).to include("cached comment")
  end

  it "maps the cached placeholder back to nothing when rendering" do
    allow(tracker).to receive(:for_error).and_return(nil)

    view_twice

    issue_card = Nokogiri::HTML(response.body).at_css("#issue-tracking")
    expect(issue_card.text).not_to include(RailsErrorDashboard::ErrorsController::NO_PLATFORM_DATA)
    expect(response.body).to include(I18n.t("red.errors.discussion.title"))
  end

  it "does not raise when the cache store itself fails" do
    broken = instance_double(ActiveSupport::Cache::MemoryStore)
    allow(broken).to receive(:fetch).and_raise(RuntimeError, "cache down")
    allow(Rails).to receive(:cache).and_return(broken)

    get "/error_dashboard/errors/#{error.id}"

    expect(response).to have_http_status(:ok)
  end
end
