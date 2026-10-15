# frozen_string_literal: true

require "rails_helper"

# Printing the configuration in a console, or pasting it into an issue, must not
# show credentials. IRB displays results with pp, which uses #inspect.
RSpec.describe RailsErrorDashboard::Configuration, "#inspect" do
  subject(:config) { described_class.new }

  let(:secrets) do
    {
      dashboard_password: "hunter2-password",
      slack_webhook_url: "https://hooks.slack.com/services/T0/B0/slack-secret",
      discord_webhook_url: "https://discord.com/api/webhooks/1/discord-secret",
      pagerduty_integration_key: "pagerduty-secret-key",
      webhook_urls: [ "https://example.com/hook?token=webhook-secret" ],
      webhook_signing_secret: "webhook-signing-secret",
      issue_tracker_token: "ghp_issue-tracker-secret",
      issue_webhook_secret: "issue-webhook-secret",
      llm_api_key: "sk-llm-secret",
      telegram_bot_token: "123456:telegram-bot-secret"
    }
  end

  before { secrets.each { |name, value| config.public_send("#{name}=", value) } }

  it "masks every credential" do
    secrets.each_value do |value|
      Array(value).each { |v| expect(config.inspect).not_to include(v) }
    end
    expect(config.inspect).to include("@dashboard_password=[FILTERED]", "@llm_api_key=[FILTERED]")
  end

  it "masks them in pp output too" do
    expect(config.pretty_inspect).not_to include("hunter2-password", "sk-llm-secret")
  end

  it "masks a credential given as a lambda" do
    config.issue_tracker_token = -> { "ghp_from_credentials" }
    expect(config.inspect).to include("@issue_tracker_token=[FILTERED]")
  end

  it "still shows the other settings, and unset credentials as unset" do
    config.discord_webhook_url = nil
    expect(config.inspect).to include("@sampling_rate=1.0", "@discord_webhook_url=nil")
  end
end
