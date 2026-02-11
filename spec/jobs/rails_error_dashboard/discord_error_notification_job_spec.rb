# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::DiscordErrorNotificationJob, type: :job do
  let(:error_log) { create(:error_log) }
  let(:webhook_url) { "https://discord.com/api/webhooks/123456789/test_webhook" }

  before do
    RailsErrorDashboard.configuration.discord_webhook_url = webhook_url
  end

  describe "#perform" do
    context "when error log exists" do
      it "sends Discord notification" do
        stub_request(:post, webhook_url)
          .with(
            body: hash_including(embeds: array_including(hash_including(title: /New Error/))),
            headers: { "Content-Type" => "application/json" }
          )
          .to_return(status: 204)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).once
      end

      it "includes error type in embed title" do
        stub_request(:post, webhook_url).to_return(status: 204)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          body["embeds"].first["title"].include?(error_log.error_type)
        }
      end

      it "includes error icon in embed title" do
        stub_request(:post, webhook_url).to_return(status: 204)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          body["embeds"].first["title"].include?("🚨")
        }
      end

      it "includes error message in description" do
        stub_request(:post, webhook_url).to_return(status: 204)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          body["embeds"].first["description"] == error_log.message
        }
      end

      it "includes platform field" do
        error_log.update(platform: "iOS")
        stub_request(:post, webhook_url).to_return(status: 204)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          platform_field = body["embeds"].first["fields"].find { |f| f["name"] == "Platform" }
          platform_field["value"] == "iOS" && platform_field["inline"] == true
        }
      end

      it "includes occurrence count field" do
        error_log.update(occurrence_count: 42)
        stub_request(:post, webhook_url).to_return(status: 204)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          count_field = body["embeds"].first["fields"].find { |f| f["name"] == "Occurrences" }
          count_field["value"] == "42"
        }
      end

      it "includes controller field" do
        error_log.update(controller_name: "UsersController")
        stub_request(:post, webhook_url).to_return(status: 204)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          controller_field = body["embeds"].first["fields"].find { |f| f["name"] == "Controller" }
          controller_field["value"] == "UsersController"
        }
      end

      it "includes action field" do
        error_log.update(action_name: "show")
        stub_request(:post, webhook_url).to_return(status: 204)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          action_field = body["embeds"].first["fields"].find { |f| f["name"] == "Action" }
          action_field["value"] == "show"
        }
      end

      it "includes first seen timestamp" do
        stub_request(:post, webhook_url).to_return(status: 204)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          time_field = body["embeds"].first["fields"].find { |f| f["name"] == "First Seen" }
          time_field["value"].present?
        }
      end

      it "includes location from backtrace" do
        error_log.update(backtrace: "app/controllers/users_controller.rb:42:in `show`")
        stub_request(:post, webhook_url).to_return(status: 204)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          location_field = body["embeds"].first["fields"].find { |f| f["name"] == "Location" }
          location_field["value"].include?("users_controller.rb")
        }
      end

      it "includes footer" do
        stub_request(:post, webhook_url).to_return(status: 204)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          body["embeds"].first["footer"]["text"] == "Rails Error Dashboard"
        }
      end

      it "includes ISO8601 timestamp" do
        stub_request(:post, webhook_url).to_return(status: 204)

        described_class.new.perform(error_log.id)

        expect(WebMock).to have_requested(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          timestamp = body["embeds"].first["timestamp"]
          timestamp.present? && timestamp.match?(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        }
      end

      context "when message is very long" do
        let(:long_message) { "Error: " + ("x" * 300) }
        let(:error_log) { create(:error_log, message: long_message) }

        it "truncates the message" do
          stub_request(:post, webhook_url).to_return(status: 204)

          described_class.new.perform(error_log.id)

          expect(WebMock).to have_requested(:post, webhook_url).with { |req|
            body = JSON.parse(req.body)
            description = body["embeds"].first["description"]
            expect(description.length).to be <= 203 # 200 + "..."
            expect(description).to end_with("...")
          }
        end
      end

      context "when backtrace is very long" do
        let(:long_backtrace_line) { "app/controllers/very/deep/nested/path/" + ("x" * 200) + ".rb:42:in `method`" }
        let(:error_log) { create(:error_log, backtrace: long_backtrace_line) }

        it "truncates the backtrace location" do
          stub_request(:post, webhook_url).to_return(status: 204)

          described_class.new.perform(error_log.id)

          expect(WebMock).to have_requested(:post, webhook_url).with { |req|
            body = JSON.parse(req.body)
            location_field = body["embeds"].first["fields"].find { |f| f["name"] == "Location" }
            expect(location_field["value"].length).to be <= 103 # 100 + "..."
            expect(location_field["value"]).to end_with("...")
          }
        end
      end

      context "with multiline backtrace" do
        let(:backtrace) do
          [
            "app/controllers/users_controller.rb:42:in `show`",
            "app/middleware/auth.rb:10:in `call`",
            "lib/framework/base.rb:5:in `process`"
          ].join("\n")
        end
        let(:error_log) { create(:error_log, backtrace: backtrace) }

        it "extracts only first line" do
          stub_request(:post, webhook_url).to_return(status: 204)

          described_class.new.perform(error_log.id)

          expect(WebMock).to have_requested(:post, webhook_url).with { |req|
            body = JSON.parse(req.body)
            location_field = body["embeds"].first["fields"].find { |f| f["name"] == "Location" }
            location = location_field["value"]
            expect(location).to include("users_controller.rb")
            expect(location).not_to include("auth.rb")
          }
        end
      end

      context "with nil or missing fields" do
        let(:error_log) do
          # Note: platform defaults to "API" via model callback
          # first_seen_at defaults to Time.current via model callback
          create(:error_log,
            controller_name: nil,
            action_name: nil,
            backtrace: nil
          )
        end

        it "handles nil controller gracefully" do
          stub_request(:post, webhook_url).to_return(status: 204)

          described_class.new.perform(error_log.id)

          expect(WebMock).to have_requested(:post, webhook_url).with { |req|
            body = JSON.parse(req.body)
            controller_field = body["embeds"].first["fields"].find { |f| f["name"] == "Controller" }
            controller_field["value"] == "N/A"
          }
        end

        it "handles nil action gracefully" do
          stub_request(:post, webhook_url).to_return(status: 204)

          described_class.new.perform(error_log.id)

          expect(WebMock).to have_requested(:post, webhook_url).with { |req|
            body = JSON.parse(req.body)
            action_field = body["embeds"].first["fields"].find { |f| f["name"] == "Action" }
            action_field["value"] == "N/A"
          }
        end

        it "handles nil backtrace gracefully" do
          stub_request(:post, webhook_url).to_return(status: 204)

          described_class.new.perform(error_log.id)

          expect(WebMock).to have_requested(:post, webhook_url).with { |req|
            body = JSON.parse(req.body)
            location_field = body["embeds"].first["fields"].find { |f| f["name"] == "Location" }
            location_field["value"] == "N/A"
          }
        end
      end
    end

    context "when error log does not exist" do
      it "handles the exception gracefully" do
        stub_request(:post, webhook_url)

        allow(Rails.logger).to receive(:error)

        expect {
          described_class.new.perform(999999)
        }.not_to raise_error

        expect(WebMock).not_to have_requested(:post, webhook_url)
        expect(Rails.logger).to have_received(:error).with(/Failed to send Discord notification/)
      end
    end

    context "when webhook URL is not configured" do
      before do
        RailsErrorDashboard.configuration.discord_webhook_url = nil
      end

      it "does not send notification" do
        stub_request(:post, webhook_url)

        described_class.new.perform(error_log.id)

        expect(WebMock).not_to have_requested(:post, webhook_url)
      end
    end

    context "when webhook URL is empty string" do
      before do
        RailsErrorDashboard.configuration.discord_webhook_url = ""
      end

      it "does not send notification" do
        stub_request(:post, webhook_url)

        described_class.new.perform(error_log.id)

        expect(WebMock).not_to have_requested(:post, webhook_url)
      end
    end

    context "when Discord API returns error" do
      it "logs the error" do
        stub_request(:post, webhook_url).to_raise(StandardError.new("API Error"))

        allow(Rails.logger).to receive(:error)

        described_class.new.perform(error_log.id)

        expect(Rails.logger).to have_received(:error).with(/Failed to send Discord notification/)
      end
    end

    context "when network error occurs" do
      it "handles the exception gracefully" do
        stub_request(:post, webhook_url).to_raise(StandardError.new("Network error"))

        allow(Rails.logger).to receive(:error)

        expect {
          described_class.new.perform(error_log.id)
        }.not_to raise_error

        expect(Rails.logger).to have_received(:error).with(/Failed to send Discord notification/)
      end
    end
  end

  describe "job queue" do
    it "is enqueued to default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end
end
