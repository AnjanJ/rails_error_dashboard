# frozen_string_literal: true

require "rails_helper"

# Which streams the error list subscribes to, and through what. Each source
# carries a token from Services::LiveStreamToken, so names are read back
# through it.
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

  def sources
    Nokogiri::HTML(response.body).css("turbo-cable-stream-source")
  end

  def subscribed_streams
    sources.map do |source|
      RailsErrorDashboard::Services::LiveStreamToken.verify(source["signed-stream-name"])&.fetch(:stream)
    end
  end

  describe "how the list subscribes" do
    # live-updates-hardening-0-17/REQ-1
    it "subscribes through RED's channel, with tokens that expire 10 minutes after the render" do
      freeze_time do
        get "/error_dashboard/errors"

        expect(sources.size).to eq(2)
        sources.each do |source|
          expect(source["channel"]).to eq("RailsErrorDashboard::LiveUpdatesChannel")
          verified = RailsErrorDashboard::Services::LiveStreamToken.verify(source["signed-stream-name"])
          expect(verified[:expires_at]).to eq((Time.now + 10.minutes).to_i)
        end
      end
    end

    # live-updates-hardening-0-17/REQ-4: nothing on the page is a token Turbo's
    # channel would accept, so no copy of this page can open a feed through it.
    it "renders no token Turbo's channel would accept" do
      get "/error_dashboard/errors", params: { application_id: application.id }

      expect(sources).to be_present
      sources.each do |source|
        expect(Turbo::StreamsChannel.verified_stream_name(source["signed-stream-name"])).to be_nil
      end
      expect(response.body).not_to include("Turbo::StreamsChannel")
    end

    # live-updates-hardening-0-17/REQ-1: a token problem costs the page its live
    # updates, never the page.
    it "renders the list with no subscription and no Live badge when a token can't be issued" do
      allow(RailsErrorDashboard::Services::LiveStreamToken).to receive(:issue).and_return(nil)

      get "/error_dashboard/errors"

      expect(response).to have_http_status(:ok)
      expect(sources).to be_empty
      expect(Nokogiri::HTML(response.body).css(".bi-broadcast")).to be_empty
    end
  end

  it "subscribes the unfiltered list to the two global streams" do
    get "/error_dashboard/errors"

    expect(response).to have_http_status(:ok)
    expect(subscribed_streams).to contain_exactly("rails_error_dashboard:error_list", "rails_error_dashboard:error_updates")
  end

  it "subscribes an application-filtered list to that application's streams only" do
    get "/error_dashboard/errors", params: { application_id: application.id }

    id = application.id
    expect(subscribed_streams).to contain_exactly("rails_error_dashboard:error_list_app_#{id}", "rails_error_dashboard:error_updates_app_#{id}")
  end

  {
    "a platform filter" => { platform: "iOS" },
    "a search" => { search: "timeout" },
    "a status filter" => { status: "resolved" },
    "a sort" => { sort_by: "occurrence_count" },
    "the explicit all-statuses view" => { unresolved: "0" },
    "a later page" => { page: 2, per_page: 1 }
  }.each do |label, params|
    it "does not subscribe to new-row prepends with #{label}, but keeps updates" do
      get "/error_dashboard/errors", params: params

      expect(response).to have_http_status(:ok)
      expect(subscribed_streams).to contain_exactly("rails_error_dashboard:error_updates")
    end
  end

  # live-updates-hardening-0-17/REQ-11
  it "subscribes no list to a stats stream" do
    [ {}, { application_id: application.id }, { platform: "iOS" }, { application_id: application.id, page: 2, per_page: 1 } ]
      .each do |params|
        get "/error_dashboard/errors", params: params

        expect(subscribed_streams).to be_present
        expect(subscribed_streams.grep(/stats/)).to be_empty, "a stats stream for #{params.inspect}"
      end
  end

  it "combines both rules: application plus another filter" do
    get "/error_dashboard/errors", params: { application_id: application.id, platform: "iOS" }

    id = application.id
    expect(subscribed_streams).to contain_exactly("rails_error_dashboard:error_updates_app_#{id}")
  end

  it "never turns a hostile application_id into a stream name" do
    get "/error_dashboard/errors", params: { application_id: "7_evil" }

    expect(subscribed_streams).to all(match(/\Arails_error_dashboard:error_(list|updates)_app_0\z/))
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
    allow(broadcaster).to receive(:render_partial).and_return("<tr></tr>")
    row = RailsErrorDashboard::ErrorLog.last

    broadcaster.broadcast_new(row)
    broadcaster.broadcast_update(row)

    get "/error_dashboard/errors"
    global = subscribed_streams
    get "/error_dashboard/errors", params: { application_id: application.id }
    scoped = subscribed_streams

    expect(published.uniq).to match_array(global + scoped)
  end
end
