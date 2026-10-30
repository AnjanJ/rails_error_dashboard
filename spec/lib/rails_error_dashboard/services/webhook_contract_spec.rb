# frozen_string_literal: true

require "rails_helper"

# What a receiver can rely on for every event: each one goes through its real
# job and out over HTTP, so this is what's on the wire, not what a builder returns.
RSpec.describe "The webhook contract" do
  let(:url) { "https://example.com/hooks/red" }
  let(:config) { RailsErrorDashboard.configuration }
  let(:error_log) do
    create(:error_log, error_type: "NoMethodError", message: "boom", platform: "ios", environment: "production",
      controller_name: "orders", action_name: "create", user_id: 7, user_agent: "curl/8", ip_address: "10.0.0.1",
      request_url: "https://app.test/orders", request_params: { id: 1 }.to_json, backtrace: "app/a.rb:1\napp/b.rb:2",
      first_seen_at: 1.hour.ago, last_seen_at: Time.current, occurred_at: Time.current)
  end
  let(:anomaly) { { anomaly: true, level: :high, baseline_type: "hourly", threshold: 10.5, std_devs_above: 3.2 } }
  let(:sent) { [] }

  before do
    config.enable_webhook_notifications = true
    config.webhook_urls = [ url ]
    config.dashboard_base_url = "https://example.com"
    config.application_name = "Shop"
    RailsErrorDashboard::Services::BaselineAlertThrottler.clear!
    stub_request(:post, url).to_return { |request| sent << request; { status: 200 } }
  end

  after do
    RailsErrorDashboard.reset_configuration!
    RailsErrorDashboard::Services::BaselineAlertThrottler.clear!
  end

  # Serialised and run the way a queue backend does, with 0.17.0's arguments, so
  # every example here is also a job left in the queue across the upgrade.
  def deliver(event)
    job = case event
    when "error.created" then RailsErrorDashboard::WebhookErrorNotificationJob.new(error_log.id, "en")
    when "baseline.anomaly_detected" then RailsErrorDashboard::BaselineAlertJob.new(error_log.id, anomaly, "en")
    when "storm.detected" then RailsErrorDashboard::StormNotificationJob.new(started_at: "2026-10-30T10:00:00Z", state: "open", locale: "en")
    when "notifications.suppressed" then RailsErrorDashboard::NotificationBurstSummaryJob.new(limit: 5, window_seconds: 60, locale: "en")
    end
    ActiveJob::Base.execute(job.serialize)
    sent.last
  end

  # WebMock writes the header X-Error-Dashboard-Id, whatever was sent.
  def header(request, name)
    request.headers.find { |key, _| key.casecmp?(name) }&.last
  end

  def expect_shape(value, shape, path)
    shape.each do |key, type|
      expect(value).to have_key(key), "#{path} lost #{key}"
      case type
      when Hash then expect_shape(value[key], type, "#{path}.#{key}")
      when Array then expect(type).to include(value[key].class), "#{path}.#{key} is a #{value[key].class}"
      else expect(value[key]).to be_a(type), "#{path}.#{key} is a #{value[key].class}"
      end
    end
  end

  RailsErrorDashboard::WebhookContract::BODIES.each do |event, shape|
    describe event do
      it "says which contract and which event it is, even from a job already queued (webhook-v1/REQ-1, webhook-v1/REQ-2, webhook-v1/REQ-12)" do
        body = JSON.parse(deliver(event).body)

        expect(body).to include("version" => 1, "event" => event)
      end

      it "stamps the time in UTC, whatever the app's zone (webhook-v1/REQ-2)" do
        request = Time.use_zone("Asia/Kolkata") { deliver(event) }

        expect(JSON.parse(request.body)["timestamp"]).to match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/)
      end

      it "puts the event in a header (webhook-v1/REQ-3)" do
        expect(header(deliver(event), "X-Error-Dashboard-Event")).to eq(event)
      end

      if %w[error.created baseline.anomaly_detected].include?(event)
        it "names the error in a header (webhook-v1/REQ-4)" do
          expect(header(deliver(event), "X-Error-Dashboard-ID")).to eq(error_log.id.to_s)
        end
      else
        it "has no error to name (webhook-v1/REQ-4)" do
          expect(header(deliver(event), "X-Error-Dashboard-ID")).to be_nil
        end
      end

      it "keeps every field 0.17.0 sent, with the same type (webhook-v1/REQ-9)" do
        expect_shape(JSON.parse(deliver(event).body), shape, event)
      end

      it "signs the exact bytes it sent (webhook-v1/REQ-10)" do
        secret = "0123456789abcdef0123456789abcdef"
        config.webhook_signing_secret = secret
        request = deliver(event)

        expect(RailsErrorDashboard::Services::WebhookSigner.valid?(
          request.body,
          timestamp: header(request, "X-Error-Dashboard-Timestamp"),
          signature: header(request, "X-Error-Dashboard-Signature-256"),
          secret: secret
        )).to be(true)
      end
    end
  end

  describe "the channels that aren't ours to version (webhook-v1/REQ-11)" do
    before do
      config.webhook_urls = []
      config.enable_webhook_notifications = false
    end

    let(:started_at) { "2026-10-30T10:00:00Z" }

    # The job's own sentence, so this pins what's on the wire around it, and a
    # later change to the wording doesn't fail a test about the envelope.
    let(:message) do
      RailsErrorDashboard::StormNotificationJob.new.send(:build_message, started_at, "open", config, "en")
    end

    def storm
      RailsErrorDashboard::StormNotificationJob.perform_now(started_at: started_at, state: "open", locale: "en")
    end

    it "sends Slack exactly the message and nothing else" do
      config.enable_slack_notifications = true
      config.slack_webhook_url = url

      storm

      expect(sent.last.body).to eq({ text: message }.to_json)
    end

    it "sends Discord exactly the message and nothing else" do
      config.enable_discord_notifications = true
      config.discord_webhook_url = url

      storm

      expect(sent.last.body).to eq({ content: message }.to_json)
    end

    it "sends Telegram exactly the message and nothing else" do
      allow(RailsErrorDashboard::Services::TelegramDelivery).to receive(:configured?).and_return(true)
      allow(RailsErrorDashboard::Services::TelegramDelivery).to receive(:send_message)

      storm

      expect(RailsErrorDashboard::Services::TelegramDelivery).to have_received(:send_message).with(message)
    end
  end
end
