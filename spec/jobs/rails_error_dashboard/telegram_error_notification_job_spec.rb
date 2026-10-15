# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::TelegramErrorNotificationJob, type: :job do
  let(:error_log) { create(:error_log, error_type: "RuntimeError", message: "boom") }
  let(:token) { "987654:XYZ-telegram-secret" }
  let(:url) { "https://api.telegram.org/bot#{token}/sendMessage" }

  before do
    RailsErrorDashboard.configuration.telegram_bot_token = token
    RailsErrorDashboard.configuration.telegram_chat_id = "@ops_channel"
  end

  after { RailsErrorDashboard.reset_configuration! }

  describe "#perform" do
    it "sends the HTML message to the configured chat" do
      stub_request(:post, url).to_return(status: 200, body: '{"ok":true}')

      described_class.new.perform(error_log.id)

      expect(WebMock).to have_requested(:post, url).with { |req|
        body = JSON.parse(req.body)
        body["chat_id"] == "@ops_channel" &&
          body["parse_mode"] == "HTML" &&
          body["text"].include?("<b>RuntimeError</b>") &&
          body["text"].include?("<code>boom</code>")
      }.once
    end

    it "builds the message in the locale it was enqueued with" do
      stub_request(:post, url).to_return(status: 200, body: '{"ok":true}')

      described_class.new.perform(error_log.id, "de")

      heading = RailsErrorDashboard::I18nStore.translate("red.notifications.error_alert.heading", locale: "de")
      expect(WebMock).to have_requested(:post, url).with { |req| JSON.parse(req.body)["text"].include?(heading) }
    end

    it "sends nothing when the token or chat id is missing" do
      RailsErrorDashboard.configuration.telegram_chat_id = nil
      stub_request(:post, url)

      described_class.new.perform(error_log.id)

      expect(WebMock).not_to have_requested(:post, url)
    end

    it "logs and does not raise when the error log is gone" do
      stub_request(:post, url)
      allow(Rails.logger).to receive(:error)

      expect { described_class.new.perform(999_999) }.not_to raise_error

      expect(WebMock).not_to have_requested(:post, url)
      expect(Rails.logger).to have_received(:error).with(/Failed to send Telegram notification/)
    end

    it "logs a transport failure with the token redacted" do
      stub_request(:post, url).to_raise(SocketError.new("getaddrinfo: #{url}"))
      allow(Rails.logger).to receive(:error)

      expect { described_class.new.perform(error_log.id) }.not_to raise_error

      expect(Rails.logger).to have_received(:error)
        .with("[RailsErrorDashboard] Failed to send Telegram notification: getaddrinfo: https://api.telegram.org/bot[FILTERED]/sendMessage")
      expect(Rails.logger).not_to have_received(:error).with(/#{Regexp.escape(token)}/)
    end

    it "does not raise when Telegram rejects the message" do
      stub_request(:post, url).to_return(status: 403, body: '{"ok":false,"error_code":403,"description":"Forbidden: bot was kicked"}')
      allow(Rails.logger).to receive(:error)

      expect { described_class.new.perform(error_log.id) }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/HTTP 403.*bot was kicked/)
    end
  end

  it "is enqueued to the default queue" do
    expect(described_class.new.queue_name).to eq("default")
  end
end
