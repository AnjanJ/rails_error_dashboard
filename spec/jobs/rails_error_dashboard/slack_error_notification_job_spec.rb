# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::SlackErrorNotificationJob, type: :job do
  let(:error_log) { create(:error_log) }
  let(:webhook_url) { "https://hooks.slack.com/services/TEST/WEBHOOK/URL" }

  before do
    RailsErrorDashboard.configuration.slack_webhook_url = webhook_url
    RailsErrorDashboard.configuration.dashboard_base_url = "https://example.com"
  end

  describe "#perform" do
    context "when error log exists" do
      it "sends Slack notification" do
        stub_request(:post, webhook_url)
          .with(
            body: hash_including(text: /New Error in/),
            headers: { "Content-Type" => "application/json" }
          )
          .to_return(status: 200, body: "ok")

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).once
      end

      it "includes error type in payload" do
        stub_request(:post, webhook_url).to_return(status: 200)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          body["blocks"].any? { |block|
            block.dig("fields")&.any? { |field| field["text"]&.include?(error_log.error_type) }
          }
        }
      end

      it "includes platform with emoji" do
        error_log.update(platform: "iOS")
        stub_request(:post, webhook_url).to_return(status: 200)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          body["blocks"].any? { |block|
            block.dig("fields")&.any? { |field| field["text"]&.include?("📱") && field["text"]&.include?("iOS") }
          }
        }
      end

      it "includes error message" do
        stub_request(:post, webhook_url).to_return(status: 200)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          body["blocks"].any? { |block|
            block.dig("text", "text")&.include?(error_log.message)
          }
        }
      end

      it "includes dashboard URL button" do
        stub_request(:post, webhook_url).to_return(status: 200)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          actions_block = body["blocks"].find { |b| b["type"] == "actions" }
          actions_block["elements"].any? { |el|
            el["url"] == "https://example.com/error_dashboard/errors/#{error_log.id}"
          }
        }
      end


      context "with request URL" do
        let(:error_log) { create(:error_log, request_url: "https://example.com/api/users") }

        it "includes request URL" do
          stub_request(:post, webhook_url).to_return(status: 200)

          described_class.new.perform(error_log.id)

          expect(WebMock).to have_requested(:post, webhook_url).with { |req|
            body = JSON.parse(req.body)
            body["blocks"].any? { |block|
              block.dig("text", "text")&.include?(error_log.request_url)
            }
          }
        end
      end

      context "when message is very long" do
        let(:long_message) { "Error: " + ("x" * 1000) }
        let(:error_log) { create(:error_log, message: long_message) }

        it "truncates the message" do
          stub_request(:post, webhook_url).to_return(status: 200)

          described_class.new.perform(error_log.id)

          expect(WebMock).to have_requested(:post, webhook_url).with { |req|
            body = JSON.parse(req.body)
            message_block = body["blocks"].find { |b| b.dig("text", "text")&.include?("Message") }
            message_text = message_block.dig("text", "text")
            expect(message_text.length).to be < long_message.length + 100 # Account for markdown wrapper
            expect(message_text).to include("...")
          }
        end
      end
    end

    context "when error log does not exist" do
      it "does not send notification" do
        stub_request(:post, webhook_url)

        described_class.new.perform(999999)

        expect(WebMock).not_to have_requested(:post, webhook_url)
      end
    end

    context "when webhook URL is not configured" do
      before do
        RailsErrorDashboard.configuration.slack_webhook_url = nil
      end

      it "does not send notification" do
        stub_request(:post, webhook_url)

        described_class.new.perform(error_log.id)

        expect(WebMock).not_to have_requested(:post, webhook_url)
      end
    end

    context "when webhook URL is empty string" do
      before do
        RailsErrorDashboard.configuration.slack_webhook_url = ""
      end

      it "does not send notification" do
        stub_request(:post, webhook_url)

        described_class.new.perform(error_log.id)

        expect(WebMock).not_to have_requested(:post, webhook_url)
      end
    end

    context "when Slack API returns error" do
      it "logs the error" do
        stub_request(:post, webhook_url).to_return(status: 500, body: "Internal Server Error")

        allow(Rails.logger).to receive(:error)

        described_class.new.perform(error_log.id)

        expect(Rails.logger).to have_received(:error).with(/Slack notification failed/)
      end
    end

    context "when network error occurs" do
      it "handles the exception gracefully" do
        stub_request(:post, webhook_url).to_raise(StandardError.new("Network error"))

        allow(Rails.logger).to receive(:error)

        expect {
          described_class.new.perform(error_log.id)
        }.not_to raise_error

        expect(Rails.logger).to have_received(:error).with(/Failed to send Slack notification/)
      end
    end
  end

  describe "job queue" do
    it "is enqueued to error_notifications queue" do
      expect(described_class.new.queue_name).to eq("error_notifications")
    end
  end
end
