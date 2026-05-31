# frozen_string_literal: true

require "rails_helper"

# Verifies the OTel outbound wiring in Commands::LogError. The Tracer façade
# itself is exhaustively unit-tested in
# spec/lib/rails_error_dashboard/integrations/tracer_spec.rb — these specs
# focus on the integration: does LogError emit the parent capture span with
# the right attributes, in both sync and async paths?
RSpec.describe "Commands::LogError OTel instrumentation" do
  # Fake span — records every attribute set on it so we can assert later.
  class LogErrorOtelFakeSpan
    attr_reader :attributes, :recorded_exceptions

    def initialize(attributes: {})
      @attributes = attributes.dup
      @recorded_exceptions = []
      @status = nil
    end

    def set_attribute(key, value)
      @attributes[key] = value
      self
    end

    def add_event(_name, attributes: nil); self; end

    def record_exception(exception, attributes: nil)
      @recorded_exceptions << exception
      self
    end

    attr_accessor :status

    def context; nil; end
    def finish; self; end
  end

  class LogErrorOtelFakeTracer
    attr_reader :spans

    def initialize
      @spans = []
    end

    def in_span(name, attributes: {})
      span = LogErrorOtelFakeSpan.new(attributes: attributes)
      @spans << { name: name, span: span }
      yield span
    end
  end

  class LogErrorOtelFakeProvider
    def initialize(tracer); @tracer = tracer; end
    def tracer(_name, _version = nil); @tracer; end
  end

  let(:tracer) { LogErrorOtelFakeTracer.new }
  let(:exception) do
    begin
      raise StandardError, "boom — capture me"
    rescue => e
      e
    end
  end

  def install_otel(tracer:)
    provider = LogErrorOtelFakeProvider.new(tracer)
    otel_module = Module.new
    otel_module.define_singleton_method(:tracer_provider) { provider }
    stub_const("OpenTelemetry", otel_module)

    status_class = Class.new do
      def self.error(message); new(:error, message); end
      attr_reader :code, :message
      def initialize(code, message); @code = code; @message = message; end
    end
    trace = Module.new
    trace.const_set(:Status, status_class)
    otel_module.const_set(:Trace, trace)
  end

  before do
    RailsErrorDashboard::Integrations::Tracer.reset!
    RailsErrorDashboard.configure do |c|
      c.async_logging = false
      c.enable_otel_export = true
      c.otel_spans = %i[capture breadcrumbs health notifications]
      c.application_name = "test-app"
    end
    install_otel(tracer: tracer)
  end

  after do
    RailsErrorDashboard::Integrations::Tracer.reset!
    RailsErrorDashboard.reset_configuration!
  end

  describe "sync path" do
    it "emits exactly one rails_error_dashboard.capture_error span" do
      RailsErrorDashboard::Commands::LogError.call(exception, {})
      capture_spans = tracer.spans.select { |s| s[:name] == "rails_error_dashboard.capture_error" }
      expect(capture_spans.size).to eq(1)
    end

    it "tags the span with error.type and (truncated) error.message" do
      RailsErrorDashboard::Commands::LogError.call(exception, {})
      span = tracer.spans.first[:span]
      expect(span.attributes["error.type"]).to eq("StandardError")
      expect(span.attributes["error.message"]).to start_with("boom — capture me")
    end

    it "truncates error.message to 200 chars" do
      long = StandardError.new("x" * 500)
      RailsErrorDashboard::Commands::LogError.call(long, {})
      span = tracer.spans.first[:span]
      expect(span.attributes["error.message"].length).to be <= 201  # 200 + the … ellipsis
    end

    it "marks the span as not-async" do
      RailsErrorDashboard::Commands::LogError.call(exception, {})
      span = tracer.spans.first[:span]
      expect(span.attributes["rails_error_dashboard.was_async"]).to eq(false)
    end

    it "tags the span with environment" do
      RailsErrorDashboard::Commands::LogError.call(exception, {})
      span = tracer.spans.first[:span]
      expect(span.attributes["rails_error_dashboard.environment"]).to eq(Rails.env.to_s)
    end

    it "tags the span with the application name after find_or_create_application" do
      RailsErrorDashboard::Commands::LogError.call(exception, {})
      span = tracer.spans.first[:span]
      expect(span.attributes["rails_error_dashboard.application"]).to be_a(String)
      expect(span.attributes["rails_error_dashboard.application"]).not_to be_empty
    end

    it "tags the span with the error_id after the record is persisted" do
      result = RailsErrorDashboard::Commands::LogError.call(exception, {})
      span = tracer.spans.first[:span]
      expect(span.attributes["rails_error_dashboard.error_id"]).to eq(result.id)
    end

    it "tags deduplicated=false on first occurrence" do
      RailsErrorDashboard::Commands::LogError.call(exception, {})
      span = tracer.spans.first[:span]
      expect(span.attributes["rails_error_dashboard.deduplicated"]).to eq(false)
    end

    it "tags deduplicated=true on a repeat occurrence" do
      RailsErrorDashboard::Commands::LogError.call(exception, {})
      tracer.spans.clear
      RailsErrorDashboard::Commands::LogError.call(exception, {})
      span = tracer.spans.first[:span]
      expect(span.attributes["rails_error_dashboard.deduplicated"]).to eq(true)
    end

    it "sets the base attributes (version + service_name) on every span" do
      RailsErrorDashboard::Commands::LogError.call(exception, {})
      span = tracer.spans.first[:span]
      expect(span.attributes["rails_error_dashboard.version"]).to eq(RailsErrorDashboard::VERSION)
      expect(span.attributes["rails_error_dashboard.service_name"]).to eq("test-app")
    end

    it "tags filtered=true when ExceptionFilter rejects the exception" do
      allow(RailsErrorDashboard::Services::ExceptionFilter).to receive(:should_log?).and_return(false)
      RailsErrorDashboard::Commands::LogError.call(exception, {})
      span = tracer.spans.first[:span]
      expect(span.attributes["rails_error_dashboard.filtered"]).to eq(true)
    end

    it "does NOT emit a span when enable_otel_export is false" do
      RailsErrorDashboard.configuration.enable_otel_export = false
      RailsErrorDashboard::Commands::LogError.call(exception, {})
      expect(tracer.spans).to be_empty
    end

    it "does NOT emit a span when :capture is not in otel_spans" do
      RailsErrorDashboard.configuration.otel_spans = %i[breadcrumbs health]
      RailsErrorDashboard::Commands::LogError.call(exception, {})
      expect(tracer.spans).to be_empty
    end

    it "still creates the error log when OTel is off (transparent instrumentation)" do
      RailsErrorDashboard.configuration.enable_otel_export = false
      expect {
        RailsErrorDashboard::Commands::LogError.call(exception, {})
      }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
    end

    it "swallows host-app-safety: a tracer error never propagates" do
      allow(tracer).to receive(:in_span).and_raise(StandardError, "tracer broken")
      expect {
        RailsErrorDashboard::Commands::LogError.call(exception, {})
      }.not_to raise_error
    end
  end

  describe "async path" do
    before do
      RailsErrorDashboard.configuration.async_logging = true
    end

    it "emits a capture_error span around the enqueue with was_async=true" do
      # Stub the job so the test doesn't actually enqueue to a real adapter
      allow(RailsErrorDashboard::AsyncErrorLoggingJob).to receive(:perform_later)

      RailsErrorDashboard::Commands::LogError.call(exception, {})

      capture_spans = tracer.spans.select { |s| s[:name] == "rails_error_dashboard.capture_error" }
      expect(capture_spans.size).to eq(1)
      span = capture_spans.first[:span]
      expect(span.attributes["rails_error_dashboard.was_async"]).to eq(true)
      expect(span.attributes["error.type"]).to eq("StandardError")
    end
  end
end
