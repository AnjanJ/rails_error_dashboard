# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::NotificationBurstSummaryJob do
  let(:slack_url) { "https://hooks.slack.com/services/TEST/BURST/URL" }
  let(:discord_url) { "https://discord.com/api/webhooks/123/burst" }
  let(:webhook_url) { "https://example.com/hooks/burst" }
  let(:config) { RailsErrorDashboard.configuration }

  before { config.application_name = "TestApp" }
  after { RailsErrorDashboard.reset_configuration! }

  def body_of(url)
    found = nil
    expect(WebMock).to have_requested(:post, url).with { |req| found = JSON.parse(req.body) }.once
    found
  end

  it "posts one plain message to Slack naming the limit and the window" do
    config.enable_slack_notifications = true
    config.slack_webhook_url = slack_url
    stub_request(:post, slack_url).to_return(status: 200)

    described_class.perform_now(limit: 3, window_seconds: 60)

    text = body_of(slack_url).fetch("text")
    expect(text).to include("TestApp")
    expect(text).to include("3")
    expect(text).to include("60")
  end

  it "posts a {content:} payload to Discord" do
    config.enable_discord_notifications = true
    config.discord_webhook_url = discord_url
    stub_request(:post, discord_url).to_return(status: 200)

    described_class.perform_now(limit: 3, window_seconds: 60)

    expect(body_of(discord_url)).to have_key("content")
  end

  it "posts a machine-readable event to every custom webhook" do
    config.enable_webhook_notifications = true
    config.webhook_urls = [ webhook_url ]
    stub_request(:post, webhook_url).to_return(status: 200)

    described_class.perform_now(limit: 3, window_seconds: 60)

    expect(body_of(webhook_url)).to include(
      "event" => "new_error_notifications_suppressed", "limit" => 3, "window_seconds" => 60, "application" => "TestApp"
    )
  end

  it "links to the dashboard when a base URL is configured" do
    config.enable_slack_notifications = true
    config.slack_webhook_url = slack_url
    config.dashboard_base_url = "https://app.example.com/red/"
    stub_request(:post, slack_url).to_return(status: 200)

    described_class.perform_now(limit: 3, window_seconds: 60)

    expect(body_of(slack_url).fetch("text")).to include("https://app.example.com/red/errors")
  end

  it "is translated with the locale resolved at enqueue time" do
    config.enable_slack_notifications = true
    config.slack_webhook_url = slack_url
    stub_request(:post, slack_url).to_return(status: 200)

    described_class.perform_now(limit: 3, window_seconds: 60, locale: "de")

    german = RailsErrorDashboard::I18nStore.translate(
      "red.notifications.burst.suppressed", locale: "de", application: "TestApp", limit: 3, window: 60
    )
    expect(body_of(slack_url).fetch("text")).to include(german)
    expect(german).not_to include("new errors") # really translated, not the English fallback
  end

  it "sends nothing when no channel is enabled" do
    expect { described_class.perform_now(limit: 3, window_seconds: 60) }.not_to raise_error
    expect(WebMock).not_to have_requested(:post, /.*/)
  end

  it "never raises when a channel is down" do
    config.enable_slack_notifications = true
    config.slack_webhook_url = slack_url
    stub_request(:post, slack_url).to_raise(SocketError)

    expect { described_class.perform_now(limit: 3, window_seconds: 60) }.not_to raise_error
  end
end
