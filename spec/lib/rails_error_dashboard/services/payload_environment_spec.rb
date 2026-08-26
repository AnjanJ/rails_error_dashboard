# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Notification payloads carry the environment" do
  let!(:application) { create(:application, name: "Shop") }
  let(:staging) { create(:error_log, application: application, environment: "staging", platform: "Web") }
  let(:legacy) { create(:error_log, application: application, environment: nil, platform: "Web") }

  before { RailsErrorDashboard.configuration.pagerduty_integration_key = "pd-key" }
  after { RailsErrorDashboard.reset_configuration! }

  it "Slack adds an Environment field only when present" do
    with = RailsErrorDashboard::Services::SlackPayloadBuilder.call(staging).to_json
    without = RailsErrorDashboard::Services::SlackPayloadBuilder.call(legacy).to_json
    expect(with).to include("*Environment:*\\nstaging")
    expect(without).not_to include("*Environment:*")
  end

  it "Discord adds an Environment field only when present" do
    with = RailsErrorDashboard::Services::DiscordPayloadBuilder.call(staging).to_json
    without = RailsErrorDashboard::Services::DiscordPayloadBuilder.call(legacy).to_json
    expect(with).to include('"name":"Environment","value":"staging"')
    expect(without).not_to include('"name":"Environment"')
  end

  it "Webhook carries error.environment" do
    expect(RailsErrorDashboard::Services::WebhookPayloadBuilder.call(staging)[:error][:environment]).to eq("staging")
    expect(RailsErrorDashboard::Services::WebhookPayloadBuilder.call(legacy)[:error][:environment]).to be_nil
  end

  it "PagerDuty carries custom_details.environment" do
    payload = RailsErrorDashboard::Services::PagerdutyPayloadBuilder.call(staging, routing_key: "pd-key")
    expect(payload[:payload][:custom_details][:environment]).to eq("staging")
  end

  it "Email subject and body include the environment, and the legacy subject is unchanged" do
    mail = RailsErrorDashboard::ErrorNotificationMailer.error_alert(staging, [ "ops@example.com" ])
    expect(mail.subject).to include("[Shop · staging]")
    html = (mail.html_part || mail).body.to_s
    text = mail.text_part&.body.to_s
    expect(html).to include("Environment")
    expect(html).to include("staging")
    expect(text).to include("Environment: staging") if text.present?

    legacy_mail = RailsErrorDashboard::ErrorNotificationMailer.error_alert(legacy, [ "ops@example.com" ])
    expect(legacy_mail.subject).to include("[Shop]")
    expect(legacy_mail.subject).not_to include("·")
  end
end
