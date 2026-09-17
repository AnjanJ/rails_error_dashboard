# frozen_string_literal: true

require "rails_helper"

# Which Turbo streams the error list subscribes to. Stream names are signed in
# the page, so they are read back through Turbo's own verifier.
RSpec.describe "Live stream scoping on the error list", type: :request do
  let!(:application) { create(:application) }
  let(:broadcaster) { RailsErrorDashboard::Services::ErrorBroadcaster }

  before do
    skip "turbo-rails is not loaded" unless defined?(Turbo::StreamsChannel)

    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    allow(broadcaster).to receive(:available?).and_return(true)
    2.times { create(:error_log, application: application, platform: "iOS") } # two, so page 2 exists
  end

  after { RailsErrorDashboard.configuration.authenticate_with = nil }

  def subscribed_streams
    response.body.scan(/signed-stream-name="([^"]+)"/).flatten.map do |signed|
      Turbo::StreamsChannel.verified_stream_name(signed)
    end
  end

  it "subscribes the unfiltered list to the three global streams" do
    get "/error_dashboard/errors"

    expect(response).to have_http_status(:ok)
    expect(subscribed_streams).to contain_exactly("error_list", "error_updates", "error_stats")
  end

  it "subscribes an application-filtered list to that application's streams only" do
    get "/error_dashboard/errors", params: { application_id: application.id }

    id = application.id
    expect(subscribed_streams).to contain_exactly("error_list_app_#{id}", "error_updates_app_#{id}", "error_stats_app_#{id}")
  end

  {
    "a platform filter" => { platform: "iOS" },
    "a search" => { search: "timeout" },
    "a status filter" => { status: "resolved" },
    "a sort" => { sort_by: "occurrence_count" },
    "the explicit all-statuses view" => { unresolved: "0" },
    "a later page" => { page: 2, per_page: 1 }
  }.each do |label, params|
    it "does not subscribe to new-row prepends with #{label}, but keeps updates and stats" do
      get "/error_dashboard/errors", params: params

      expect(response).to have_http_status(:ok)
      expect(subscribed_streams).to contain_exactly("error_updates", "error_stats")
    end
  end

  it "combines both rules: application plus another filter" do
    get "/error_dashboard/errors", params: { application_id: application.id, platform: "iOS" }

    id = application.id
    expect(subscribed_streams).to contain_exactly("error_updates_app_#{id}", "error_stats_app_#{id}")
  end

  it "never turns a hostile application_id into a stream name" do
    get "/error_dashboard/errors", params: { application_id: "7_evil" }

    expect(subscribed_streams).to all(match(/\Aerror_(list|updates|stats)_app_0\z/))
  end

  it "does not choke on a nested page parameter" do
    expect { get "/error_dashboard/errors", params: { page: { x: "1" } } }.not_to raise_error
    expect(response.status).to be < 500
  end

  it "subscribes to nothing when broadcasting is unavailable" do
    allow(broadcaster).to receive(:available?).and_return(false)

    get "/error_dashboard/errors"

    expect(subscribed_streams).to be_empty
  end

  it "uses exactly the names the broadcaster publishes to" do
    published = []
    channel = Turbo::StreamsChannel
    allow(channel).to receive(:broadcast_prepend_to) { |stream, **| published << stream }
    allow(channel).to receive(:broadcast_replace_to) { |stream, **| published << stream }
    allow(RailsErrorDashboard::Queries::DashboardStats).to receive(:call).and_return({ total_today: 1 })
    allow(broadcaster).to receive(:render_partial).and_return("<tr></tr>")
    row = RailsErrorDashboard::ErrorLog.last

    broadcaster.reset_throttle!
    broadcaster.broadcast_new(row)
    broadcaster.broadcast_update(row)

    get "/error_dashboard/errors"
    global = subscribed_streams
    get "/error_dashboard/errors", params: { application_id: application.id }
    scoped = subscribed_streams

    expect(published.uniq).to match_array(global + scoped)
  end
end
