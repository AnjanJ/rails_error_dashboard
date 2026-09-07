# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::AsyncErrorLoggingJob, type: :job do
  describe "#perform" do
    let(:exception_data) do
      {
        class_name: "StandardError",
        message: "Test async error",
        backtrace: [ "app/controllers/test_controller.rb:10:in `index'" ]
      }
    end
    let(:context) { { user_id: 1, platform: "API" } }

    it "creates an error log" do
      expect {
        described_class.new.perform(exception_data, context)
      }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
    end

    it "reconstructs the exception with correct class" do
      described_class.new.perform(exception_data, context)
      error_log = RailsErrorDashboard::ErrorLog.last

      expect(error_log.error_type).to eq("StandardError")
    end

    it "reconstructs the exception with correct message" do
      described_class.new.perform(exception_data, context)
      error_log = RailsErrorDashboard::ErrorLog.last

      expect(error_log.message).to eq("Test async error")
    end

    it "reconstructs the exception with correct backtrace" do
      described_class.new.perform(exception_data, context)
      error_log = RailsErrorDashboard::ErrorLog.last

      expect(error_log.backtrace).to include("app/controllers/test_controller.rb:10:in `index'")
    end

    context "with exception classes whose constructors do not take a message" do
      it "keeps ActiveRecord::RecordInvalid (constructor wants a record) with its class and message" do
        data = { class_name: "ActiveRecord::RecordInvalid", message: "Validation failed: Name can't be blank",
                 backtrace: [ "app/models/user.rb:10" ] }

        expect { described_class.new.perform(data, context) }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
        log = RailsErrorDashboard::ErrorLog.last
        expect(log.error_type).to eq("ActiveRecord::RecordInvalid")
        expect(log.message).to eq("Validation failed: Name can't be blank")
      end

      it "keeps a custom exception with a required keyword argument" do
        stub_const("KeywordError", Class.new(StandardError) do
          def initialize(message, code:)
            @code = code
            super(message)
          end
        end)
        data = { class_name: "KeywordError", message: "failed with code", backtrace: [] }

        expect { described_class.new.perform(data, context) }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
        expect(RailsErrorDashboard::ErrorLog.last.error_type).to eq("KeywordError")
      end

      it "falls back to the constructor when the subclass builds its message from constructor state" do
        stub_const("StatefulMessageError", Class.new(StandardError) do
          def initialize(detail)
            @detail = detail
            super("stateful: #{detail}")
          end

          def message
            "stateful: #{@detail.upcase}"
          end
        end)
        data = { class_name: "StatefulMessageError", message: "boom", backtrace: [] }

        expect { described_class.new.perform(data, context) }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
        log = RailsErrorDashboard::ErrorLog.last
        expect(log.error_type).to eq("StatefulMessageError")
        expect(log.message).to eq("stateful: BOOM")
      end
    end

    it "preserves context data" do
      described_class.new.perform(exception_data, context)
      error_log = RailsErrorDashboard::ErrorLog.last

      expect(error_log.user_id).to eq(1)
      expect(error_log.platform).to eq("API")
    end

    context "with different exception types" do
      it "handles ArgumentError" do
        data = exception_data.merge(class_name: "ArgumentError")

        described_class.new.perform(data, context)
        error_log = RailsErrorDashboard::ErrorLog.last

        expect(error_log.error_type).to eq("ArgumentError")
      end

      it "handles SecurityError" do
        data = exception_data.merge(class_name: "SecurityError")

        described_class.new.perform(data, context)
        error_log = RailsErrorDashboard::ErrorLog.last

        expect(error_log.error_type).to eq("SecurityError")
        expect(error_log.critical?).to be true
      end
    end

    context "when exception class doesn't exist" do
      it "falls back to StandardError" do
        data = exception_data.merge(class_name: "NonExistentError")

        described_class.new.perform(data, context)
        error_log = RailsErrorDashboard::ErrorLog.last

        expect(error_log.error_type).to eq("StandardError")
      end

      it "still logs the original message" do
        data = exception_data.merge(
          class_name: "NonExistentError",
          message: "Original error message"
        )

        described_class.new.perform(data, context)
        error_log = RailsErrorDashboard::ErrorLog.last

        expect(error_log.message).to eq("Original error message")
      end
    end

    context "when backtrace is nil" do
      it "handles missing backtrace gracefully" do
        data = exception_data.merge(backtrace: nil)

        expect {
          described_class.new.perform(data, context)
        }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
      end
    end

    context "when job execution fails" do
      it "logs the error and doesn't raise" do
        # Mock the instance method, not the class method
        allow_any_instance_of(RailsErrorDashboard::Commands::LogError).to receive(:call).and_raise("Job error")

        expect(Rails.logger).to receive(:error).with(/AsyncErrorLoggingJob failed/)
        expect(Rails.logger).to receive(:error).with(/Backtrace:/)

        expect {
          described_class.new.perform(exception_data, context)
        }.not_to raise_error
      end
    end
  end

  describe "queue" do
    it "is enqueued to default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end
end
