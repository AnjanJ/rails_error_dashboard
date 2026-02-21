# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::BaselineAlertJob, type: :job do
  let(:error_log) { create(:error_log, error_type: "NoMethodError", platform: "ios") }
  let(:anomaly_data) do
    {
      anomaly: true,
      level: :high,
      baseline_type: "hourly",
      threshold: 10.5,
      std_devs_above: 3.2
    }
  end

  before do
    # Clear throttler cache
    RailsErrorDashboard::Services::BaselineAlertThrottler.clear!

    # Reset configuration to defaults
    RailsErrorDashboard.configuration.enable_slack_notifications = false
    RailsErrorDashboard.configuration.enable_email_notifications = false
    RailsErrorDashboard.configuration.enable_discord_notifications = false
    RailsErrorDashboard.configuration.enable_webhook_notifications = false
    RailsErrorDashboard.configuration.enable_pagerduty_notifications = false
    RailsErrorDashboard.configuration.baseline_alert_cooldown_minutes = 120
  end

  describe "#perform" do
    context "when error log does not exist" do
      it "does not send notifications" do
        expect_any_instance_of(described_class).not_to receive(:post_json)
        described_class.new.perform(999_999, anomaly_data)
      end
    end

    context "when alert is throttled" do
      before do
        # Record a recent alert
        RailsErrorDashboard::Services::BaselineAlertThrottler.record_alert(
          error_log.error_type,
          error_log.platform
        )
      end

      it "does not send notifications" do
        expect_any_instance_of(described_class).not_to receive(:post_json)
        described_class.new.perform(error_log.id, anomaly_data)
      end

      it "logs throttling message" do
        expect(Rails.logger).to receive(:info).with(/Baseline alert throttled/)
        described_class.new.perform(error_log.id, anomaly_data)
      end
    end

    context "when alert is not throttled" do
      it "records the alert" do
        expect {
          described_class.new.perform(error_log.id, anomaly_data)
        }.to change {
          RailsErrorDashboard::Services::BaselineAlertThrottler.minutes_since_last_alert(
            error_log.error_type,
            error_log.platform
          )
        }.from(nil).to(0)
      end

      context "with Slack notifications enabled" do
        before do
          RailsErrorDashboard.configuration.enable_slack_notifications = true
          RailsErrorDashboard.configuration.slack_webhook_url = "https://hooks.slack.com/test"
        end

        it "sends Slack notification via post_json" do
          expect_any_instance_of(described_class).to receive(:post_json).with(
            "https://hooks.slack.com/test",
            hash_including(text: "🚨 Baseline Anomaly Alert")
          )

          described_class.new.perform(error_log.id, anomaly_data)
        end

        it "includes error information in payload" do
          captured_payload = nil
          allow_any_instance_of(described_class).to receive(:post_json) do |_instance, _url, payload|
            captured_payload = payload
          end

          described_class.new.perform(error_log.id, anomaly_data)

          expect(captured_payload[:text]).to eq("🚨 Baseline Anomaly Alert")
          expect(captured_payload[:blocks]).to be_present
        end

        it "handles Slack errors gracefully" do
          allow_any_instance_of(described_class).to receive(:post_json).and_raise(StandardError.new("Network error"))

          expect(Rails.logger).to receive(:error).with(/Failed to send baseline alert to Slack/).and_call_original
          allow(Rails.logger).to receive(:error).and_call_original

          expect {
            described_class.new.perform(error_log.id, anomaly_data)
          }.not_to raise_error
        end
      end

      context "with Discord notifications enabled" do
        before do
          RailsErrorDashboard.configuration.enable_discord_notifications = true
          RailsErrorDashboard.configuration.discord_webhook_url = "https://discord.com/api/webhooks/test"
        end

        it "sends Discord notification via post_json" do
          expect_any_instance_of(described_class).to receive(:post_json).with(
            "https://discord.com/api/webhooks/test",
            hash_including(embeds: anything)
          )

          described_class.new.perform(error_log.id, anomaly_data)
        end

        it "includes embeds in Discord payload" do
          captured_payload = nil
          allow_any_instance_of(described_class).to receive(:post_json) do |_instance, _url, payload|
            captured_payload = payload
          end

          described_class.new.perform(error_log.id, anomaly_data)

          expect(captured_payload[:embeds]).to be_present
          expect(captured_payload[:embeds].first[:title]).to eq("🚨 Baseline Anomaly Detected")
        end

        it "handles Discord errors gracefully" do
          allow_any_instance_of(described_class).to receive(:post_json).and_raise(StandardError.new("Network error"))

          expect(Rails.logger).to receive(:error).with(/Failed to send baseline alert to Discord/).and_call_original
          allow(Rails.logger).to receive(:error).and_call_original

          expect {
            described_class.new.perform(error_log.id, anomaly_data)
          }.not_to raise_error
        end
      end

      context "with webhook notifications enabled" do
        before do
          RailsErrorDashboard.configuration.enable_webhook_notifications = true
          RailsErrorDashboard.configuration.webhook_urls = [
            "https://example.com/webhook1",
            "https://example.com/webhook2"
          ]
        end

        it "sends notifications to all webhook URLs" do
          expect_any_instance_of(described_class).to receive(:post_json).with(
            "https://example.com/webhook1",
            anything
          )

          expect_any_instance_of(described_class).to receive(:post_json).with(
            "https://example.com/webhook2",
            anything
          )

          described_class.new.perform(error_log.id, anomaly_data)
        end

        it "includes structured payload" do
          captured_payload = nil
          allow_any_instance_of(described_class).to receive(:post_json) do |_instance, _url, payload|
            captured_payload = payload
          end

          described_class.new.perform(error_log.id, anomaly_data)

          expect(captured_payload[:event]).to eq("baseline_anomaly")
          expect(captured_payload[:error][:type]).to eq(error_log.error_type)
          expect(captured_payload[:anomaly][:level]).to eq("high")
          expect(captured_payload[:anomaly][:std_devs_above]).to eq(3.2)
        end

        it "handles webhook errors gracefully" do
          allow_any_instance_of(described_class).to receive(:post_json).and_raise(StandardError.new("Network error"))

          expect(Rails.logger).to receive(:error).with(/Failed to send baseline alert to webhook/).and_call_original
          allow(Rails.logger).to receive(:error).and_call_original

          expect {
            described_class.new.perform(error_log.id, anomaly_data)
          }.not_to raise_error
        end
      end

      context "with PagerDuty notifications enabled" do
        before do
          RailsErrorDashboard.configuration.enable_pagerduty_notifications = true
          RailsErrorDashboard.configuration.pagerduty_integration_key = "test-key"
        end

        context "with critical anomaly" do
          let(:critical_anomaly) { anomaly_data.merge(level: :critical) }

          it "sends PagerDuty notification" do
            expect(Rails.logger).to receive(:info).with(/Baseline alert PagerDuty notification/)
            described_class.new.perform(error_log.id, critical_anomaly)
          end
        end

        context "with non-critical anomaly" do
          it "does not send PagerDuty notification" do
            expect(Rails.logger).not_to receive(:info).with(/PagerDuty/)
            described_class.new.perform(error_log.id, anomaly_data)
          end
        end
      end

      context "with email notifications enabled" do
        before do
          RailsErrorDashboard.configuration.enable_email_notifications = true
          RailsErrorDashboard.configuration.notification_email_recipients = [ "admin@example.com" ]
        end

        it "logs that email would be sent" do
          expect(Rails.logger).to receive(:info).with(/Baseline alert email would be sent/)
          described_class.new.perform(error_log.id, anomaly_data)
        end
      end

      context "with multiple channels enabled" do
        before do
          RailsErrorDashboard.configuration.enable_slack_notifications = true
          RailsErrorDashboard.configuration.slack_webhook_url = "https://hooks.slack.com/test"
          RailsErrorDashboard.configuration.enable_discord_notifications = true
          RailsErrorDashboard.configuration.discord_webhook_url = "https://discord.com/api/webhooks/test"
        end

        it "sends to all enabled channels" do
          expect_any_instance_of(described_class).to receive(:post_json).with(
            "https://hooks.slack.com/test",
            anything
          )

          expect_any_instance_of(described_class).to receive(:post_json).with(
            "https://discord.com/api/webhooks/test",
            anything
          )

          described_class.new.perform(error_log.id, anomaly_data)
        end
      end
    end

    context "with different anomaly levels" do
      before do
        RailsErrorDashboard.configuration.enable_slack_notifications = true
        RailsErrorDashboard.configuration.slack_webhook_url = "https://hooks.slack.com/test"
      end

      it "formats elevated anomaly correctly" do
        elevated_anomaly = anomaly_data.merge(level: :elevated)
        captured_payload = nil
        allow_any_instance_of(described_class).to receive(:post_json) do |_instance, _url, payload|
          captured_payload = payload
        end

        described_class.new.perform(error_log.id, elevated_anomaly)

        severity_field = captured_payload[:blocks].find { |b| b[:type] == "section" }&.dig(:fields)&.find { |f| f[:text].include?("Severity") }
        expect(severity_field[:text]).to include("ELEVATED")
      end

      it "formats critical anomaly correctly" do
        critical_anomaly = anomaly_data.merge(level: :critical)
        captured_payload = nil
        allow_any_instance_of(described_class).to receive(:post_json) do |_instance, _url, payload|
          captured_payload = payload
        end

        described_class.new.perform(error_log.id, critical_anomaly)

        severity_field = captured_payload[:blocks].find { |b| b[:type] == "section" }&.dig(:fields)&.find { |f| f[:text].include?("Severity") }
        expect(severity_field[:text]).to include("CRITICAL")
        expect(severity_field[:text]).to include("🔴")
      end
    end
  end
end
