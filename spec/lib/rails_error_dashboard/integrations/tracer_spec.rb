# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Integrations::Tracer do
  # Fake span double mimicking ::OpenTelemetry::Trace::Span — supports
  # the subset of the interface our façade touches (set_attribute,
  # add_event, record_exception, status=).
  class TracerFakeSpan
    attr_reader :attributes, :events, :recorded_exceptions, :status

    def initialize(attributes: {})
      @attributes = attributes.dup
      @events = []
      @recorded_exceptions = []
      @status = nil
    end

    def set_attribute(key, value)
      @attributes[key] = value
      self
    end

    def add_event(name, attributes: nil)
      @events << { name: name, attributes: attributes }
      self
    end

    def record_exception(exception, attributes: nil)
      @recorded_exceptions << { exception: exception, attributes: attributes }
      self
    end

    def status=(s)
      @status = s
    end

    def context; nil; end
    def finish; self; end
  end

  # Fake tracer — yields a TracerFakeSpan to the block, captures the call args.
  class TracerFakeTracer
    attr_reader :spans_created

    def initialize
      @spans_created = []
    end

    def in_span(name, attributes: {})
      span = TracerFakeSpan.new(attributes: attributes)
      @spans_created << { name: name, attributes: attributes, span: span }
      yield span
    end
  end

  # Fake tracer provider — returns the same fake tracer for every .tracer call.
  class TracerFakeProvider
    attr_reader :tracer_calls, :fake_tracer

    def initialize(fake_tracer)
      @fake_tracer = fake_tracer
      @tracer_calls = []
    end

    def tracer(name, version = nil)
      @tracer_calls << { name: name, version: version }
      @fake_tracer
    end
  end

  # Hand-rolled minimal OTel namespace — stub_const lets us swap it per example.
  def install_otel(tracer:)
    provider = TracerFakeProvider.new(tracer)
    otel_module = Module.new
    otel_module.define_singleton_method(:tracer_provider) { provider }
    stub_const("OpenTelemetry", otel_module)

    # Also wire up Trace::Status — the façade uses it to set error status.
    status_class = Class.new do
      def self.error(message)
        new(:error, message)
      end

      attr_reader :code, :message
      def initialize(code, message)
        @code = code
        @message = message
      end
    end
    trace = Module.new
    trace.const_set(:Status, status_class)
    otel_module.const_set(:Trace, trace)

    provider
  end

  before do
    described_class.reset!
    RailsErrorDashboard.configuration.enable_otel_export = false
    RailsErrorDashboard.configuration.otel_spans = %i[capture breadcrumbs health notifications]
    RailsErrorDashboard.configuration.otel_service_name = nil
    RailsErrorDashboard.configuration.application_name = "test-app"
  end

  after do
    described_class.reset!
    RailsErrorDashboard.reset_configuration!
  end

  describe ".in_span — block return value" do
    it "returns the block's value when tracing is off" do
      result = described_class.in_span("foo", kind: :capture) { 42 }
      expect(result).to eq(42)
    end

    it "returns the block's value when tracing is on" do
      RailsErrorDashboard.configuration.enable_otel_export = true
      install_otel(tracer: TracerFakeTracer.new)
      result = described_class.in_span("foo", kind: :capture) { 99 }
      expect(result).to eq(99)
    end
  end

  describe ".in_span — no-op behavior" do
    it "yields a NoopSpan when enable_otel_export is false" do
      RailsErrorDashboard.configuration.enable_otel_export = false
      yielded = nil
      described_class.in_span("foo", kind: :capture) { |s| yielded = s }
      expect(yielded).to be_a(described_class::NoopSpan)
    end

    it "yields a NoopSpan when OTel API is not loaded" do
      hide_const("OpenTelemetry") if defined?(OpenTelemetry)
      RailsErrorDashboard.configuration.enable_otel_export = true
      yielded = nil
      described_class.in_span("foo", kind: :capture) { |s| yielded = s }
      expect(yielded).to be_a(described_class::NoopSpan)
    end

    it "yields a NoopSpan when the requested kind is not in otel_spans" do
      RailsErrorDashboard.configuration.enable_otel_export = true
      RailsErrorDashboard.configuration.otel_spans = %i[capture]
      install_otel(tracer: TracerFakeTracer.new)
      yielded = nil
      described_class.in_span("foo", kind: :notifications) { |s| yielded = s }
      expect(yielded).to be_a(described_class::NoopSpan)
    end

    it "yields a NoopSpan when otel_spans is empty" do
      RailsErrorDashboard.configuration.enable_otel_export = true
      RailsErrorDashboard.configuration.otel_spans = []
      install_otel(tracer: TracerFakeTracer.new)
      yielded = nil
      described_class.in_span("foo", kind: :capture) { |s| yielded = s }
      expect(yielded).to be_a(described_class::NoopSpan)
    end

    it "yields a NoopSpan when otel_spans is nil" do
      RailsErrorDashboard.configuration.enable_otel_export = true
      RailsErrorDashboard.configuration.otel_spans = nil
      install_otel(tracer: TracerFakeTracer.new)
      yielded = nil
      described_class.in_span("foo", kind: :capture) { |s| yielded = s }
      expect(yielded).to be_a(described_class::NoopSpan)
    end

    it "NoopSpan responds to set_attribute, add_event, record_exception without raising" do
      noop = described_class::NOOP_SPAN
      expect { noop.set_attribute("k", "v") }.not_to raise_error
      expect { noop.add_event("evt") }.not_to raise_error
      expect { noop.record_exception(StandardError.new("x")) }.not_to raise_error
      expect { noop.status = :error }.not_to raise_error
    end
  end

  describe ".in_span — when fully enabled" do
    before do
      RailsErrorDashboard.configuration.enable_otel_export = true
    end

    it "creates a span namespaced under rails_error_dashboard.*" do
      tr = TracerFakeTracer.new
      install_otel(tracer: tr)
      described_class.in_span("capture_error", kind: :capture) { nil }
      expect(tr.spans_created.first[:name]).to eq("rails_error_dashboard.capture_error")
    end

    it "merges base attributes (version, service name) into the span" do
      tr = TracerFakeTracer.new
      install_otel(tracer: tr)
      described_class.in_span("capture_error", kind: :capture, attributes: { "error_type" => "NoMethodError" }) { nil }

      attrs = tr.spans_created.first[:attributes]
      expect(attrs["rails_error_dashboard.version"]).to eq(RailsErrorDashboard::VERSION)
      expect(attrs["rails_error_dashboard.service_name"]).to eq("test-app")
      expect(attrs["error_type"]).to eq("NoMethodError")
    end

    it "prefers otel_service_name over application_name when both set" do
      RailsErrorDashboard.configuration.otel_service_name = "my-otel-service"
      tr = TracerFakeTracer.new
      install_otel(tracer: tr)
      described_class.in_span("foo", kind: :capture) { nil }
      expect(tr.spans_created.first[:attributes]["rails_error_dashboard.service_name"]).to eq("my-otel-service")
    end

    it "falls back to 'unknown' when neither service name nor application name set" do
      RailsErrorDashboard.configuration.otel_service_name = nil
      RailsErrorDashboard.configuration.application_name = nil
      tr = TracerFakeTracer.new
      install_otel(tracer: tr)
      described_class.in_span("foo", kind: :capture) { nil }
      expect(tr.spans_created.first[:attributes]["rails_error_dashboard.service_name"]).to eq("unknown")
    end

    it "coerces symbol attribute values to strings (OTel only accepts primitives)" do
      tr = TracerFakeTracer.new
      install_otel(tracer: tr)
      described_class.in_span("foo", kind: :capture, attributes: { "severity" => :critical }) { nil }
      expect(tr.spans_created.first[:attributes]["severity"]).to eq("critical")
    end

    it "preserves primitive attribute values (string, int, bool)" do
      tr = TracerFakeTracer.new
      install_otel(tracer: tr)
      described_class.in_span("foo", kind: :capture, attributes: {
        "s" => "abc", "i" => 42, "b" => true, "f" => 1.5
      }) { nil }
      attrs = tr.spans_created.first[:attributes]
      expect(attrs["s"]).to eq("abc")
      expect(attrs["i"]).to eq(42)
      expect(attrs["b"]).to be true
      expect(attrs["f"]).to eq(1.5)
    end

    it "drops nil attribute values" do
      tr = TracerFakeTracer.new
      install_otel(tracer: tr)
      described_class.in_span("foo", kind: :capture, attributes: { "kept" => "x", "dropped" => nil }) { nil }
      attrs = tr.spans_created.first[:attributes]
      expect(attrs).to have_key("kept")
      expect(attrs).not_to have_key("dropped")
    end

    it "respects each of the four span kinds" do
      tr = TracerFakeTracer.new
      install_otel(tracer: tr)
      %i[capture breadcrumbs health notifications].each do |kind|
        described_class.in_span(kind.to_s, kind: kind) { nil }
      end
      expect(tr.spans_created.size).to eq(4)
    end
  end

  describe ".in_span — exception handling" do
    before do
      RailsErrorDashboard.configuration.enable_otel_export = true
    end

    it "records the exception on the span and re-raises" do
      tr = TracerFakeTracer.new
      install_otel(tracer: tr)
      expect {
        described_class.in_span("foo", kind: :capture) { raise StandardError, "boom" }
      }.to raise_error(StandardError, "boom")

      span = tr.spans_created.first[:span]
      expect(span.recorded_exceptions.first[:exception].message).to eq("boom")
    end

    it "sets span status to error with truncated message" do
      tr = TracerFakeTracer.new
      install_otel(tracer: tr)
      long_msg = "x" * 500
      expect {
        described_class.in_span("foo", kind: :capture) { raise StandardError, long_msg }
      }.to raise_error(StandardError)

      status = tr.spans_created.first[:span].status
      expect(status.code).to eq(:error)
      expect(status.message.length).to be <= 200
    end

    it "falls back to NoopSpan when tracer.in_span itself raises (host safety)" do
      tr = TracerFakeTracer.new
      install_otel(tracer: tr)
      allow(tr).to receive(:in_span).and_raise(StandardError, "tracer broken")
      yielded = nil
      result = described_class.in_span("foo", kind: :capture) { |s| yielded = s; 7 }
      expect(yielded).to be_a(described_class::NoopSpan)
      expect(result).to eq(7)
    end

    it "rescues errors from base_attributes (host safety)" do
      tr = TracerFakeTracer.new
      install_otel(tracer: tr)
      allow(RailsErrorDashboard).to receive(:configuration).and_raise(StandardError, "config broken")
      expect {
        described_class.in_span("foo", kind: :capture) { 1 }
      }.not_to raise_error
    end
  end

  describe ".otel_api_loaded?" do
    it "returns true when OpenTelemetry is defined with tracer_provider" do
      install_otel(tracer: TracerFakeTracer.new)
      expect(described_class.otel_api_loaded?).to be true
    end

    it "returns false when OpenTelemetry is not defined" do
      hide_const("OpenTelemetry") if defined?(OpenTelemetry)
      expect(described_class.otel_api_loaded?).to be false
    end

    it "returns false when OpenTelemetry has no tracer_provider method" do
      otel_module = Module.new
      stub_const("OpenTelemetry", otel_module)
      expect(described_class.otel_api_loaded?).to be false
    end

    it "memoizes — second call does not re-check constants" do
      install_otel(tracer: TracerFakeTracer.new)
      expect(described_class.otel_api_loaded?).to be true
      hide_const("OpenTelemetry")
      expect(described_class.otel_api_loaded?).to be true
    end
  end

  describe ".reset!" do
    it "clears the memoized tracer and otel_api_loaded flag" do
      install_otel(tracer: TracerFakeTracer.new)
      expect(described_class.otel_api_loaded?).to be true

      described_class.reset!

      hide_const("OpenTelemetry")
      expect(described_class.otel_api_loaded?).to be false
    end
  end

  describe ".emit?" do
    it "returns false when master switch is off" do
      RailsErrorDashboard.configuration.enable_otel_export = false
      install_otel(tracer: TracerFakeTracer.new)
      expect(described_class.emit?(:capture)).to be false
    end

    it "returns false when OTel API is not loaded" do
      hide_const("OpenTelemetry") if defined?(OpenTelemetry)
      RailsErrorDashboard.configuration.enable_otel_export = true
      expect(described_class.emit?(:capture)).to be false
    end

    it "returns true when master + API + kind all align" do
      RailsErrorDashboard.configuration.enable_otel_export = true
      RailsErrorDashboard.configuration.otel_spans = %i[capture]
      install_otel(tracer: TracerFakeTracer.new)
      expect(described_class.emit?(:capture)).to be true
      expect(described_class.emit?(:health)).to be false
    end

    it "rescues to false on unexpected error" do
      allow(RailsErrorDashboard).to receive(:configuration).and_raise(StandardError, "boom")
      expect(described_class.emit?(:capture)).to be false
    end
  end
end
