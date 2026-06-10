# frozen_string_literal: true

module RailsErrorDashboard
  module Integrations
    # OpenTelemetry tracer façade for the outbound direction — emits spans
    # from the gem's capture path so host operators can audit error tracking
    # latency from their existing Datadog/Honeycomb/Jaeger pipeline.
    #
    # Symmetric counterpart to LlmSpanProcessor (which is INBOUND — pulls
    # OTel spans INTO RED breadcrumbs). This module pushes OUTBOUND: gem
    # operations OUT to the host's tracer provider.
    #
    # Designed to be called from hot paths unconditionally. When OTel is
    # absent or the feature is off, `in_span` runs the block with a no-op
    # span object — call sites do NOT branch on availability.
    #
    # HOST APP SAFETY (HOST_APP_SAFETY.md):
    # - No-op when `enable_otel_export = false` OR OTel API not loaded
    # - Per-span-kind opt-in/out via config.otel_spans
    # - Tracer instance memoized per-process (rebuild on `reset!`)
    # - Every public method hard-rescues — never raises into host code
    # - Block return value is preserved even when tracer errors
    # - Exceptions raised by the block re-raise after being recorded
    #
    # Configuration:
    #   config.enable_otel_export = true     # master switch (default false)
    #   config.otel_service_name = "my-app"  # falls back to application_name
    #   config.otel_spans = [:capture, :breadcrumbs, :health, :notifications]
    #
    # Usage from capture-path code:
    #
    #   Tracer.in_span("capture_error", kind: :capture,
    #                  attributes: { error_type: exception.class.name }) do |span|
    #     # ... do the work ...
    #     span&.set_attribute("rails_error_dashboard.error_id", error.id)
    #   end
    #
    # The span object yielded may be the real OTel span or a NoopSpan.
    # Always use safe-nav (`span&.`) or guard with `span.respond_to?(:...)`.
    module Tracer
      INSTRUMENTATION_NAME = "rails_error_dashboard"
      ALL_SPAN_KINDS = %i[capture breadcrumbs health notifications].freeze

      # No-op stand-in returned to the block when tracing is off or unavailable.
      # Mimics the OTel Span interface (set_attribute, add_event, record_exception)
      # so call sites don't branch.
      class NoopSpan
        def set_attribute(_key, _value); self; end
        def add_event(_name, attributes: nil); self; end
        def record_exception(_exception, attributes: nil); self; end
        def status=(_status); end
        def finish; self; end
        def context; nil; end
      end

      NOOP_SPAN = NoopSpan.new.freeze

      class << self
        # Yields a span object to the block. Returns the block's return value.
        # Records exceptions raised by the block as span events and re-raises.
        #
        # @param name [String] short span name (will be namespaced with INSTRUMENTATION_NAME)
        # @param kind [Symbol] one of ALL_SPAN_KINDS — checked against config.otel_spans
        # @param attributes [Hash<String,Object>] attached to the span at creation
        # @yieldparam span [NoopSpan, ::OpenTelemetry::Trace::Span] real or no-op
        # @return [Object] whatever the block returns
        def in_span(name, kind: :capture, attributes: {})
          return yield(NOOP_SPAN) unless emit?(kind)

          tr = tracer
          return yield(NOOP_SPAN) unless tr

          full_name = "#{INSTRUMENTATION_NAME}.#{name}"
          merged = base_attributes.merge(safe_stringify(attributes))

          tr.in_span(full_name, attributes: merged) do |span|
            begin
              yield span
            rescue StandardError => e
              record_block_exception(span, e)
              raise
            end
          end
        rescue StandardError => e
          # Tracer internals failed (e.g. OTel SDK threw on add_span). Fall back
          # to running the block with a no-op so the host app never sees a crash
          # caused by the tracer.
          Logger.debug("[RailsErrorDashboard] Tracer.in_span(#{name.inspect}) failed: #{e.class}: #{e.message}")
          yield NOOP_SPAN
        end

        # Returns true when the OTel API is loaded AND the master switch is on
        # AND the given span kind is in the enabled set. Cheap — called on every
        # in_span invocation, including in the hot path.
        # @param kind [Symbol]
        # @return [Boolean]
        def emit?(kind)
          config = RailsErrorDashboard.configuration
          return false unless config.enable_otel_export
          return false unless otel_api_loaded?

          enabled_kinds = config.otel_spans
          return false if enabled_kinds.nil? || enabled_kinds.empty?
          enabled_kinds.include?(kind)
        rescue StandardError
          false
        end

        # Reset memoized tracer + availability — for spec isolation only.
        def reset!
          @tracer = nil
          @otel_api_loaded = nil
        end

        # Returns true if the OTel API gem is loaded (NOT the SDK). The API alone
        # is enough — it ships a ProxyTracerProvider that's a no-op when no SDK
        # is configured, which is the behavior we want.
        # @return [Boolean]
        def otel_api_loaded?
          return @otel_api_loaded unless @otel_api_loaded.nil?
          @otel_api_loaded = !!(defined?(::OpenTelemetry) &&
                                ::OpenTelemetry.respond_to?(:tracer_provider))
        rescue StandardError
          @otel_api_loaded = false
        end

        private

        # Memoized tracer instance. Returns nil on any failure so the caller
        # falls back to no-op behavior.
        # @return [::OpenTelemetry::Trace::Tracer, nil]
        def tracer
          return @tracer if @tracer
          return nil unless otel_api_loaded?

          @tracer = ::OpenTelemetry.tracer_provider.tracer(
            INSTRUMENTATION_NAME,
            RailsErrorDashboard::VERSION
          )
        rescue StandardError => e
          Logger.debug("[RailsErrorDashboard] Tracer initialization failed: #{e.class}: #{e.message}")
          nil
        end

        # Attributes attached to every span — service-name and gem version
        # let operators filter the gem's traffic out of their dashboards.
        def base_attributes
          config = RailsErrorDashboard.configuration
          {
            "rails_error_dashboard.version" => RailsErrorDashboard::VERSION,
            "rails_error_dashboard.service_name" => config.otel_service_name ||
                                                    config.application_name ||
                                                    "unknown"
          }
        rescue StandardError
          {}
        end

        # OTel attribute values must be strings, bools, numerics, or arrays of those.
        # Coerce hash values to strings as a safety net — host code passing arbitrary
        # objects (e.g. a Symbol or an Exception) won't crash the SDK.
        def safe_stringify(attrs)
          return {} unless attrs.is_a?(Hash)
          attrs.each_with_object({}) do |(k, v), acc|
            key = k.to_s
            acc[key] = case v
            when String, Numeric, TrueClass, FalseClass then v
            when Array
              v.map { |x| x.is_a?(String) || x.is_a?(Numeric) || x == true || x == false ? x : x.to_s }
            when nil then nil
            else v.to_s
            end
          end.compact
        rescue StandardError
          {}
        end

        # OTel semconv for exceptions:
        #   span.record_exception(exception)  -- adds an "exception" event
        #   span.status = OpenTelemetry::Trace::Status.error("message")
        def record_block_exception(span, exception)
          return unless span.respond_to?(:record_exception)
          span.record_exception(exception)

          if defined?(::OpenTelemetry::Trace::Status) &&
             ::OpenTelemetry::Trace::Status.respond_to?(:error)
            span.status = ::OpenTelemetry::Trace::Status.error(exception.message.to_s[0, 200])
          end
        rescue StandardError
          nil
        end
      end
    end
  end
end
