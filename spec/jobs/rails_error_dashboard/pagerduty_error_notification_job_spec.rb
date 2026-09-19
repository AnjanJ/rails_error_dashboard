# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::PagerdutyErrorNotificationJob, type: :job do
  let(:error_log) { create(:error_log, error_type: "SecurityError") }
  let(:integration_key) { "test_pagerduty_key_12345" }
  let(:pagerduty_api_url) { "https://events.pagerduty.com/v2/enqueue" }

  before do
    RailsErrorDashboard.configuration.pagerduty_integration_key = integration_key
    RailsErrorDashboard.configuration.dashboard_base_url = "https://example.com"
  end

  # Global configuration: restore it, or this key outlives the file and a later
  # spec that enables PagerDuty finds a usable integration key waiting.
  after { RailsErrorDashboard.reset_configuration! }

  describe "#perform" do
    context "when error is critical" do
      it "sends PagerDuty notification" do
        stub_request(:post, pagerduty_api_url)
          .with(
            body: hash_including(routing_key: integration_key, event_action: "trigger"),
            headers: { "Content-Type" => "application/json" }
          )
          .to_return(status: 202, body: { status: "success", dedup_key: "abc123" }.to_json)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, pagerduty_api_url).once
      end

      it "includes routing key in payload" do
        stub_request(:post, pagerduty_api_url).to_return(status: 202)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, pagerduty_api_url).with { |req|
          body = JSON.parse(req.body)
          body["routing_key"] == integration_key
        }
      end

      it "uses trigger event action" do
        stub_request(:post, pagerduty_api_url).to_return(status: 202)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, pagerduty_api_url).with { |req|
          body = JSON.parse(req.body)
          body["event_action"] == "trigger"
        }
      end

      it "includes error type in summary" do
        stub_request(:post, pagerduty_api_url).to_return(status: 202)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, pagerduty_api_url).with { |req|
          body = JSON.parse(req.body)
          body["payload"]["summary"].include?(error_log.error_type)
        }
      end

      it "includes platform in summary" do
        error_log.update(platform: "iOS")
        stub_request(:post, pagerduty_api_url).to_return(status: 202)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, pagerduty_api_url).with { |req|
          body = JSON.parse(req.body)
          body["payload"]["summary"].include?("iOS")
        }
      end

      it "sets severity to critical" do
        stub_request(:post, pagerduty_api_url).to_return(status: 202)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, pagerduty_api_url).with { |req|
          body = JSON.parse(req.body)
          body["payload"]["severity"] == "critical"
        }
      end

      it "includes error source" do
        error_log.update(controller_name: "UsersController", action_name: "show")
        stub_request(:post, pagerduty_api_url).to_return(status: 202)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, pagerduty_api_url).with { |req|
          body = JSON.parse(req.body)
          body["payload"]["source"] == "UsersController#show"
        }
      end

      it "includes component from controller name" do
        error_log.update(controller_name: "UsersController")
        stub_request(:post, pagerduty_api_url).to_return(status: 202)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, pagerduty_api_url).with { |req|
          body = JSON.parse(req.body)
          body["payload"]["component"] == "UsersController"
        }
      end

      it "includes error type as group and class" do
        stub_request(:post, pagerduty_api_url).to_return(status: 202)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, pagerduty_api_url).with { |req|
          body = JSON.parse(req.body)
          body["payload"]["group"] == error_log.error_type &&
          body["payload"]["class"] == error_log.error_type
        }
      end

      it "includes custom details with error message" do
        stub_request(:post, pagerduty_api_url).to_return(status: 202)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, pagerduty_api_url).with { |req|
          body = JSON.parse(req.body)
          body["payload"]["custom_details"]["message"] == error_log.message
        }
      end

      it "includes custom details with controller and action" do
        error_log.update(controller_name: "UsersController", action_name: "show")
        stub_request(:post, pagerduty_api_url).to_return(status: 202)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, pagerduty_api_url).with { |req|
          body = JSON.parse(req.body)
          details = body["payload"]["custom_details"]
          details["controller"] == "UsersController" && details["action"] == "show"
        }
      end

      it "includes custom details with platform" do
        error_log.update(platform: "Android")
        stub_request(:post, pagerduty_api_url).to_return(status: 202)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, pagerduty_api_url).with { |req|
          body = JSON.parse(req.body)
          details = body["payload"]["custom_details"]
          details["platform"] == "Android"
        }
      end

      it "includes custom details with occurrence count" do
        error_log.update(occurrence_count: 42)
        stub_request(:post, pagerduty_api_url).to_return(status: 202)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, pagerduty_api_url).with { |req|
          body = JSON.parse(req.body)
          body["payload"]["custom_details"]["occurrences"] == 42
        }
      end

      it "includes custom details with timestamps in ISO8601 format" do
        stub_request(:post, pagerduty_api_url).to_return(status: 202)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, pagerduty_api_url).with { |req|
          body = JSON.parse(req.body)
          details = body["payload"]["custom_details"]
          details["first_seen_at"].present? && details["first_seen_at"].match?(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        }
      end

      it "includes custom details with request URL" do
        error_log.update(request_url: "https://example.com/api/users")
        stub_request(:post, pagerduty_api_url).to_return(status: 202)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, pagerduty_api_url).with { |req|
          body = JSON.parse(req.body)
          body["payload"]["custom_details"]["request_url"] == "https://example.com/api/users"
        }
      end

      it "includes backtrace summary (first 10 lines)" do
        backtrace = (1..20).map { |i| "app/controllers/users_controller.rb:#{i}:in `show`" }.join("\n")
        error_log.update(backtrace: backtrace)
        stub_request(:post, pagerduty_api_url).to_return(status: 202)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, pagerduty_api_url).with { |req|
          body = JSON.parse(req.body)
          backtrace_array = body["payload"]["custom_details"]["backtrace"]
          expect(backtrace_array).to be_an(Array)
          expect(backtrace_array.length).to eq(10)
          expect(backtrace_array.first).to include("users_controller.rb:1")
          expect(backtrace_array.last).to include("users_controller.rb:10")
        }
      end

      it "includes error ID in custom details" do
        stub_request(:post, pagerduty_api_url).to_return(status: 202)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, pagerduty_api_url).with { |req|
          body = JSON.parse(req.body)
          body["payload"]["custom_details"]["error_id"] == error_log.id
        }
      end

      it "includes dashboard link" do
        stub_request(:post, pagerduty_api_url).to_return(status: 202)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, pagerduty_api_url).with { |req|
          body = JSON.parse(req.body)
          link = body["links"].first
          link["href"] == "https://example.com/error_dashboard/errors/#{error_log.id}" &&
          link["text"] == "View in Error Dashboard"
        }
      end

      it "includes client information" do
        stub_request(:post, pagerduty_api_url).to_return(status: 202)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, pagerduty_api_url).with { |req|
          body = JSON.parse(req.body)
          body["client"] == "Rails Error Dashboard" &&
          body["client_url"] == "https://example.com/error_dashboard/errors/#{error_log.id}"
        }
      end

      context "when source determination falls back" do
        it "uses request URL when controller and action are nil" do
          error_log.update(
            controller_name: nil,
            action_name: nil,
            request_url: "https://example.com/api/test"
          )
          stub_request(:post, pagerduty_api_url).to_return(status: 202)

          described_class.new.perform(error_log.id)

          expect(WebMock).to have_requested(:post, pagerduty_api_url).with { |req|
            body = JSON.parse(req.body)
            body["payload"]["source"] == "https://example.com/api/test"
          }
        end

        it "uses platform when controller, action, and request URL are nil" do
          error_log.update(
            controller_name: nil,
            action_name: nil,
            request_url: nil,
            platform: "iOS"
          )
          stub_request(:post, pagerduty_api_url).to_return(status: 202)

          described_class.new.perform(error_log.id)

          expect(WebMock).to have_requested(:post, pagerduty_api_url).with { |req|
            body = JSON.parse(req.body)
            body["payload"]["source"] == "iOS"
          }
        end

        it "uses default when all source fields are nil" do
          error_log.update(
            controller_name: nil,
            action_name: nil,
            request_url: nil,
            platform: nil
          )
          stub_request(:post, pagerduty_api_url).to_return(status: 202)

          described_class.new.perform(error_log.id)

          expect(WebMock).to have_requested(:post, pagerduty_api_url).with { |req|
            body = JSON.parse(req.body)
            body["payload"]["source"] == "Rails Application"
          }
        end
      end

      context "when backtrace is nil" do
        it "returns empty array" do
          error_log.update(backtrace: nil)
          stub_request(:post, pagerduty_api_url).to_return(status: 202)

          described_class.new.perform(error_log.id)

          expect(WebMock).to have_requested(:post, pagerduty_api_url).with { |req|
            body = JSON.parse(req.body)
            body["payload"]["custom_details"]["backtrace"] == []
          }
        end
      end
    end

    context "when error is not critical" do
      let(:error_log) { create(:error_log, error_type: "ArgumentError") }

      it "does not send notification" do
        stub_request(:post, pagerduty_api_url)

        described_class.new.perform(error_log.id)

        expect(WebMock).not_to have_requested(:post, pagerduty_api_url)
      end
    end

    context "when error log does not exist" do
      it "handles the exception gracefully" do
        stub_request(:post, pagerduty_api_url)

        allow(Rails.logger).to receive(:error)

        expect {
          described_class.new.perform(999999)
        }.not_to raise_error

        expect(WebMock).not_to have_requested(:post, pagerduty_api_url)
        expect(Rails.logger).to have_received(:error).with(/Failed to send PagerDuty notification/)
      end
    end

    context "when integration key is not configured" do
      before do
        RailsErrorDashboard.configuration.pagerduty_integration_key = nil
      end

      it "does not send notification" do
        stub_request(:post, pagerduty_api_url)

        described_class.new.perform(error_log.id)

        expect(WebMock).not_to have_requested(:post, pagerduty_api_url)
      end
    end

    context "when integration key is empty string" do
      before do
        RailsErrorDashboard.configuration.pagerduty_integration_key = ""
      end

      it "does not send notification" do
        stub_request(:post, pagerduty_api_url)

        described_class.new.perform(error_log.id)

        expect(WebMock).not_to have_requested(:post, pagerduty_api_url)
      end
    end

    context "when PagerDuty API returns error" do
      it "logs the error" do
        stub_request(:post, pagerduty_api_url)
          .to_return(status: 400, body: { status: "invalid event", errors: [ "routing_key is invalid" ] }.to_json)

        allow(Rails.logger).to receive(:error)

        described_class.new.perform(error_log.id)

        expect(Rails.logger).to have_received(:error).with(/PagerDuty API error: 400/)
      end
    end

    context "when network error occurs" do
      it "handles the exception gracefully" do
        stub_request(:post, pagerduty_api_url).to_raise(StandardError.new("Network error"))

        allow(Rails.logger).to receive(:error)

        expect {
          described_class.new.perform(error_log.id)
        }.not_to raise_error

        expect(Rails.logger).to have_received(:error).with(/Failed to send PagerDuty notification/)
      end
    end

    context "when dashboard_base_url is not configured" do
      before do
        RailsErrorDashboard.configuration.dashboard_base_url = nil
      end

      it "uses localhost as fallback" do
        stub_request(:post, pagerduty_api_url).to_return(status: 202)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, pagerduty_api_url).with { |req|
          body = JSON.parse(req.body)
          body["client_url"] == "http://localhost:3000/error_dashboard/errors/#{error_log.id}"
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
