# frozen_string_literal: true

require "rails_helper"

# The channel the error list subscribes through. It accepts a subscription only
# with a token RED issued for live updates, and stops delivering once that
# token has expired, even while the subscription stays open.
RSpec.describe RailsErrorDashboard::LiveUpdatesChannel, type: :channel do
  let(:token_service) { RailsErrorDashboard::Services::LiveStreamToken }
  let(:stream) { RailsErrorDashboard::Services::ErrorBroadcaster.stream_name(:list) }

  # Action Cable's test helper reads server.pubsub before any example code
  # runs, and the dummy app has no cable.yml.
  before(:context) do
    @original_cable = ActionCable.server.config.cable
    ActionCable.server.config.cable = { "adapter" => "test" }
    ActionCable.server.instance_variable_set(:@pubsub, nil)
  end

  after(:context) do
    ActionCable.server.config.cable = @original_cable
    ActionCable.server.instance_variable_set(:@pubsub, nil)
  end

  before { RailsErrorDashboard.configuration.enable_live_updates = true }
  after { RailsErrorDashboard.configuration.enable_live_updates = false }

  def expect_rejected
    expect(subscription).to be_rejected
    expect(subscription.streams).to be_empty
  end

  # live-updates-hardening-0-17/REQ-2
  describe "subscribing" do
    it "streams from the name inside a valid token" do
      subscribe(signed_stream_name: token_service.issue(stream))

      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from(stream)
    end

    it "rejects an expired token" do
      token = token_service.issue(stream)

      travel(token_service::LIFETIME + 1.second) { subscribe(signed_stream_name: token) }

      expect_rejected
    end

    it "rejects a tampered token" do
      token = token_service.issue(stream)
      subscribe(signed_stream_name: token[0..-2] + (token[-1] == "A" ? "B" : "A"))

      expect_rejected
    end

    it "rejects a subscription with no token" do
      subscribe

      expect_rejected
    end

    it "rejects a token Turbo signed for the same stream" do
      skip "turbo-rails is not loaded" unless defined?(Turbo::StreamsChannel)

      subscribe(signed_stream_name: Turbo.signed_stream_verifier.generate(stream))

      expect_rejected
    end
  end

  # live-updates-hardening-0-17/REQ-5
  it "rejects even a valid token while live updates are off" do
    RailsErrorDashboard.configuration.enable_live_updates = false

    subscribe(signed_stream_name: token_service.issue(stream))

    expect_rejected
  end

  # live-updates-hardening-0-17/REQ-3
  describe "a subscription that outlives its token" do
    # The test stub records stream_from without running the callback, so the
    # callback is called here directly.
    let(:message) { "<turbo-stream action=\"prepend\" target=\"error_list\"></turbo-stream>" }

    it "relays messages until the token expires" do
      subscribe(signed_stream_name: token_service.issue(stream))

      subscription.send(:relay, message)

      expect(transmissions.last).to eq(message)
    end

    it "relays nothing after the token expires, and stops streaming" do
      subscribe(signed_stream_name: token_service.issue(stream))
      delivered = transmissions.size

      travel(token_service::LIFETIME + 1.second) { subscription.send(:relay, message) }

      expect(transmissions.size).to eq(delivered)
      expect(subscription.streams).to be_empty
    end
  end

  # live-updates-hardening-0-17/REQ-2: a client can't call into the channel.
  it "has no action a client could perform" do
    expect(described_class.action_methods).to be_empty
  end
end
