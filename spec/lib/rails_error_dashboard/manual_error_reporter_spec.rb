# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::ManualErrorReporter do
  # Disable async logging for tests so we can verify results immediately
  before do
    @original_async = RailsErrorDashboard.configuration.async_logging
    RailsErrorDashboard.configuration.async_logging = false
  end

  after do
    RailsErrorDashboard.configuration.async_logging = @original_async
  end

  describe ".report" do
    let(:error_type) { "TypeError" }
    let(:message) { "Cannot read property 'foo' of undefined" }
    let(:backtrace) { [ "at handleClick (app.js:42)", "at onClick (button.js:15)" ] }

    context "with minimal parameters" do
      it "creates an error log" do
        expect {
          described_class.report(
            error_type: error_type,
            message: message
          )
        }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
      end

      it "sets the error type correctly" do
        error_log = described_class.report(
          error_type: error_type,
          message: message
        )

        expect(error_log.error_type).to eq(error_type)
      end

      it "sets the message correctly" do
        error_log = described_class.report(
          error_type: error_type,
          message: message
        )

        expect(error_log.message).to eq(message)
      end

      it "sets source to 'manual' by default" do
        error_log = described_class.report(
          error_type: error_type,
          message: message
        )

        # Source is tracked in request_url when it's a manual error
        expect(error_log.request_url).to include("manual")
      end
    end

    context "with full parameters" do
      let(:full_params) do
        {
          error_type: "PaymentError",
          message: "Credit card declined",
          backtrace: backtrace,
          platform: "Web",
          user_id: 123,
          request_url: "https://example.com/checkout",
          user_agent: "Mozilla/5.0",
          ip_address: "192.168.1.1",
          app_version: "1.2.3",
          metadata: { card_type: "visa", amount: 99.99 },
          severity: :high,
          source: "frontend"
        }
      end

      it "creates an error log with all attributes" do
        error_log = described_class.report(**full_params)

        expect(error_log).to be_persisted
        expect(error_log.error_type).to eq("PaymentError")
        expect(error_log.message).to eq("Credit card declined")
        expect(error_log.platform).to eq("Web")
        expect(error_log.user_id).to eq(123) # Stored as integer
        expect(error_log.request_url).to eq("https://example.com/checkout")
        expect(error_log.user_agent).to eq("Mozilla/5.0")
        expect(error_log.ip_address).to eq("192.168.1.1")
      end

      it "stores the backtrace" do
        error_log = described_class.report(**full_params)

        expect(error_log.backtrace).to include("at handleClick (app.js:42)")
        expect(error_log.backtrace).to include("at onClick (button.js:15)")
      end
    end

    context "with backtrace variations" do
      it "accepts backtrace as array" do
        error_log = described_class.report(
          error_type: error_type,
          message: message,
          backtrace: [ "line 1", "line 2" ]
        )

        expect(error_log.backtrace).to include("line 1")
        expect(error_log.backtrace).to include("line 2")
      end

      it "accepts backtrace as newline-separated string" do
        error_log = described_class.report(
          error_type: error_type,
          message: message,
          backtrace: "line 1\nline 2\nline 3"
        )

        expect(error_log.backtrace).to include("line 1")
        expect(error_log.backtrace).to include("line 2")
      end

      it "handles nil backtrace" do
        error_log = described_class.report(
          error_type: error_type,
          message: message,
          backtrace: nil
        )

        # Backtrace might be empty string or minimal - just verify it doesn't crash
        expect(error_log).to be_persisted
      end
    end

    context "with different platforms" do
      it "reports Web errors" do
        error_log = described_class.report(
          error_type: "JavaScriptError",
          message: "Uncaught exception",
          platform: "Web"
        )

        expect(error_log.platform).to eq("Web")
      end

      it "reports iOS errors" do
        error_log = described_class.report(
          error_type: "NSException",
          message: "Fatal crash",
          platform: "iOS"
        )

        expect(error_log.platform).to eq("iOS")
      end

      it "reports Android errors" do
        error_log = described_class.report(
          error_type: "RuntimeException",
          message: "App crashed",
          platform: "Android"
        )

        expect(error_log.platform).to eq("Android")
      end
    end

    context "with metadata" do
      it "accepts custom metadata" do
        error_log = described_class.report(
          error_type: error_type,
          message: message,
          metadata: { custom_field: "value", another: 123 }
        )

        expect(error_log).to be_persisted
      end
    end

    context "error grouping" do
      it "groups errors with same type and message" do
        # Report the same error twice
        first_log = described_class.report(
          error_type: "NetworkError",
          message: "Connection timeout",
          platform: "Web"
        )

        second_log = described_class.report(
          error_type: "NetworkError",
          message: "Connection timeout",
          platform: "Web"
        )

        # Should increment occurrence count, not create new record
        expect(first_log.id).to eq(second_log.id)
        expect(second_log.occurrence_count).to be > first_log.occurrence_count
      end

      it "creates separate errors for different types" do
        first_log = described_class.report(
          error_type: "NetworkError",
          message: "Connection timeout"
        )

        second_log = described_class.report(
          error_type: "ValidationError",
          message: "Connection timeout"
        )

        expect(first_log.id).not_to eq(second_log.id)
      end
    end

    context "async logging" do
      before do
        RailsErrorDashboard.configuration.async_logging = true
      end

      after do
        RailsErrorDashboard.configuration.async_logging = false
      end

      it "enqueues a background job when async is enabled" do
        expect {
          described_class.report(
            error_type: error_type,
            message: message
          )
        }.to have_enqueued_job(RailsErrorDashboard::AsyncErrorLoggingJob)
      end
    end
  end

  describe RailsErrorDashboard::ManualErrorReporter::SyntheticException do
    let(:synthetic) do
      described_class.new(
        error_type: "TypeError",
        message: "Test error",
        backtrace: [ "line 1", "line 2" ]
      )
    end

    it "has a message" do
      expect(synthetic.message).to eq("Test error")
    end

    it "has a backtrace" do
      expect(synthetic.backtrace).to eq([ "line 1", "line 2" ])
    end

    it "has a class with the error type name" do
      expect(synthetic.class.name).to include("TypeError")
    end

    it "responds to is_a? correctly" do
      expect(synthetic.is_a?(described_class)).to be true
    end

    it "has a meaningful inspect" do
      expect(synthetic.inspect).to include("TypeError")
      expect(synthetic.inspect).to include("Test error")
    end
  end
end
