# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::WebhookDelivery do
  let(:url) { "https://example.com/hooks/errors" }
  let(:payload) { { event: "error.created", error: { id: 1 } } }

  after { RailsErrorDashboard.reset_configuration! }

  describe ".post" do
    it "posts the payload as JSON with the default headers" do
      stub_request(:post, url).to_return(status: 200)

      described_class.post(url, payload)

      expect(WebMock).to have_requested(:post, url).with(
        body: payload.to_json,
        headers: { "Content-Type" => "application/json", "User-Agent" => "RailsErrorDashboard/1.0" }
      )
    end

    it "merges caller headers over the defaults" do
      stub_request(:post, url).to_return(status: 200)

      described_class.post(url, payload, headers: { "X-Error-Dashboard-Event" => "error.created" })

      expect(WebMock).to have_requested(:post, url).with(
        headers: { "X-Error-Dashboard-Event" => "error.created", "Content-Type" => "application/json" }
      )
    end

    it "sends no signature headers when no secret is configured" do
      stub_request(:post, url).to_return(status: 200)

      described_class.post(url, payload)

      expect(WebMock).to have_requested(:post, url).with { |req|
        req.headers.keys.none? { |h| h.casecmp?("X-Error-Dashboard-Signature-256") } &&
          req.headers.keys.none? { |h| h.casecmp?("X-Error-Dashboard-Timestamp") }
      }
    end

    context "with webhook_signing_secret set" do
      let(:secret) { "s3cret-s3cret-s3cret" }

      before { RailsErrorDashboard.configuration.webhook_signing_secret = secret }

      it "signs the exact bytes it sends, so the receiver can verify them" do
        stub_request(:post, url).to_return(status: 200)

        described_class.post(url, payload)

        expect(WebMock).to have_requested(:post, url).with { |req|
          RailsErrorDashboard::Services::WebhookSigner.valid?(
            req.body,
            timestamp: req.headers["X-Error-Dashboard-Timestamp"],
            signature: req.headers["X-Error-Dashboard-Signature-256"],
            secret: secret
          )
        }
      end

      it "does not verify under a different secret" do
        stub_request(:post, url).to_return(status: 200)

        described_class.post(url, payload)

        expect(WebMock).to have_requested(:post, url).with { |req|
          !RailsErrorDashboard::Services::WebhookSigner.valid?(
            req.body,
            timestamp: req.headers["X-Error-Dashboard-Timestamp"],
            signature: req.headers["X-Error-Dashboard-Signature-256"],
            secret: "another"
          )
        }
      end
    end

    it "keeps the query string of the webhook URL" do
      with_query = "https://example.com/hooks/errors?token=abc"
      stub_request(:post, with_query).to_return(status: 200)

      described_class.post(with_query, payload)

      expect(WebMock).to have_requested(:post, with_query)
    end

    it "lets transport errors propagate to the caller, who logs in its own words" do
      stub_request(:post, url).to_raise(Errno::ECONNREFUSED)

      expect { described_class.post(url, payload) }.to raise_error(Errno::ECONNREFUSED)
    end
  end
end
