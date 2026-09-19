# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::WebhookErrorNotificationJob, type: :job do
  let(:error_log) { create(:error_log) }
  let(:webhook_url) { "https://example.com/webhooks/errors" }

  before do
    RailsErrorDashboard.configuration.webhook_urls = webhook_url
    RailsErrorDashboard.configuration.dashboard_base_url = "https://example.com"
  end

  # Global configuration: restore it, or these URLs outlive the file and a later
  # spec that enables webhooks finds live endpoints waiting.
  after { RailsErrorDashboard.reset_configuration! }

  describe "#perform" do
    context "when error log exists" do
      it "sends webhook notification" do
        stub_request(:post, webhook_url)
          .with(
            body: hash_including(event: "error.created"),
            headers: {
              "Content-Type" => "application/json",
              "User-Agent" => "RailsErrorDashboard/1.0",
              "X-Error-Dashboard-Event" => "error.created",
              "X-Error-Dashboard-ID" => error_log.id.to_s
            }
          )
          .to_return(status: 200)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).once
      end

      it "includes event type in payload" do
        stub_request(:post, webhook_url).to_return(status: 200)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          body["event"] == "error.created"
        }
      end

      it "includes timestamp in ISO8601 format" do
        stub_request(:post, webhook_url).to_return(status: 200)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          timestamp = body["timestamp"]
          timestamp.present? && timestamp.match?(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        }
      end

      it "includes error ID" do
        stub_request(:post, webhook_url).to_return(status: 200)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          body["error"]["id"] == error_log.id
        }
      end

      it "includes error type and message" do
        stub_request(:post, webhook_url).to_return(status: 200)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          error = body["error"]
          error["type"] == error_log.error_type && error["message"] == error_log.message
        }
      end

      it "includes severity as string" do
        stub_request(:post, webhook_url).to_return(status: 200)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          body["error"]["severity"].is_a?(String)
        }
      end

      it "includes platform" do
        error_log.update(platform: "iOS")
        stub_request(:post, webhook_url).to_return(status: 200)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          error = body["error"]
          error["platform"] == "iOS"
        }
      end

      it "includes controller and action" do
        error_log.update(controller_name: "UsersController", action_name: "show")
        stub_request(:post, webhook_url).to_return(status: 200)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          error = body["error"]
          error["controller"] == "UsersController" && error["action"] == "show"
        }
      end

      it "includes occurrence count" do
        error_log.update(occurrence_count: 42)
        stub_request(:post, webhook_url).to_return(status: 200)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          body["error"]["occurrence_count"] == 42
        }
      end

      it "includes timestamps in ISO8601 format" do
        stub_request(:post, webhook_url).to_return(status: 200)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          error = body["error"]
          error["occurred_at"].match?(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        }
      end

      it "includes resolved status" do
        error_log.update(resolved: true)
        stub_request(:post, webhook_url).to_return(status: 200)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          body["error"]["resolved"] == true
        }
      end

      it "includes request information" do
        error_log.update(
          request_url: "https://example.com/api/users",
          user_agent: "Mozilla/5.0",
          ip_address: "192.168.1.1"
        )
        stub_request(:post, webhook_url).to_return(status: 200)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          request = body["error"]["request"]
          request["url"] == "https://example.com/api/users" &&
          request["user_agent"] == "Mozilla/5.0" &&
          request["ip_address"] == "192.168.1.1"
        }
      end

      it "includes request params when present" do
        error_log.update(request_params: '{"name":"John","email":"john@example.com"}')
        stub_request(:post, webhook_url).to_return(status: 200)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          params = body["error"]["request"]["params"]
          params["name"] == "John" && params["email"] == "john@example.com"
        }
      end

      it "includes user ID" do
        user = create(:user)
        error_log.update(user_id: user.id)
        stub_request(:post, webhook_url).to_return(status: 200)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          body["error"]["user"]["id"] == user.id
        }
      end

      it "includes backtrace (first 20 lines)" do
        backtrace = (1..30).map { |i| "app/controllers/users_controller.rb:#{i}:in `show`" }.join("\n")
        error_log.update(backtrace: backtrace)
        stub_request(:post, webhook_url).to_return(status: 200)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          backtrace_array = body["error"]["backtrace"]
          expect(backtrace_array).to be_an(Array)
          expect(backtrace_array.length).to eq(20)
          expect(backtrace_array.first).to include("users_controller.rb:1")
          expect(backtrace_array.last).to include("users_controller.rb:20")
        }
      end

      it "includes metadata with error hash" do
        stub_request(:post, webhook_url).to_return(status: 200)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          body["error"]["metadata"]["error_hash"] == error_log.error_hash
        }
      end

      it "includes metadata with dashboard URL" do
        stub_request(:post, webhook_url).to_return(status: 200)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          url = body["error"]["metadata"]["dashboard_url"]
          url == "https://example.com/error_dashboard/errors/#{error_log.id}"
        }
      end

      it "sets custom headers" do
        stub_request(:post, webhook_url).to_return(status: 200)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with(
          headers: {
            "Content-Type" => "application/json",
            "User-Agent" => "RailsErrorDashboard/1.0",
            "X-Error-Dashboard-Event" => "error.created",
            "X-Error-Dashboard-ID" => error_log.id.to_s
          }
        )
      end

      context "with invalid request params JSON" do
        it "returns empty hash for invalid JSON" do
          error_log.update(request_params: "invalid json {")
          stub_request(:post, webhook_url).to_return(status: 200)

          described_class.new.perform(error_log.id)

          expect(WebMock).to have_requested(:post, webhook_url).with { |req|
            body = JSON.parse(req.body)
            body["error"]["request"]["params"] == {}
          }
        end
      end

      context "with nil request params" do
        it "returns empty hash" do
          error_log.update(request_params: nil)
          stub_request(:post, webhook_url).to_return(status: 200)

          described_class.new.perform(error_log.id)

          expect(WebMock).to have_requested(:post, webhook_url).with { |req|
            body = JSON.parse(req.body)
            body["error"]["request"]["params"] == {}
          }
        end
      end

      context "with nil backtrace" do
        it "returns empty array" do
          error_log.update(backtrace: nil)
          stub_request(:post, webhook_url).to_return(status: 200)

          described_class.new.perform(error_log.id)

          expect(WebMock).to have_requested(:post, webhook_url).with { |req|
            body = JSON.parse(req.body)
            body["error"]["backtrace"] == []
          }
        end
      end
    end

    context "with multiple webhook URLs" do
      let(:webhook_urls) { [ "https://example.com/webhook1", "https://example.com/webhook2" ] }

      before do
        RailsErrorDashboard.configuration.webhook_urls = webhook_urls
      end

      it "sends to all webhook URLs" do
        webhook_urls.each do |url|
          stub_request(:post, url).to_return(status: 200)
        end

        described_class.new.perform(error_log.id)

        webhook_urls.each do |url|
          expect(WebMock).to have_requested(:post, url).once
        end
      end

      it "continues sending if one webhook fails" do
        stub_request(:post, webhook_urls[0]).to_return(status: 500)
        stub_request(:post, webhook_urls[1]).to_return(status: 200)

        allow(Rails.logger).to receive(:warn)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_urls[0]).once
        expect(WebMock).to have_requested(:post, webhook_urls[1]).once
      end
    end

    context "when error log does not exist" do
      it "handles the exception gracefully" do
        webhook_url = "https://example.com/webhooks/errors"
        stub_request(:post, webhook_url)

        allow(Rails.logger).to receive(:error)

        expect {
          described_class.new.perform(999999)
        }.not_to raise_error

        expect(WebMock).not_to have_requested(:post, webhook_url)
        expect(Rails.logger).to have_received(:error).with(/Failed to send webhook notification/)
      end
    end

    context "when webhook URLs are not configured" do
      before do
        RailsErrorDashboard.configuration.webhook_urls = nil
      end

      it "does not send notification" do
        stub_request(:post, webhook_url)

        described_class.new.perform(error_log.id)

        expect(WebMock).not_to have_requested(:post, webhook_url)
      end
    end

    context "when webhook URLs array is empty" do
      before do
        RailsErrorDashboard.configuration.webhook_urls = []
      end

      it "does not send notification" do
        stub_request(:post, webhook_url)

        described_class.new.perform(error_log.id)

        expect(WebMock).not_to have_requested(:post, webhook_url)
      end
    end

    context "when webhook API returns error" do
      it "logs warning for failed webhook" do
        stub_request(:post, webhook_url).to_return(status: 500, body: "Internal Server Error")

        allow(Rails.logger).to receive(:warn)

        described_class.new.perform(error_log.id)

        expect(Rails.logger).to have_received(:warn).with(/Webhook failed for #{webhook_url}: 500/)
      end
    end

    context "when network error occurs for specific webhook" do
      it "logs error and continues" do
        stub_request(:post, webhook_url).to_raise(StandardError.new("Network error"))

        allow(Rails.logger).to receive(:error)

        expect {
          described_class.new.perform(error_log.id)
        }.not_to raise_error

        expect(Rails.logger).to have_received(:error).with(/Webhook error for #{webhook_url}/)
      end
    end

    context "when dashboard_base_url is not configured" do
      before do
        RailsErrorDashboard.configuration.dashboard_base_url = nil
      end

      it "uses localhost as fallback" do
        stub_request(:post, webhook_url).to_return(status: 200)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          url = body["error"]["metadata"]["dashboard_url"]
          url == "http://localhost:3000/error_dashboard/errors/#{error_log.id}"
        }
      end
    end
  end

  describe "job queue" do
    it "is enqueued to default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end
end
