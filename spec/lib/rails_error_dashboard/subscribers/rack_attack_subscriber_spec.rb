# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Subscribers::RackAttackSubscriber do
  let(:collector) { RailsErrorDashboard::Services::BreadcrumbCollector }

  before do
    RailsErrorDashboard.configuration.enable_breadcrumbs = true
    collector.init_buffer
  end

  after do
    described_class.unsubscribe!
    collector.clear_buffer
    RailsErrorDashboard.reset_configuration!
  end

  describe ".subscribe!" do
    it "registers all expected event subscribers" do
      subscriptions = described_class.subscribe!
      expect(subscriptions).to be_an(Array)
      expect(subscriptions.size).to eq(3)
    end

    it "stores subscriptions for later cleanup" do
      described_class.subscribe!
      expect(described_class.subscriptions).not_to be_empty
    end
  end

  describe ".unsubscribe!" do
    it "removes all subscriptions" do
      described_class.subscribe!
      expect(described_class.subscriptions).not_to be_empty

      described_class.unsubscribe!
      expect(described_class.subscriptions).to be_empty
    end
  end

  describe "throttle.rack_attack subscriber" do
    before { described_class.subscribe! }

    it "adds rack_attack breadcrumb with throttle details" do
      request = double("Rack::Request",
        env: {
          "rack.attack.matched" => "login/ip",
          "rack.attack.match_type" => :throttle,
          "rack.attack.match_discriminator" => "192.168.1.1"
        },
        path: "/login",
        request_method: "POST")

      ActiveSupport::Notifications.instrument("throttle.rack_attack", { request: request }) { }

      breadcrumbs = collector.harvest
      ra_crumbs = breadcrumbs.select { |c| c[:c] == "rack_attack" }
      expect(ra_crumbs).not_to be_empty

      crumb = ra_crumbs.last
      expect(crumb[:m]).to eq("throttle: login/ip (192.168.1.1) POST /login")
      expect(crumb[:meta][:rule]).to eq("login/ip")
      expect(crumb[:meta][:type]).to eq("throttle")
      expect(crumb[:meta][:discriminator]).to eq("192.168.1.1")
      expect(crumb[:meta][:path]).to eq("/login")
      expect(crumb[:meta][:method]).to eq("POST")
    end
  end

  describe "blocklist.rack_attack subscriber" do
    before { described_class.subscribe! }

    it "adds rack_attack breadcrumb with blocklist details" do
      request = double("Rack::Request",
        env: {
          "rack.attack.matched" => "bad_ips",
          "rack.attack.match_type" => :blocklist,
          "rack.attack.match_discriminator" => "10.0.0.1"
        },
        path: "/api/data",
        request_method: "GET")

      ActiveSupport::Notifications.instrument("blocklist.rack_attack", { request: request }) { }

      breadcrumbs = collector.harvest
      ra_crumbs = breadcrumbs.select { |c| c[:c] == "rack_attack" }
      expect(ra_crumbs).not_to be_empty

      crumb = ra_crumbs.last
      expect(crumb[:m]).to eq("blocklist: bad_ips (10.0.0.1) GET /api/data")
      expect(crumb[:meta][:rule]).to eq("bad_ips")
      expect(crumb[:meta][:type]).to eq("blocklist")
    end
  end

  describe "track.rack_attack subscriber" do
    before { described_class.subscribe! }

    # A plain `track` rule (no :limit/:period) is a Rack::Attack::Check, and Check
    # NEVER writes "rack.attack.match_discriminator" into the env — only Throttle
    # does. These doubles therefore omit that key deliberately: including it would
    # make the fixture more generous than reality and hide issue #170.
    it "adds rack_attack breadcrumb with track details" do
      request = double("Rack::Request",
        env: {
          "rack.attack.matched" => "api_usage",
          "rack.attack.match_type" => :track
        },
        path: "/api/v1/users",
        request_method: "GET",
        ip: "203.0.113.7")

      ActiveSupport::Notifications.instrument("track.rack_attack", { request: request }) { }

      breadcrumbs = collector.harvest
      ra_crumbs = breadcrumbs.select { |c| c[:c] == "rack_attack" }
      expect(ra_crumbs).not_to be_empty

      crumb = ra_crumbs.last
      expect(crumb[:m]).to eq("track: api_usage (203.0.113.7) GET /api/v1/users")
      expect(crumb[:meta][:type]).to eq("track")
    end

    it "falls back to the client IP when Check omits the discriminator (issue #170)" do
      request = double("Rack::Request",
        env: {
          "rack.attack.matched" => "requests accepting markdown",
          "rack.attack.match_type" => :track
        },
        path: "/doc",
        request_method: "GET",
        ip: "198.51.100.42")

      ActiveSupport::Notifications.instrument("track.rack_attack", { request: request }) { }

      crumb = collector.harvest.select { |c| c[:c] == "rack_attack" }.last
      expect(crumb[:meta][:discriminator]).to eq("198.51.100.42")
    end

    it "prefers an explicit discriminator over the IP fallback" do
      # A counted track (limit:/period:) routes through Throttle, which DOES set
      # the discriminator — that value must win over request.ip.
      request = double("Rack::Request",
        env: {
          "rack.attack.matched" => "api_usage",
          "rack.attack.match_type" => :track,
          "rack.attack.match_discriminator" => "user_42"
        },
        path: "/api/v1/users",
        request_method: "GET",
        ip: "203.0.113.7")

      ActiveSupport::Notifications.instrument("track.rack_attack", { request: request }) { }

      crumb = collector.harvest.select { |c| c[:c] == "rack_attack" }.last
      expect(crumb[:meta][:discriminator]).to eq("user_42")
    end

    it "captures the user agent so the agent can be identified (issue #170)" do
      request = double("Rack::Request",
        env: {
          "rack.attack.matched" => "requests accepting markdown",
          "rack.attack.match_type" => :track
        },
        path: "/doc",
        request_method: "GET",
        ip: "198.51.100.42",
        user_agent: "ChatGPT-User/1.0")

      expect(RailsErrorDashboard::Services::RackAttackTracker).to receive(:record)
        .with(hash_including(user_agent: "ChatGPT-User/1.0"))

      ActiveSupport::Notifications.instrument("track.rack_attack", { request: request }) { }
    end

    it "falls back to the raw env header when the request has no #user_agent" do
      request = double("Rack::Request",
        env: {
          "rack.attack.matched" => "md",
          "rack.attack.match_type" => :track,
          "HTTP_USER_AGENT" => "GPTBot/1.2"
        },
        path: "/doc",
        request_method: "GET",
        ip: "198.51.100.42")

      expect(RailsErrorDashboard::Services::RackAttackTracker).to receive(:record)
        .with(hash_including(user_agent: "GPTBot/1.2"))

      ActiveSupport::Notifications.instrument("track.rack_attack", { request: request }) { }
    end

    it "does not raise when request.ip itself raises" do
      request = double("Rack::Request",
        env: {
          "rack.attack.matched" => "api_usage",
          "rack.attack.match_type" => :track
        },
        path: "/doc",
        request_method: "GET")
      allow(request).to receive(:ip).and_raise(ArgumentError, "malformed X-Forwarded-For")

      expect {
        ActiveSupport::Notifications.instrument("track.rack_attack", { request: request }) { }
      }.not_to raise_error

      crumb = collector.harvest.select { |c| c[:c] == "rack_attack" }.last
      expect(crumb[:meta][:discriminator]).to eq("")
    end
  end

  describe "safety" do
    before { described_class.subscribe! }

    it "skips when no breadcrumb buffer is active" do
      collector.clear_buffer

      request = double("Rack::Request",
        env: {
          "rack.attack.matched" => "test",
          "rack.attack.match_type" => :throttle,
          "rack.attack.match_discriminator" => "1.2.3.4"
        },
        path: "/test",
        request_method: "GET")

      ActiveSupport::Notifications.instrument("throttle.rack_attack", { request: request }) { }

      # Re-init buffer to check — nothing should have been added
      collector.init_buffer
      breadcrumbs = collector.harvest
      expect(breadcrumbs.select { |c| c[:c] == "rack_attack" }).to be_empty
    end

    it "handles nil request gracefully" do
      ActiveSupport::Notifications.instrument("throttle.rack_attack", { request: nil }) { }

      breadcrumbs = collector.harvest
      expect(breadcrumbs.select { |c| c[:c] == "rack_attack" }).to be_empty
    end

    it "handles request without env gracefully" do
      request = double("Rack::Request", path: "/test", request_method: "GET")
      allow(request).to receive(:respond_to?).with(:env).and_return(false)
      allow(request).to receive(:respond_to?).with(:path).and_return(true)
      allow(request).to receive(:respond_to?).with(:request_method).and_return(true)
      # resolve_discriminator probes :ip for the track fallback (issue #170),
      # and resolve_user_agent probes :user_agent for agent attribution.
      allow(request).to receive(:respond_to?).with(:ip).and_return(false)
      allow(request).to receive(:respond_to?).with(:user_agent).and_return(false)

      ActiveSupport::Notifications.instrument("throttle.rack_attack", { request: request }) { }

      breadcrumbs = collector.harvest
      ra_crumbs = breadcrumbs.select { |c| c[:c] == "rack_attack" }
      expect(ra_crumbs).not_to be_empty
      expect(ra_crumbs.last[:meta][:rule]).to eq("")
    end

    it "handles Hash-like request object without crashing" do
      # Some middleware might pass a plain Hash instead of a Rack::Request
      request = { "PATH_INFO" => "/test" }

      ActiveSupport::Notifications.instrument("throttle.rack_attack", { request: request }) { }

      breadcrumbs = collector.harvest
      ra_crumbs = breadcrumbs.select { |c| c[:c] == "rack_attack" }
      # Hash responds to :env? No. respond_to?(:env) => false, so env = {}
      # Hash responds to :path? No. respond_to?(:path) => false, so path = ""
      expect(ra_crumbs).not_to be_empty
      expect(ra_crumbs.last[:meta][:rule]).to eq("")
      expect(ra_crumbs.last[:meta][:path]).to eq("")
    end

    it "handles request with empty env hash" do
      request = double("Rack::Request",
        env: {},
        path: "/test",
        request_method: "GET")

      ActiveSupport::Notifications.instrument("throttle.rack_attack", { request: request }) { }

      breadcrumbs = collector.harvest
      ra_crumbs = breadcrumbs.select { |c| c[:c] == "rack_attack" }
      expect(ra_crumbs).not_to be_empty
      crumb = ra_crumbs.last
      expect(crumb[:meta][:rule]).to eq("")
      expect(crumb[:meta][:discriminator]).to eq("")
      expect(crumb[:m]).to eq("throttle:  () GET /test")
    end
  end
end
