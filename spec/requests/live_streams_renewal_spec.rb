# frozen_string_literal: true

require "rails_helper"

# An open error list renews its live-update tokens here before they expire.
# The renewal answers only a viewer who passes the dashboard's own
# authentication, so losing dashboard access ends a live feed within one token
# lifetime. It returns exactly the streams the list subscribes to, because the
# list hands over its own query string and both ends ask the same method.
RSpec.describe "Renewing live-update subscriptions", type: :request do
  let!(:application) { create(:application) }
  let(:broadcaster) { RailsErrorDashboard::Services::ErrorBroadcaster }
  let(:token_service) { RailsErrorDashboard::Services::LiveStreamToken }
  let(:renew_path) { "/error_dashboard/errors/live_streams" }

  before do
    allow(broadcaster).to receive(:available?).and_return(true)
    2.times { create(:error_log, application: application, platform: "iOS") } # two, so page 2 exists
  end

  after { RailsErrorDashboard.configuration.authenticate_with = nil }

  def verified_stream(token)
    token_service.verify(token)&.fetch(:stream)
  end

  # Opens the list, then renews the way its script does: from the URL the
  # page itself carries.
  def page_and_renewal(query)
    get(query.empty? ? "/error_dashboard/errors" : "/error_dashboard/errors?#{query}")
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    on_page = html.css("turbo-cable-stream-source").to_h do |source|
      [ source["red-live-kind"], verified_stream(source["signed-stream-name"]) ]
    end

    get html.at_css("#red-live-streams")["data-renew-url"]
    expect(response).to have_http_status(:ok)
    renewed = JSON.parse(response.body).fetch("tokens").transform_values { |token| verified_stream(token) }

    [ on_page, renewed ]
  end

  context "for a viewer the dashboard lets in" do
    before { RailsErrorDashboard.configuration.authenticate_with = -> { true } }

    # live-updates-hardening-0-17/REQ-6
    it "renews exactly the streams the list subscribes to, for every kind of list" do
      queries = [
        "",
        "application_id=#{application.id}",
        "platform=iOS",
        "sort_by=occurrence_count",
        "page=2&per_page=1",
        "platform%5B%5D=iOS",
        "application_id=#{application.id}&platform=iOS"
      ]

      queries.each do |query|
        on_page, renewed = page_and_renewal(query)

        expect(on_page).to be_present, "no subscriptions for ?#{query}"
        expect(renewed).to eq(on_page), "renewal for ?#{query} named #{renewed.inspect}, page has #{on_page.inspect}"
      end
    end

    it "returns fresh tokens, valid for 10 minutes from the renewal, that no cache keeps" do
      get "/error_dashboard/errors"
      first = Nokogiri::HTML(response.body).css("turbo-cable-stream-source").map { |source| source["signed-stream-name"] }

      travel 5.minutes do
        get renew_path

        tokens = JSON.parse(response.body).fetch("tokens").values
        expect(tokens & first).to be_empty
        tokens.each { |token| expect(token_service.verify(token)[:expires_at]).to eq((Time.now + 10.minutes).to_i) }
        expect(response.headers["Cache-Control"]).to include("no-store")
      end
    end

    it "tells the page how often to renew: at half a token's lifetime" do
      get "/error_dashboard/errors"

      container = Nokogiri::HTML(response.body).at_css("#red-live-streams")
      expect(container["data-renew-every"]).to eq((token_service::LIFETIME / 2).in_milliseconds.to_i.to_s)
    end

    it "answers 404 while live updates are unavailable" do
      allow(broadcaster).to receive(:available?).and_return(false)

      get renew_path

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include("tokens")
    end

    it "answers 503, not an error page, when a token can't be issued" do
      allow(token_service).to receive(:issue).and_return(nil)

      get renew_path

      expect(response).to have_http_status(:service_unavailable)
      expect(response.body).to be_empty
    end
  end

  # live-updates-hardening-0-17/REQ-7
  describe "for a viewer the dashboard refuses" do
    it "gives a request without Basic credentials no token" do
      get renew_path

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).not_to include("tokens")
    end

    it "gives a viewer the host's authenticate_with lambda denies no token" do
      RailsErrorDashboard.configuration.authenticate_with = -> { false }

      get renew_path

      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include("tokens")
    end
  end
end
