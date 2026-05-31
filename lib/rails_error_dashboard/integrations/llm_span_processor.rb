# frozen_string_literal: true

module RailsErrorDashboard
  module Integrations
    # OpenTelemetry SpanProcessor that maps GenAI semantic-convention spans
    # into LLM breadcrumbs. Registered with `OpenTelemetry.tracer_provider`
    # when the host app already runs OTel (ruby_llm, thoughtbot/instrumentation,
    # etc. all emit GenAI spans automatically).
    #
    # IMPORTANT — does NOT subclass ::OpenTelemetry::SDK::Trace::SpanProcessor.
    # That would NameError at file-load time on hosts without the SDK. Ruby's
    # OTel SDK accepts any duck-typed processor — name + arity is the contract.
    #
    # Reads attribute keys per the GenAI semconv (current + deprecated aliases).
    # Spec: https://opentelemetry.io/docs/specs/semconv/gen-ai/
    #
    # HOST APP SAFETY:
    # - on_finish wraps the entire body in rescue StandardError => nil
    # - No work happens unless enable_llm_observability AND enable_breadcrumbs
    # - Non-GenAI spans return immediately (cheapest possible path)
    # - Never raises, never blocks the tracer pipeline
    class LlmSpanProcessor
      class << self
        # Idempotently register a single shared LlmSpanProcessor instance with
        # the host's OpenTelemetry tracer provider. Called from Engine
        # `after_initialize` when `enable_llm_observability` is on.
        #
        # Returns false (and does nothing) when:
        # - OTel SDK isn't loaded (`Integrations::OTel.available?` is false)
        # - `enable_llm_observability` is off
        # - The active tracer provider is the default `ProxyTracerProvider`
        #   (SDK loaded but `OpenTelemetry::SDK.configure` never called) —
        #   detected by absence of `add_span_processor`
        # - Already registered in this process (Spring reload safety)
        # - `add_span_processor` raises (host app safety — never crash boot)
        #
        # @return [Boolean] true if a processor was newly registered, false otherwise
        def register!
          return false if @registered
          return false unless RailsErrorDashboard.configuration.enable_llm_observability
          return false unless OTel.available?

          provider = ::OpenTelemetry.tracer_provider
          return false unless provider.respond_to?(:add_span_processor)

          provider.add_span_processor(new)
          @registered = true
          true
        rescue StandardError => e
          RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] LlmSpanProcessor.register! failed: #{e.message}")
          false
        end

        # Test hook — clear the registered flag so re-registration is possible
        # in a fresh spec example. Does NOT remove the processor from the
        # tracer provider (OTel SDK offers no symmetric `remove_span_processor`).
        def reset!
          @registered = false
        end

        # @return [Boolean]
        def registered?
          @registered == true
        end
      end

      # Attribute keys — current GenAI semconv, with deprecated aliases.
      PROVIDER_KEYS   = [ "gen_ai.provider.name", "gen_ai.system" ].freeze
      MODEL_KEYS      = [ "gen_ai.response.model", "gen_ai.request.model" ].freeze
      INPUT_TOKEN_KEYS  = [ "gen_ai.usage.input_tokens", "gen_ai.usage.prompt_tokens" ].freeze
      OUTPUT_TOKEN_KEYS = [ "gen_ai.usage.output_tokens", "gen_ai.usage.completion_tokens" ].freeze
      TOOL_NAME_KEY     = "gen_ai.tool.name"
      OPERATION_KEY     = "gen_ai.operation.name"
      ERROR_TYPE_KEY    = "error.type"

      # Required SpanProcessor interface — no-op. We only act when the span
      # is fully populated (attributes/timestamps/status), which is on_finish.
      def on_start(_span, _parent_context)
        nil
      end

      # Required SpanProcessor interface. Must never raise.
      def on_finish(span)
        return unless RailsErrorDashboard.configuration.enable_llm_observability
        return unless RailsErrorDashboard.configuration.enable_breadcrumbs

        attrs = safe_attributes(span)
        return if attrs.empty?
        return unless gen_ai_span?(attrs)

        event   = build_event(span, attrs)
        category = event.tool_call? ? "llm_tool" : "llm"

        Services::BreadcrumbCollector.add(
          category,
          event.to_breadcrumb_message,
          duration_ms: event.duration_ms,
          metadata: event.to_breadcrumb_metadata
        )
      rescue StandardError => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] LlmSpanProcessor.on_finish failed: #{e.message}")
        nil
      end

      # OTel SDK Export::SUCCESS == 0. Hardcoded so this file loads without OTel.
      def force_flush(timeout: nil)
        0
      end

      def shutdown(timeout: nil)
        0
      end

      private

      def safe_attributes(span)
        attrs = span.attributes
        attrs.is_a?(Hash) ? attrs : {}
      rescue StandardError
        {}
      end

      # Cheap pre-filter — only inspect spans that actually carry GenAI semconv.
      def gen_ai_span?(attrs)
        PROVIDER_KEYS.any? { |k| attrs.key?(k) } ||
          MODEL_KEYS.any? { |k| attrs.key?(k) } ||
          attrs.key?(OPERATION_KEY) ||
          attrs.key?(TOOL_NAME_KEY)
      end

      def build_event(span, attrs)
        provider      = first_attr(attrs, PROVIDER_KEYS)
        model         = first_attr(attrs, MODEL_KEYS)
        input_tokens  = first_attr(attrs, INPUT_TOKEN_KEYS)
        output_tokens = first_attr(attrs, OUTPUT_TOKEN_KEYS)
        tool_name     = attrs[TOOL_NAME_KEY] || (attrs[OPERATION_KEY] == "execute_tool" ? attrs[OPERATION_KEY] : nil)
        error_type    = attrs[ERROR_TYPE_KEY]

        status = error_type ? :error : :success
        duration_ms = compute_duration_ms(span)

        cost = nil
        if status == :success && tool_name.nil? && model
          cost = Services::LlmCostEstimator.estimate(
            provider: provider,
            model: model,
            input_tokens: input_tokens,
            output_tokens: output_tokens
          )
        end

        ValueObjects::LlmCallEvent.new(
          provider: provider || "unknown",
          model: model || "unknown",
          status: status,
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          duration_ms: duration_ms,
          error_class: error_type,
          tool_name: tool_name,
          cost_usd_estimate: cost
        )
      end

      def first_attr(attrs, keys)
        keys.each { |k| return attrs[k] if attrs.key?(k) }
        nil
      end

      # OTel timestamps are nanoseconds since epoch. Convert to ms; guard nils.
      def compute_duration_ms(span)
        start_ns = span.start_timestamp
        end_ns   = span.end_timestamp
        return nil unless start_ns && end_ns
        ((end_ns - start_ns) / 1_000_000.0).round(2)
      rescue StandardError
        nil
      end
    end
  end
end
