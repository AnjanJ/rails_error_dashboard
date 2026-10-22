# frozen_string_literal: true

require "rails_helper"

# Whether the dashboard loads the live-updates client, and where it points it.
# A reachable (async, in-process) pubsub in every example, so that with the
# switch off nothing but the switch can explain a missing tag.
RSpec.describe "Live updates client on the dashboard", type: :request do
  let(:helper_module) { RailsErrorDashboard::ApplicationHelper }
  let(:client_url) { helper_module::LIVE_UPDATES_CLIENT_URL }
  let!(:error_log) { create(:error_log) }

  before do
    skip "turbo-rails is not loaded" unless defined?(Turbo::StreamsChannel)

    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    @original_cable = ActionCable.server.config.cable
    ActionCable.server.config.cable = { "adapter" => "async" }
    ActionCable.server.instance_variable_set(:@pubsub, nil)
    RailsErrorDashboard::Services::ErrorBroadcaster.instance_variable_set(:@broadcast_unavailable_until, nil)
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.enable_live_updates = false
    ActionCable.server.config.cable = @original_cable
    ActionCable.server.instance_variable_set(:@pubsub, nil)
  end

  def page
    Nokogiri::HTML(response.body)
  end

  def client_script
    page.at_css("head script[type='module'][src='#{client_url}']")
  end

  context "with the switch off (the default)" do
    it "renders no subscription, no client script and no Live badge (live-updates-client/REQ-3)" do
      get "/error_dashboard/errors"

      expect(response).to have_http_status(:ok)
      expect(page.css("turbo-cable-stream-source")).to be_empty
      expect(response.body).not_to include(client_url)
      expect(page.css(".bi-broadcast")).to be_empty
    end
  end

  context "with the switch on and the pubsub reachable" do
    before { RailsErrorDashboard.configuration.enable_live_updates = true }

    it "subscribes and shows the Live badge (control for REQ-3)" do
      get "/error_dashboard/errors"

      expect(page.css("turbo-cable-stream-source")).not_to be_empty
      expect(page.css(".bi-broadcast")).not_to be_empty
    end

    it "loads the pinned client in <head> with its integrity hash (live-updates-client/REQ-4)" do
      get "/error_dashboard/errors"

      expect(client_script).to be_present
      expect(client_url).to match(%r{\Ahttps://cdn\.jsdelivr\.net/npm/@hotwired/turbo-rails@\d+\.\d+\.\d+/})
      expect(client_script["integrity"]).to eq(helper_module::LIVE_UPDATES_CLIENT_INTEGRITY)
      expect(client_script["integrity"]).to start_with("sha384-")
      expect(client_script["crossorigin"]).to eq("anonymous")
    end

    it "loads no client on a page that does not subscribe (live-updates-client/REQ-6)" do
      get "/error_dashboard/errors/#{error_log.id}"

      expect(response).to have_http_status(:ok)
      expect(page.css("turbo-cable-stream-source")).to be_empty
      expect(response.body).not_to include(client_url)
    end

    describe "where the client connects (live-updates-client/REQ-9)" do
      around do |example|
        config = ActionCable.server.config
        url, mount_path = config.url, config.mount_path
        example.run
      ensure
        config.url = url
        config.mount_path = mount_path
      end

      def cable_meta
        page.at_css("head meta[name='action-cable-url']")
      end

      it "names the host's configured cable URL" do
        ActionCable.server.config.url = "wss://cable.example.test/live"

        get "/error_dashboard/errors"

        expect(cable_meta&.[]("content")).to eq("wss://cable.example.test/live")
      end

      it "names the host's mount path when no URL is set" do
        ActionCable.server.config.url = nil
        ActionCable.server.config.mount_path = "/custom-cable"

        get "/error_dashboard/errors"

        expect(cable_meta&.[]("content")).to eq("/custom-cable")
      end

      it "still renders the page when neither is set (the client then uses /cable)" do
        ActionCable.server.config.url = nil
        ActionCable.server.config.mount_path = nil

        get "/error_dashboard/errors"

        expect(response).to have_http_status(:ok)
        expect(client_script).to be_present
        expect(cable_meta).to be_nil
      end
    end
  end
end
