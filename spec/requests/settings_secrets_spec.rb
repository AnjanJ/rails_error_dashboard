# frozen_string_literal: true

require "rails_helper"

# The settings page is read by whoever has dashboard access, which is not the
# same set of people as whoever may read the Slack webhook URL. Every option
# Configuration#inspect masks must be masked here too, whatever :type the
# page declares for it.
RSpec.describe "Settings page credentials", type: :request do
  let(:secrets) do
    {
      dashboard_password: "hunter2-dashboard-password",
      slack_webhook_url: "https://hooks.slack.com/services/T0/B0/slack-secret-token",
      discord_webhook_url: "https://discord.com/api/webhooks/1/discord-secret-token",
      pagerduty_integration_key: "pagerduty-secret-integration-key",
      webhook_urls: [ "https://example.com/hook?token=custom-webhook-secret" ],
      webhook_signing_secret: "webhook-signing-secret-value",
      issue_tracker_token: "ghp_issue-tracker-secret-token",
      issue_webhook_secret: "issue-webhook-secret-value",
      llm_api_key: "sk-llm-secret-key",
      telegram_bot_token: "123456:telegram-bot-secret-token"
    }
  end

  before do
    config = RailsErrorDashboard.configuration
    config.authenticate_with = -> { true }
    config.enable_slack_notifications = true
    config.enable_discord_notifications = true
    config.enable_telegram_notifications = true
    config.telegram_chat_id = "-1001234567890"
    config.enable_pagerduty_notifications = true
    config.enable_webhook_notifications = true
    config.enable_issue_tracking = true
    secrets.each { |name, value| config.public_send("#{name}=", value) }
  end

  after { RailsErrorDashboard.reset_configuration! }

  it "covers every secret the configuration masks" do
    expect(secrets.keys).to match_array(RailsErrorDashboard::Configuration::SECRET_ATTRIBUTES)
  end

  it "prints none of the credential values, only that they are set" do
    get "/error_dashboard/settings"

    expect(response).to have_http_status(:ok)
    secrets.each_value do |value|
      Array(value).each do |v|
        expect(response.body).not_to include(v), "#{v} appeared on the settings page"
      end
    end
    expect(response.body).not_to include("slack-secret-token", "discord-secret-token", "custom-webhook-secret", "telegram-bot-secret")
    # The chat id is an address, not a credential, and stays readable.
    expect(response.body).to include("-1001234567890")
    # One Set badge per visible secret (the dashboard password and the LLM key
    # are on the page too; issue-tracker rows need enable_issue_tracking).
    expect(response.body.scan(/bi-check-circle"><\/i>\s*Set\b/).size).to be >= 5
  end

  it "shows an unset credential as Not set rather than blank" do
    RailsErrorDashboard.configuration.slack_webhook_url = nil

    get "/error_dashboard/settings"

    expect(response.body).to include("Not set")
    expect(response.body).not_to include("slack-secret-token")
  end
end
