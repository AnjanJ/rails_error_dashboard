# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::ErrorNotificationDispatcher do
  let!(:application) { create(:application) }
  let!(:error_log) { create(:error_log, application: application) }

  after { RailsErrorDashboard.reset_configuration! }

  describe ".call" do
    it "enqueues Slack notification when enabled" do
      RailsErrorDashboard.configure do |c|
        c.enable_slack_notifications = true
        c.slack_webhook_url = "https://hooks.slack.com/test"
      end

      expect {
        described_class.call(error_log)
      }.to have_enqueued_job(RailsErrorDashboard::SlackErrorNotificationJob).with(error_log.id)
    end

    it "does not enqueue Slack notification when disabled" do
      RailsErrorDashboard.configure do |c|
        c.enable_slack_notifications = false
      end

      expect {
        described_class.call(error_log)
      }.not_to have_enqueued_job(RailsErrorDashboard::SlackErrorNotificationJob)
    end

    it "enqueues email notification when enabled" do
      RailsErrorDashboard.configure do |c|
        c.enable_email_notifications = true
        c.notification_email_recipients = [ "admin@example.com" ]
      end

      expect {
        described_class.call(error_log)
      }.to have_enqueued_job(RailsErrorDashboard::EmailErrorNotificationJob).with(error_log.id)
    end

    it "does not enqueue email notification when no recipients" do
      RailsErrorDashboard.configure do |c|
        c.enable_email_notifications = true
        c.notification_email_recipients = []
      end

      expect {
        described_class.call(error_log)
      }.not_to have_enqueued_job(RailsErrorDashboard::EmailErrorNotificationJob)
    end

    it "enqueues Discord notification when enabled" do
      RailsErrorDashboard.configure do |c|
        c.enable_discord_notifications = true
        c.discord_webhook_url = "https://discord.com/api/webhooks/test"
      end

      expect {
        described_class.call(error_log)
      }.to have_enqueued_job(RailsErrorDashboard::DiscordErrorNotificationJob).with(error_log.id)
    end

    it "enqueues PagerDuty notification when enabled" do
      RailsErrorDashboard.configure do |c|
        c.enable_pagerduty_notifications = true
        c.pagerduty_integration_key = "test-key"
      end

      expect {
        described_class.call(error_log)
      }.to have_enqueued_job(RailsErrorDashboard::PagerdutyErrorNotificationJob).with(error_log.id)
    end

    it "enqueues webhook notification when enabled" do
      RailsErrorDashboard.configure do |c|
        c.enable_webhook_notifications = true
        c.webhook_urls = [ "https://example.com/webhook" ]
      end

      expect {
        described_class.call(error_log)
      }.to have_enqueued_job(RailsErrorDashboard::WebhookErrorNotificationJob).with(error_log.id)
    end

    it "enqueues nothing when all notifications disabled" do
      expect {
        described_class.call(error_log)
      }.not_to have_enqueued_job
    end
  end
end
