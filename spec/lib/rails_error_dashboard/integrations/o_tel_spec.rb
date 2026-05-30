# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Integrations::OTel do
  before { described_class.reset! }
  after { described_class.reset! }

  describe ".available?" do
    context "when OpenTelemetry is not defined" do
      it "returns false" do
        hide_const("OpenTelemetry") if defined?(OpenTelemetry)
        expect(described_class.available?).to be false
      end
    end

    context "when OpenTelemetry is defined but OpenTelemetry::SDK is not" do
      it "returns false" do
        stub_const("OpenTelemetry", Module.new)
        expect(described_class.available?).to be false
      end
    end

    context "when OpenTelemetry::SDK is defined but SpanProcessor base class is not" do
      it "returns false" do
        otel = Module.new
        sdk = Module.new
        otel.const_set(:SDK, sdk)
        # Intentionally omit Trace::SpanProcessor — represents a half-loaded SDK
        stub_const("OpenTelemetry", otel)

        expect(described_class.available?).to be false
      end
    end

    context "when OpenTelemetry SDK and SpanProcessor are fully loaded" do
      it "returns true" do
        otel = Module.new
        sdk = Module.new
        trace = Module.new
        span_processor = Class.new
        trace.const_set(:SpanProcessor, span_processor)
        sdk.const_set(:Trace, trace)
        otel.const_set(:SDK, sdk)
        stub_const("OpenTelemetry", otel)

        expect(described_class.available?).to be true
      end
    end

    context "when constant lookup raises an unexpected error" do
      it "rescues to false rather than blowing up the host app" do
        allow(described_class).to receive(:send).and_call_original
        # Force the internal detect path to raise — guards the rescue clause
        allow(described_class).to receive(:send).with(:detect).and_raise(StandardError, "boom")

        expect(described_class.available?).to be false
      end
    end

    describe "memoization" do
      it "caches the result across calls (does not re-check constants)" do
        otel = Module.new
        sdk = Module.new
        trace = Module.new
        trace.const_set(:SpanProcessor, Class.new)
        sdk.const_set(:Trace, trace)
        otel.const_set(:SDK, sdk)
        stub_const("OpenTelemetry", otel)

        expect(described_class.available?).to be true

        # Hide the constant — memoized result should still be true
        hide_const("OpenTelemetry")
        expect(described_class.available?).to be true
      end

      it "memoizes a negative result too" do
        hide_const("OpenTelemetry") if defined?(OpenTelemetry)
        expect(described_class.available?).to be false

        # Even if OTel becomes available, the cached false stays until reset!
        otel = Module.new
        sdk = Module.new
        trace = Module.new
        trace.const_set(:SpanProcessor, Class.new)
        sdk.const_set(:Trace, trace)
        otel.const_set(:SDK, sdk)
        stub_const("OpenTelemetry", otel)

        expect(described_class.available?).to be false
      end
    end
  end

  describe ".reset!" do
    it "clears the memoized result" do
      hide_const("OpenTelemetry") if defined?(OpenTelemetry)
      expect(described_class.available?).to be false

      described_class.reset!

      otel = Module.new
      sdk = Module.new
      trace = Module.new
      trace.const_set(:SpanProcessor, Class.new)
      sdk.const_set(:Trace, trace)
      otel.const_set(:SDK, sdk)
      stub_const("OpenTelemetry", otel)

      expect(described_class.available?).to be true
    end
  end
end
