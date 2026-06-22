# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::StormNotificationJob do
  let(:started_at) { "2026-06-22T12:00:00Z" }
  let(:slack_url) { "https://hooks.slack.com/services/TEST/STORM/URL" }
  let(:discord_url) { "https://discord.com/api/webhooks/123/storm" }
  let(:webhook_url_a) { "https://example.com/hooks/a" }
  let(:webhook_url_b) { "https://example.com/hooks/b" }

  before do
    RailsErrorDashboard.configuration.application_name = "TestApp"
  end

  after { RailsErrorDashboard.reset_configuration! }

  describe "#perform" do
    context "with Slack configured" do
      before do
        RailsErrorDashboard.configuration.enable_slack_notifications = true
        RailsErrorDashboard.configuration.slack_webhook_url = slack_url
      end

      it "posts a {text:} payload to the Slack webhook" do
        stub_request(:post, slack_url).to_return(status: 200)

        described_class.perform_now(started_at: started_at)

        expect(WebMock).to have_requested(:post, slack_url).with { |req|
          JSON.parse(req.body).key?("text")
        }.once
      end

      it "includes 'shedding mode' in the message for the default state" do
        stub_request(:post, slack_url).to_return(status: 200)

        described_class.perform_now(started_at: started_at, state: "shedding")

        expect(WebMock).to have_requested(:post, slack_url).with { |req|
          JSON.parse(req.body)["text"].include?("shedding mode")
        }
      end

      it "includes 'count-only mode' in the message when state is 'open'" do
        stub_request(:post, slack_url).to_return(status: 200)

        described_class.perform_now(started_at: started_at, state: "open")

        expect(WebMock).to have_requested(:post, slack_url).with { |req|
          JSON.parse(req.body)["text"].include?("count-only mode")
        }
      end

      it "falls back to 'shedding mode' for any non-'open' state" do
        stub_request(:post, slack_url).to_return(status: 200)

        described_class.perform_now(started_at: started_at, state: "anything")

        expect(WebMock).to have_requested(:post, slack_url).with { |req|
          JSON.parse(req.body)["text"].include?("shedding mode")
        }
      end
    end

    context "with Discord configured" do
      before do
        RailsErrorDashboard.configuration.enable_discord_notifications = true
        RailsErrorDashboard.configuration.discord_webhook_url = discord_url
      end

      it "posts a {content:} payload to the Discord webhook" do
        stub_request(:post, discord_url).to_return(status: 200)

        described_class.perform_now(started_at: started_at)

        expect(WebMock).to have_requested(:post, discord_url).with { |req|
          body = JSON.parse(req.body)
          body.key?("content") && body["content"].include?("Error storm detected")
        }.once
      end
    end

    context "with generic webhooks configured" do
      before do
        RailsErrorDashboard.configuration.enable_webhook_notifications = true
        RailsErrorDashboard.configuration.webhook_urls = [ webhook_url_a, webhook_url_b ]
      end

      it "posts an 'error_storm_detected' payload to every webhook URL" do
        stub_request(:post, webhook_url_a).to_return(status: 200)
        stub_request(:post, webhook_url_b).to_return(status: 200)

        described_class.perform_now(started_at: started_at)

        [ webhook_url_a, webhook_url_b ].each do |url|
          expect(WebMock).to have_requested(:post, url).with { |req|
            JSON.parse(req.body)["event"] == "error_storm_detected"
          }.once
        end
      end
    end

    context "with no notification channels configured" do
      it "does not raise and makes no HTTP calls" do
        expect {
          described_class.perform_now(started_at: started_at)
        }.not_to raise_error

        expect(WebMock).not_to have_requested(:post, /.*/)
      end
    end

    context "when the HTTP post raises" do
      before do
        RailsErrorDashboard.configuration.enable_slack_notifications = true
        RailsErrorDashboard.configuration.slack_webhook_url = slack_url
      end

      it "rescues a raised error and does not propagate it" do
        stub_request(:post, slack_url).to_raise(StandardError.new("boom"))

        expect {
          described_class.perform_now(started_at: started_at, state: "open")
        }.not_to raise_error
      end

      it "rescues a timeout and does not propagate it" do
        stub_request(:post, slack_url).to_timeout

        expect {
          described_class.perform_now(started_at: started_at)
        }.not_to raise_error
      end
    end

    context "dashboard link" do
      before do
        RailsErrorDashboard.configuration.enable_slack_notifications = true
        RailsErrorDashboard.configuration.slack_webhook_url = slack_url
      end

      it "includes the storms link when dashboard_base_url is set (trailing slash chomped)" do
        RailsErrorDashboard.configuration.dashboard_base_url = "https://errors.example.com/"
        stub_request(:post, slack_url).to_return(status: 200)

        described_class.perform_now(started_at: started_at)

        expect(WebMock).to have_requested(:post, slack_url).with { |req|
          JSON.parse(req.body)["text"].include?("https://errors.example.com/errors/storms")
        }
      end

      it "omits the link fragment when dashboard_base_url is nil" do
        RailsErrorDashboard.configuration.dashboard_base_url = nil
        stub_request(:post, slack_url).to_return(status: 200)

        described_class.perform_now(started_at: started_at)

        expect(WebMock).to have_requested(:post, slack_url).with { |req|
          !JSON.parse(req.body)["text"].include?("/errors/storms")
        }
      end
    end
  end
end
