# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::AsyncErrorLoggingJob, type: :job do
  # A class that counts how often it is built, standing in for any loaded
  # class a reported type could name.
  let(:recording_class) do
    Class.new do
      class << self
        attr_accessor :instances
      end
      self.instances = 0

      def initialize(*)
        self.class.instances += 1
      end
    end
  end

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
      # The reconstructed OBJECT is still a StandardError -- allocating a class
      # that does not exist is impossible -- but the stored error_type keeps
      # the name that was reported. A frontend or mobile client reporting
      # "FrontendWidgetFailure" is the normal case for this path, and renaming
      # every one of them StandardError collapsed distinct client errors into
      # a single group.
      it "keeps the reported type rather than the fallback class" do
        data = exception_data.merge(class_name: "NonExistentError")

        described_class.new.perform(data, context)
        error_log = RailsErrorDashboard::ErrorLog.last

        expect(error_log.error_type).to eq("NonExistentError")
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

    # A client report's error_type is the CALLER's string: hosts take it from
    # their own frontend or mobile clients. The worker must never treat it as
    # the name of a class to look up or build.
    context "with a client report" do
      let(:client_context) { context.merge(_capture_source: "client") }

      it "never looks the reported type up as a constant (async-job-reconstruct/REQ-1)" do
        lookups = []
        stub_const("RedProbeNamespace", Module.new do
          define_singleton_method(:const_missing) do |name|
            lookups << name
            super(name)
          end
        end)
        data = exception_data.merge(class_name: "RedProbeNamespace::Widget")

        described_class.new.perform(data, client_context)

        expect(lookups).to be_empty
        expect(RailsErrorDashboard::ErrorLog.last.error_type).to eq("RedProbeNamespace::Widget")
      end

      it "builds no instance of a class the reported type happens to name (async-job-reconstruct/REQ-1)" do
        stub_const("RedProbeWidget", recording_class)
        data = exception_data.merge(class_name: "RedProbeWidget")

        described_class.new.perform(data, client_context)

        expect(RedProbeWidget.instances).to eq(0)
        expect(RailsErrorDashboard::ErrorLog.last.error_type).to eq("RedProbeWidget")
      end

      it "hands LogError a SyntheticException even when the type names a real exception (async-job-reconstruct/REQ-1)" do
        expect(RailsErrorDashboard::Commands::LogError).to receive(:new)
          .with(an_instance_of(RailsErrorDashboard::ManualErrorReporter::SyntheticException), anything, worker: true)
          .and_call_original

        described_class.new.perform(exception_data.merge(class_name: "ArgumentError"), client_context)

        log = RailsErrorDashboard::ErrorLog.last
        expect(log.error_type).to eq("ArgumentError")
        expect(log.message).to eq("Test async error")
        expect(log.backtrace).to include("app/controllers/test_controller.rb:10:in `index'")
      end
    end

    # Payloads enqueued before 0.16.0 carry no capture-source marker, so a
    # client report from one of them arrives here looking like a server
    # exception. Only an Exception subclass may be built on this path.
    context "with a payload that has no capture-source marker" do
      it "builds no instance of a class that is not an exception (async-job-reconstruct/REQ-2, REQ-5)" do
        stub_const("RedProbeWidget", recording_class)
        data = exception_data.merge(class_name: "RedProbeWidget")

        expect { described_class.new.perform(data, context) }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
        expect(RedProbeWidget.instances).to eq(0)
        expect(RailsErrorDashboard::ErrorLog.last.error_type).to eq("RedProbeWidget")
      end

      it "stores a module or a plain constant as reported (async-job-reconstruct/REQ-2)" do
        stub_const("RedProbeModule", Module.new)
        stub_const("RED_PROBE_VALUE", "not a class")

        # Distinct messages: these hand-built payloads carry no _identity, so
        # the worker hashes the rebuilt StandardError and would group the two.
        expect {
          described_class.new.perform(exception_data.merge(class_name: "RedProbeModule", message: "a module"), context)
          described_class.new.perform(exception_data.merge(class_name: "RED_PROBE_VALUE", message: "a value"), context)
        }.to change(RailsErrorDashboard::ErrorLog, :count).by(2)
        expect(RailsErrorDashboard::ErrorLog.pluck(:error_type)).to contain_exactly("RedProbeModule", "RED_PROBE_VALUE")
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

    context "when the payload cannot be processed" do
      # A bad payload fails identically on every attempt, so retrying just
      # replays it three times before discarding. Swallow and log.
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

    context "when the error store is unreachable" do
      # The opposite contract: nothing was written, so the job did NOT deliver
      # this capture. Acknowledging it discards the payload for good. Fail, so
      # retry_on schedules another attempt.
      before do
        allow(RailsErrorDashboard::ErrorLog).to receive(:transaction)
          .and_raise(ActiveRecord::ConnectionNotEstablished, "db down")
      end

      # Two layers, asserted separately on purpose: #perform is where the
      # failure is raised, and perform_now is where retry_on catches it and
      # schedules another attempt.
      it "raises out of #perform rather than reporting a delivery it never made" do
        expect {
          described_class.new.perform(exception_data, context)
        }.to raise_error(ActiveRecord::ConnectionNotEstablished)
      end

      it "schedules a retry rather than acknowledging the capture" do
        expect {
          described_class.perform_now(exception_data, context)
        }.to change { described_class.queue_adapter.enqueued_jobs.count { |j| j[:job] == described_class } }.by(1)
      end

      it "writes no error log" do
        expect {
          begin
            described_class.new.perform(exception_data, context)
          rescue ActiveRecord::ConnectionNotEstablished
            nil
          end
        }.not_to change(RailsErrorDashboard::ErrorLog, :count)
      end

      it "says why it is failing rather than dropping the capture silently" do
        expect(Rails.logger).to receive(:error).with(/error storage unavailable/).at_least(:once)
        allow(Rails.logger).to receive(:error)

        begin
          described_class.new.perform(exception_data, context)
        rescue ActiveRecord::ConnectionNotEstablished
          nil
        end
      end
    end
  end

  # The same report through ManualErrorReporter, once sync and once through
  # the queue, must be the same capture: one row, one hash, the same fields.
  describe "a client report through the queue" do
    let(:report) do
      { error_type: "RedProbeWidget", message: "widget failed",
        backtrace: [ "at handleClick (app.js:42)", "at onClick (button.js:15)" ], platform: "Web" }
    end

    before do
      stub_const("RedProbeWidget", recording_class)
      RailsErrorDashboard.reset_configuration!
      RailsErrorDashboard.configuration.sampling_rate = 1.0
      RailsErrorDashboard.configuration.enable_storm_protection = false
      allow(RailsErrorDashboard::Services::ErrorBroadcaster).to receive(:available?).and_return(false)
    end

    after { RailsErrorDashboard.reset_configuration! }

    it "stores what the sync path stores, on the same row (async-job-reconstruct/REQ-3)" do
      RailsErrorDashboard.configuration.async_logging = false
      sync_row = RailsErrorDashboard::ManualErrorReporter.report(**report)

      RailsErrorDashboard.configuration.async_logging = true
      RailsErrorDashboard::ManualErrorReporter.report(**report)
      perform_enqueued_jobs

      row = RailsErrorDashboard::ErrorLog.sole
      expect(row.id).to eq(sync_row.id)
      expect(row.error_hash).to eq(sync_row.error_hash)
      expect(row.occurrence_count).to eq(2)
      expect(row.error_type).to eq("RedProbeWidget")
      expect(row.message).to eq("widget failed")
      expect(row.backtrace).to eq(sync_row.backtrace)
      expect(row.backtrace_source).to eq("client")
      expect(RedProbeWidget.instances).to eq(0)
    end
  end

  describe "queue" do
    it "is enqueued to default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end
end
