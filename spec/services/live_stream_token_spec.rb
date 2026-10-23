# frozen_string_literal: true

require "rails_helper"

# The token a live-updates subscription carries: which stream it may listen to,
# and until when. Built by hand here with RED's key and other purposes, so the
# spec pins what a token is, not just that issue and verify agree.
RSpec.describe RailsErrorDashboard::Services::LiveStreamToken do
  let(:stream) { RailsErrorDashboard::Services::ErrorBroadcaster.stream_name(:list) }
  let(:app_stream) { RailsErrorDashboard::Services::ErrorBroadcaster.stream_name(:updates, 7) }

  def red_verifier
    key = Rails.application.key_generator.generate_key(described_class::SALT)
    ActiveSupport::MessageVerifier.new(key, digest: "SHA256", serializer: JSON)
  end

  # The verifier is memoized. Reset it on both sides, so no example depends on
  # whether an earlier spec file built one (a memoized verifier would make the
  # key-failure example below pass straight past its stub).
  before { described_class.reset! }
  after { described_class.reset! }

  # live-updates-hardening-0-17/REQ-1
  describe ".issue" do
    it "issues a token for a RED stream that expires 10 minutes later" do
      freeze_time do
        verified = described_class.verify(described_class.issue(app_stream))

        expect(verified).to eq(stream: app_stream, expires_at: (Time.now + 10.minutes).to_i)
        expect(described_class::LIFETIME).to eq(10.minutes)
      end
    end

    it "issues a different token each time, even within one second" do
      freeze_time do
        expect(described_class.issue(stream)).not_to eq(described_class.issue(stream))
      end
    end

    it "issues nothing for a stream that isn't RED's" do
      expect(described_class.issue("chat_room_1")).to be_nil
      expect(described_class.issue(nil)).to be_nil
    end

    it "returns nil when the signing key can't be built" do
      allow(Rails.application).to receive(:key_generator).and_raise(ArgumentError, "no secret")

      expect(described_class.issue(stream)).to be_nil
    end
  end

  # live-updates-hardening-0-17/REQ-2
  describe ".verify" do
    it "rejects a token once it has expired" do
      token = described_class.issue(stream)

      travel(10.minutes - 1.second) { expect(described_class.verify(token)).to be_present }
      travel(10.minutes + 1.second) { expect(described_class.verify(token)).to be_nil }
    end

    it "rejects a tampered token" do
      token = described_class.issue(stream)
      tampered = token[0..-2] + (token[-1] == "A" ? "B" : "A")

      expect(described_class.verify(tampered)).to be_nil
    end

    it "rejects a token Turbo signed for the same stream" do
      skip "turbo-rails is not loaded" unless defined?(Turbo::StreamsChannel)

      expect(described_class.verify(Turbo.signed_stream_verifier.generate(stream))).to be_nil
    end

    it "rejects a token signed with RED's key for another purpose" do
      payload = { "s" => stream, "e" => (Time.now + 1.hour).to_i, "n" => "x" }

      expect(described_class.verify(red_verifier.generate(payload, purpose: "something_else"))).to be_nil
      expect(described_class.verify(red_verifier.generate(payload))).to be_nil
    end

    it "rejects a correctly signed token for a stream that isn't RED's" do
      payload = { "s" => "chat_room_1", "e" => (Time.now + 1.hour).to_i, "n" => "x" }
      token = red_verifier.generate(payload, purpose: described_class::PURPOSE)

      expect(described_class.verify(token)).to be_nil
    end

    it "rejects a correctly signed token whose own expiry has passed" do
      payload = { "s" => stream, "e" => (Time.now - 1.second).to_i, "n" => "x" }
      token = red_verifier.generate(payload, purpose: described_class::PURPOSE)

      expect(described_class.verify(token)).to be_nil
    end

    it "rejects input that isn't a token, without raising" do
      [ nil, "", "garbage", "a--b", { "x" => "y" }, [ "z" ], 42, "x" * 5_000 ].each do |input|
        expect(described_class.verify(input)).to be_nil, "expected nil for #{input.inspect[0, 40]}"
      end
    end

    it "returns nil when the signing key can't be built" do
      token = described_class.issue(stream)
      described_class.reset!
      allow(Rails.application).to receive(:key_generator).and_raise(ArgumentError, "no secret")

      expect(described_class.verify(token)).to be_nil
    end
  end
end
