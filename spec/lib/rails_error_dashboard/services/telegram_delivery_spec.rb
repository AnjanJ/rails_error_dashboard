# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::TelegramDelivery do
  let(:config) { RailsErrorDashboard.configuration }
  let(:token) { "123456:ABC-DEF_secret-token" }
  let(:url) { "https://api.telegram.org/bot#{token}/sendMessage" }

  before do
    config.enable_telegram_notifications = true
    config.telegram_bot_token = token
    config.telegram_chat_id = "-1001234567890"
  end

  after { RailsErrorDashboard.reset_configuration! }

  describe ".configured?" do
    it "needs the flag, the token and the chat id" do
      expect(described_class.configured?).to be(true)

      config.telegram_chat_id = ""
      expect(described_class.configured?).to be(false)

      config.telegram_chat_id = "42"
      config.telegram_bot_token = nil
      expect(described_class.configured?).to be(false)

      config.telegram_bot_token = token
      config.enable_telegram_notifications = false
      expect(described_class.configured?).to be(false)
    end
  end

  describe ".post" do
    it "POSTs the payload plus the chat id to the Bot API sendMessage method" do
      stub_request(:post, url).to_return(status: 200, body: '{"ok":true}')

      described_class.post({ text: "hello", parse_mode: "HTML" })

      expect(WebMock).to have_requested(:post, url).with(
        headers: { "Content-Type" => "application/json" },
        body: { text: "hello", parse_mode: "HTML", chat_id: "-1001234567890" }.to_json
      ).once
    end

    it "honours telegram_api_base_url, with or without a trailing slash" do
      config.telegram_api_base_url = "http://bot-api.internal:8081/"
      local = "http://bot-api.internal:8081/bot#{token}/sendMessage"
      stub_request(:post, local).to_return(status: 200, body: '{"ok":true}')

      described_class.post({ text: "hello" })

      expect(WebMock).to have_requested(:post, local).once
    end

    it "sends nothing and returns nil without credentials" do
      config.telegram_bot_token = nil

      expect(described_class.post({ text: "hello" })).to be_nil
      expect(WebMock).not_to have_requested(:post, /telegram/)
    end

    it "logs Telegram's description when the API rejects the message, without the token" do
      stub_request(:post, url).to_return(
        status: 400, body: { ok: false, error_code: 400, description: "Bad Request: chat not found" }.to_json
      )
      allow(Rails.logger).to receive(:error)

      described_class.post({ text: "hello" })

      expect(Rails.logger).to have_received(:error)
        .with("[RailsErrorDashboard] Telegram API rejected the message (HTTP 400): Bad Request: chat not found")
      expect(Rails.logger).not_to have_received(:error).with(/#{Regexp.escape(token)}/)
    end

    it "logs nothing for a 2xx answer" do
      stub_request(:post, url).to_return(status: 200, body: '{"ok":true}')
      allow(Rails.logger).to receive(:error)

      described_class.post({ text: "hello" })

      expect(Rails.logger).not_to have_received(:error)
    end

    it "lets transport errors propagate to the caller, which rescues and redacts" do
      stub_request(:post, url).to_raise(SocketError.new("getaddrinfo failed for #{url}"))

      expect { described_class.post({ text: "hello" }) }.to raise_error(SocketError)
    end
  end

  describe ".send_message" do
    it "sends the text verbatim with no parse mode by default" do
      stub_request(:post, url).to_return(status: 200, body: '{"ok":true}')

      described_class.send_message("Storm in <App>")

      expect(WebMock).to have_requested(:post, url).with { |req|
        body = JSON.parse(req.body)
        body["text"] == "Storm in <App>" && !body.key?("parse_mode") && body["disable_web_page_preview"] == true
      }
    end
  end

  describe ".redact" do
    it "replaces the token wherever it appears" do
      expect(described_class.redact("failed: #{url} and again #{token}"))
        .to eq("failed: https://api.telegram.org/bot[FILTERED]/sendMessage and again [FILTERED]")
    end

    it "leaves the text alone when no token is configured" do
      config.telegram_bot_token = nil

      expect(described_class.redact("plain")).to eq("plain")
    end
  end

  describe ".redacted_url" do
    it "names the endpoint without the credential" do
      expect(described_class.redacted_url).to eq("https://api.telegram.org/bot[FILTERED]/sendMessage")
    end
  end
end
