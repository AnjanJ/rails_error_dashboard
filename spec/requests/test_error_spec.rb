# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Test Error action", type: :request do
  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    ActionController::Base.allow_forgery_protection = false
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    ActionController::Base.allow_forgery_protection = true
  end

  describe "POST /error_dashboard/errors/test_error" do
    it "creates a RailsErrorDashboard::TestError in the error log" do
      expect {
        post "/error_dashboard/errors/test_error"
      }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)

      error = RailsErrorDashboard::ErrorLog.last
      expect(error.error_type).to eq("RailsErrorDashboard::TestError")
      expect(error.message).to include("[RED Test]")
      expect(error.message).to include("safe to resolve or delete")
    end

    it "redirects to the errors index with a success flash" do
      post "/error_dashboard/errors/test_error"
      expect(response).to redirect_to("/error_dashboard/errors")
      follow_redirect!
      expect(response.body).to include("Test error logged successfully")
    end

    it "is classified critical, so PagerDuty (critical-only) receives it too" do
      expect(RailsErrorDashboard::Services::SeverityClassifier.classify("RailsErrorDashboard::TestError")).to eq(:critical)
    end

    context "with a channel enabled" do
      before do
        RailsErrorDashboard.configuration.enable_slack_notifications = true
        RailsErrorDashboard.configuration.slack_webhook_url = "https://hooks.slack.com/services/T/B/test"
        RailsErrorDashboard.configuration.enable_pagerduty_notifications = true
        RailsErrorDashboard.configuration.pagerduty_integration_key = "pd-key"
      end

      after { RailsErrorDashboard.reset_configuration! }

      it "notifies on the first click through the capture path" do
        expect {
          post "/error_dashboard/errors/test_error"
        }.to have_enqueued_job(RailsErrorDashboard::SlackErrorNotificationJob).once
          .and have_enqueued_job(RailsErrorDashboard::PagerdutyErrorNotificationJob).once
      end

      # The second click is occurrence two of the same row: the capture path
      # notifies on thresholds (10, 50, ...), so it used to notify nobody.
      it "notifies again on a second click, exactly once" do
        post "/error_dashboard/errors/test_error"

        expect {
          post "/error_dashboard/errors/test_error"
        }.to have_enqueued_job(RailsErrorDashboard::SlackErrorNotificationJob).once

        expect(RailsErrorDashboard::ErrorLog.where(error_type: "RailsErrorDashboard::TestError").count).to eq(1)
      end

      it "notifies even when the capture path would have filtered the error out" do
        RailsErrorDashboard.configuration.notification_environments = [ "production" ]

        expect {
          post "/error_dashboard/errors/test_error"
        }.to have_enqueued_job(RailsErrorDashboard::SlackErrorNotificationJob).once
      end
    end

    it "preserves application_id context" do
      app = create(:application, name: "TestApp")
      post "/error_dashboard/errors/test_error", params: { application_id: app.id }
      expect(response).to redirect_to("/error_dashboard/errors?application_id=#{app.id}")
    end
  end
end
