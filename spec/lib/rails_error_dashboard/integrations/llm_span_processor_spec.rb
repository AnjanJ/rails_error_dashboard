# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Integrations::LlmSpanProcessor do
  # Fake span double mimicking ::OpenTelemetry::SDK::Trace::Span — name,
  # attributes (Hash<String, Any>), start/end timestamps in nanoseconds.
  # We avoid loading the real SDK so this spec runs whether or not
  # opentelemetry-sdk is in the host's bundle.
  FakeSpan = Struct.new(:name, :attributes, :start_timestamp, :end_timestamp, keyword_init: true)

  subject(:processor) { described_class.new }

  let(:collector) { RailsErrorDashboard::Services::BreadcrumbCollector }

  before do
    collector.clear_buffer
    collector.init_buffer
    RailsErrorDashboard.configuration.enable_breadcrumbs = true
    RailsErrorDashboard.configuration.enable_llm_observability = true
    RailsErrorDashboard.configuration.breadcrumb_categories = nil
  end

  after do
    collector.clear_buffer
    RailsErrorDashboard.reset_configuration!
  end

  # 1_000_000 ns = 1 ms. Span from 0 → 421_500_000 ns = 421.5 ms.
  def chat_span(attrs, duration_ms: 421.5)
    FakeSpan.new(
      name: "chat anthropic claude-sonnet-4-6",
      attributes: attrs,
      start_timestamp: 0,
      end_timestamp: (duration_ms * 1_000_000).to_i
    )
  end

  describe "#on_start" do
    it "is a no-op and does not record a breadcrumb" do
      span = chat_span({ "gen_ai.provider.name" => "anthropic", "gen_ai.request.model" => "claude-sonnet-4-6" })
      expect { processor.on_start(span, nil) }.not_to change { collector.current_breadcrumbs.size }
    end
  end

  describe "#on_finish" do
    context "when enable_llm_observability is false" do
      before { RailsErrorDashboard.configuration.enable_llm_observability = false }

      it "does nothing" do
        span = chat_span({ "gen_ai.provider.name" => "anthropic", "gen_ai.request.model" => "claude-sonnet-4-6" })
        expect { processor.on_finish(span) }.not_to change { collector.current_breadcrumbs.size }
      end
    end

    context "when enable_breadcrumbs is false" do
      before { RailsErrorDashboard.configuration.enable_breadcrumbs = false }

      it "does nothing" do
        span = chat_span({ "gen_ai.provider.name" => "anthropic", "gen_ai.request.model" => "claude-sonnet-4-6" })
        expect { processor.on_finish(span) }.not_to change { collector.current_breadcrumbs.size }
      end
    end

    context "with a non-GenAI span" do
      it "skips it (no gen_ai.* attributes)" do
        span = chat_span({ "http.method" => "GET", "http.url" => "/api/users" })
        expect { processor.on_finish(span) }.not_to change { collector.current_breadcrumbs.size }
      end

      it "skips when attributes is nil/not a hash" do
        broken_span = FakeSpan.new(name: "x", attributes: nil, start_timestamp: 0, end_timestamp: 1_000_000)
        expect { processor.on_finish(broken_span) }.not_to raise_error
        expect(collector.current_breadcrumbs).to be_empty
      end
    end

    context "with a successful chat span using current semconv attributes" do
      let(:attrs) do
        {
          "gen_ai.provider.name"      => "anthropic",
          "gen_ai.request.model"      => "claude-sonnet-4-6",
          "gen_ai.usage.input_tokens" => 1200,
          "gen_ai.usage.output_tokens" => 350
        }
      end

      it "records an llm breadcrumb with provider, model, tokens, duration, and cost" do
        processor.on_finish(chat_span(attrs, duration_ms: 421.5))

        crumbs = collector.current_breadcrumbs
        expect(crumbs.size).to eq(1)

        crumb = crumbs.first
        expect(crumb[:c]).to eq("llm")
        expect(crumb[:m]).to include("anthropic", "claude-sonnet-4-6", "in:1200/out:350")
        expect(crumb[:d]).to eq(421.5)

        # BreadcrumbCollector stringifies all metadata values to keep the
        # JSON payload compact and JSON-safe (see #truncate_metadata). Numeric
        # typing is preserved upstream in LlmCallEvent — assert on string form here.
        meta = crumb[:meta]
        expect(meta[:provider]).to eq("anthropic")
        expect(meta[:model]).to eq("claude-sonnet-4-6")
        expect(meta[:status]).to eq("success")
        expect(meta[:input_tokens]).to eq("1200")
        expect(meta[:output_tokens]).to eq("350")
        expect(meta[:duration_ms]).to eq("421.5")
        # Cost: 1200 * 3.0 + 350 * 15.0 = 3600 + 5250 = 8850 / 1M = 0.00885
        expect(meta[:cost_usd]).to eq("0.00885")
      end

      it "prefers gen_ai.response.model over gen_ai.request.model when present" do
        attrs["gen_ai.response.model"] = "claude-sonnet-4-6-20260415"
        processor.on_finish(chat_span(attrs))

        meta = collector.current_breadcrumbs.first[:meta]
        expect(meta[:model]).to eq("claude-sonnet-4-6-20260415")
      end
    end

    context "with deprecated semconv attribute aliases" do
      it "maps gen_ai.system → provider and prompt/completion_tokens → input/output" do
        attrs = {
          "gen_ai.system"                  => "openai",
          "gen_ai.request.model"           => "gpt-4o-mini",
          "gen_ai.usage.prompt_tokens"     => 800,
          "gen_ai.usage.completion_tokens" => 200
        }
        processor.on_finish(chat_span(attrs))

        meta = collector.current_breadcrumbs.first[:meta]
        expect(meta[:provider]).to eq("openai")
        expect(meta[:input_tokens]).to eq("800")
        expect(meta[:output_tokens]).to eq("200")
      end
    end

    context "with a tool-call span" do
      it "uses the llm_tool category, sets tool_name, and skips cost estimation" do
        attrs = {
          "gen_ai.operation.name" => "execute_tool",
          "gen_ai.tool.name"      => "search_database",
          "gen_ai.provider.name"  => "anthropic"
        }
        processor.on_finish(chat_span(attrs, duration_ms: 38.2))

        crumb = collector.current_breadcrumbs.first
        expect(crumb[:c]).to eq("llm_tool")
        expect(crumb[:m]).to eq("tool: search_database")
        expect(crumb[:d]).to eq(38.2)

        meta = crumb[:meta]
        expect(meta[:tool_name]).to eq("search_database")
        expect(meta).not_to have_key(:cost_usd)
      end
    end

    context "with an error span" do
      it "marks status as error and pulls error_class from error.type" do
        attrs = {
          "gen_ai.provider.name" => "openai",
          "gen_ai.request.model" => "gpt-4o",
          "error.type"           => "openai.RateLimitError"
        }
        processor.on_finish(chat_span(attrs))

        meta = collector.current_breadcrumbs.first[:meta]
        expect(meta[:status]).to eq("error")
        expect(meta[:error_class]).to eq("openai.RateLimitError")
        # No cost estimate when the call failed
        expect(meta).not_to have_key(:cost_usd)
      end
    end

    context "with missing timestamps" do
      it "records the breadcrumb with nil duration rather than raising" do
        attrs = { "gen_ai.provider.name" => "anthropic", "gen_ai.request.model" => "claude-sonnet-4-6" }
        span = FakeSpan.new(name: "chat", attributes: attrs, start_timestamp: nil, end_timestamp: nil)

        expect { processor.on_finish(span) }.not_to raise_error
        crumb = collector.current_breadcrumbs.first
        expect(crumb).not_to be_nil
        expect(crumb[:d]).to be_nil
        expect(crumb[:meta]).not_to have_key(:duration_ms)
      end
    end

    context "host app safety" do
      it "rescues any internal exception and never raises" do
        bad_span = double("BadSpan")
        allow(bad_span).to receive(:attributes).and_raise(StandardError, "boom")

        expect { processor.on_finish(bad_span) }.not_to raise_error
      end
    end
  end

  describe "SpanProcessor interface contracts" do
    it "force_flush returns 0 (OTel Export::SUCCESS)" do
      expect(processor.force_flush).to eq(0)
      expect(processor.force_flush(timeout: 5)).to eq(0)
    end

    it "shutdown returns 0 (OTel Export::SUCCESS)" do
      expect(processor.shutdown).to eq(0)
      expect(processor.shutdown(timeout: 5)).to eq(0)
    end
  end

  describe ".register!" do
    # OTel singleton state is process-global. Reset both detection memoization
    # and our own registered-flag between examples.
    before do
      RailsErrorDashboard::Integrations::OTel.reset!
      described_class.reset!
    end

    after do
      RailsErrorDashboard::Integrations::OTel.reset!
      described_class.reset!
    end

    # Stub a tracer provider that supports add_span_processor — simulates a
    # fully-configured SDK (post-`OpenTelemetry::SDK.configure` call).
    def stub_configured_otel
      otel = Module.new
      sdk = Module.new
      trace = Module.new
      trace.const_set(:SpanProcessor, Class.new)
      sdk.const_set(:Trace, trace)
      otel.const_set(:SDK, sdk)

      tracer_provider = double("TracerProvider")
      allow(tracer_provider).to receive(:add_span_processor)
      otel.define_singleton_method(:tracer_provider) { tracer_provider }

      stub_const("OpenTelemetry", otel)
      tracer_provider
    end

    context "when OTel SDK is not available" do
      it "returns false and does not attempt registration" do
        hide_const("OpenTelemetry") if defined?(OpenTelemetry)
        expect(described_class.register!).to be false
        expect(described_class.registered?).to be false
      end
    end

    context "when enable_llm_observability is off" do
      it "returns false even with OTel fully available" do
        stub_configured_otel
        RailsErrorDashboard.configuration.enable_llm_observability = false

        expect(described_class.register!).to be false
        expect(described_class.registered?).to be false
      end
    end

    context "when the tracer provider is the no-op proxy (SDK loaded but not configured)" do
      it "returns false rather than NoMethodError on add_span_processor" do
        # Build OTel namespace with the SDK constants but with a proxy-style
        # tracer_provider that does NOT respond to add_span_processor.
        otel = Module.new
        sdk = Module.new
        trace = Module.new
        trace.const_set(:SpanProcessor, Class.new)
        sdk.const_set(:Trace, trace)
        otel.const_set(:SDK, sdk)

        proxy = Object.new # no add_span_processor method
        otel.define_singleton_method(:tracer_provider) { proxy }
        stub_const("OpenTelemetry", otel)

        expect(described_class.register!).to be false
        expect(described_class.registered?).to be false
      end
    end

    context "when OTel SDK is fully configured and observability is on" do
      it "registers an LlmSpanProcessor instance with the tracer provider and returns true" do
        tracer_provider = stub_configured_otel

        expect(tracer_provider).to receive(:add_span_processor).with(instance_of(described_class))
        expect(described_class.register!).to be true
        expect(described_class.registered?).to be true
      end

      it "is idempotent — a second call does not re-register" do
        tracer_provider = stub_configured_otel

        expect(tracer_provider).to receive(:add_span_processor).once
        described_class.register!
        described_class.register!
        expect(described_class.registered?).to be true
      end
    end

    context "host app safety" do
      it "rescues errors from add_span_processor and returns false" do
        tracer_provider = stub_configured_otel
        allow(tracer_provider).to receive(:add_span_processor).and_raise(StandardError, "boom")

        expect { described_class.register! }.not_to raise_error
        expect(described_class.register!).to be false
        expect(described_class.registered?).to be false
      end
    end
  end

  describe ".reset!" do
    it "clears the registered flag" do
      RailsErrorDashboard::Integrations::OTel.reset!
      described_class.reset!

      otel = Module.new
      sdk = Module.new
      trace = Module.new
      trace.const_set(:SpanProcessor, Class.new)
      sdk.const_set(:Trace, trace)
      otel.const_set(:SDK, sdk)
      tp = double("TracerProvider", add_span_processor: nil)
      otel.define_singleton_method(:tracer_provider) { tp }
      stub_const("OpenTelemetry", otel)

      described_class.register!
      expect(described_class.registered?).to be true

      described_class.reset!
      expect(described_class.registered?).to be false
    end
  end
end
