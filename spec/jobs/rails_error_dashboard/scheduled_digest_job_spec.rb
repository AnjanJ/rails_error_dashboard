# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::ScheduledDigestJob, type: :job do
  let(:recipients) { [ "dev@example.com", "team@example.com" ] }

  before do
    RailsErrorDashboard.configuration.enable_scheduled_digests = true
    RailsErrorDashboard.configuration.digest_recipients = recipients
    RailsErrorDashboard.configuration.notification_email_from = "errors@example.com"
    RailsErrorDashboard.configuration.dashboard_base_url = "https://example.com"
  end

  after do
    RailsErrorDashboard.configuration.enable_scheduled_digests = false
    RailsErrorDashboard.configuration.digest_recipients = nil
  end

  describe "#perform" do
    it "sends digest email" do
      expect {
        described_class.new.perform(period: "daily")
      }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sends to configured recipients" do
      described_class.new.perform(period: "daily")

      email = ActionMailer::Base.deliveries.last
      expect(email.to).to match_array(recipients)
    end

    it "includes period in subject" do
      described_class.new.perform(period: "daily")

      email = ActionMailer::Base.deliveries.last
      expect(email.subject).to include("RED Digest")
      expect(email.subject).to include("Last 24 hours")
    end

    it "supports weekly period" do
      described_class.new.perform(period: "weekly")

      email = ActionMailer::Base.deliveries.last
      expect(email.subject).to include("Last 7 days")
    end

    it "has both HTML and text parts" do
      described_class.new.perform(period: "daily")

      email = ActionMailer::Base.deliveries.last
      expect(email.html_part).to be_present
      expect(email.text_part).to be_present
    end

    it "includes dashboard link in HTML body" do
      described_class.new.perform(period: "daily")

      email = ActionMailer::Base.deliveries.last
      expect(email.html_part.body.to_s).to include("https://example.com/error_dashboard")
    end

    context "with error data" do
      before do
        create(:error_log, error_type: "NoMethodError",
          occurred_at: 6.hours.ago, occurrence_count: 1)
      end

      it "includes error stats in HTML body" do
        described_class.new.perform(period: "daily")

        email = ActionMailer::Base.deliveries.last
        html = email.html_part.body.to_s
        expect(html).to include("New Errors")
        expect(html).to include("Occurrences")
        expect(html).to include("Resolution Rate")
      end

      it "includes error type in body" do
        described_class.new.perform(period: "daily")

        email = ActionMailer::Base.deliveries.last
        html = email.html_part.body.to_s
        expect(html).to include("NoMethodError")
      end
    end

    context "when digests are disabled" do
      before { RailsErrorDashboard.configuration.enable_scheduled_digests = false }

      it "does not send email" do
        expect {
          described_class.new.perform(period: "daily")
        }.not_to change { ActionMailer::Base.deliveries.count }
      end
    end

    context "when no recipients configured" do
      before do
        RailsErrorDashboard.configuration.digest_recipients = nil
        RailsErrorDashboard.configuration.notification_email_recipients = nil
      end

      it "does not send email" do
        expect {
          described_class.new.perform(period: "daily")
        }.not_to change { ActionMailer::Base.deliveries.count }
      end
    end

    context "when digest_recipients is empty but notification_email_recipients is set" do
      before do
        RailsErrorDashboard.configuration.digest_recipients = nil
        RailsErrorDashboard.configuration.notification_email_recipients = [ "fallback@example.com" ]
      end

      it "falls back to notification_email_recipients" do
        described_class.new.perform(period: "daily")

        email = ActionMailer::Base.deliveries.last
        expect(email.to).to eq([ "fallback@example.com" ])
      end
    end

    context "when mailer raises an error" do
      before do
        mail_message = instance_double(ActionMailer::MessageDelivery)
        allow(RailsErrorDashboard::DigestMailer).to receive(:digest_summary).and_return(mail_message)
        allow(mail_message).to receive(:deliver_now).and_raise(StandardError.new("SMTP error"))
      end

      it "does not raise" do
        expect {
          described_class.new.perform(period: "daily")
        }.not_to raise_error
      end
    end
  end

  describe "job queue" do
    it "is enqueued to default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end
end
