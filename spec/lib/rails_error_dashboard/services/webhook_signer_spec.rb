# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::WebhookSigner do
  let(:secret) { "0123456789abcdef0123456789abcdef" }
  let(:body) { '{"event":"error.created","timestamp":"2026-10-10T10:00:00Z"}' }
  let(:timestamp) { 1_760_090_400 }

  describe ".headers_for" do
    subject(:headers) { described_class.headers_for(body, secret: secret, timestamp: timestamp) }

    it "sets the timestamp header to the Unix seconds it signed with" do
      expect(headers["X-Error-Dashboard-Timestamp"]).to eq(timestamp.to_s)
    end

    it "signs timestamp.body with HMAC-SHA256 and a sha256= prefix" do
      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
      expect(headers["X-Error-Dashboard-Signature-256"]).to eq("sha256=#{expected}")
    end

    it "changes when the body changes" do
      other = described_class.headers_for(body + " ", secret: secret, timestamp: timestamp)
      expect(other["X-Error-Dashboard-Signature-256"]).not_to eq(headers["X-Error-Dashboard-Signature-256"])
    end

    it "changes when the timestamp changes, so a captured request cannot be re-dated" do
      other = described_class.headers_for(body, secret: secret, timestamp: timestamp + 1)
      expect(other["X-Error-Dashboard-Signature-256"]).not_to eq(headers["X-Error-Dashboard-Signature-256"])
    end

    it "defaults the timestamp to now" do
      now = Time.now.to_i
      ts = described_class.headers_for(body, secret: secret)["X-Error-Dashboard-Timestamp"].to_i
      expect(ts).to be_between(now - 2, now + 2)
    end
  end

  describe ".valid?" do
    let(:headers) { described_class.headers_for(body, secret: secret, timestamp: timestamp) }

    def valid?(body: self.body, signature: headers["X-Error-Dashboard-Signature-256"],
               ts: headers["X-Error-Dashboard-Timestamp"], secret: self.secret, now: timestamp, tolerance: 300)
      described_class.valid?(body, timestamp: ts, signature: signature, secret: secret,
                                   tolerance: tolerance, now: now)
    end

    it "accepts what headers_for produced" do
      expect(valid?).to be(true)
    end

    it "rejects a tampered body" do
      expect(valid?(body: body.sub("error.created", "error.resolved"))).to be(false)
    end

    it "rejects the wrong secret" do
      expect(valid?(secret: "not-the-secret")).to be(false)
    end

    it "rejects a signature without the prefix" do
      expect(valid?(signature: headers["X-Error-Dashboard-Signature-256"].delete_prefix("sha256="))).to be(false)
    end

    it "rejects a request older than the tolerance" do
      expect(valid?(now: timestamp + 301)).to be(false)
    end

    it "rejects a request from the future beyond the tolerance" do
      expect(valid?(now: timestamp - 301)).to be(false)
    end

    it "accepts a request inside the tolerance" do
      expect(valid?(now: timestamp + 299)).to be(true)
    end

    it "skips the window when tolerance is nil" do
      expect(valid?(now: timestamp + 86_400, tolerance: nil)).to be(true)
    end

    it "treats a non-numeric timestamp as invalid rather than raising" do
      expect(valid?(ts: "yesterday")).to be(false)
    end

    it "treats a missing signature or secret as invalid" do
      expect(valid?(signature: nil)).to be(false)
      expect(valid?(secret: "")).to be(false)
    end
  end
end
