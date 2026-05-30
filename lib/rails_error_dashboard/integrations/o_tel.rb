# frozen_string_literal: true

module RailsErrorDashboard
  module Integrations
    # Detection shim for the OpenTelemetry SDK. The LLM-observability feature
    # registers a SpanProcessor against `OpenTelemetry.tracer_provider` when
    # the host app already runs OTel — for ruby_llm and thoughtbot users
    # this is the zero-config path. When OTel is absent, we silently skip
    # the SpanProcessor (the Faraday middleware path still works).
    #
    # `opentelemetry-sdk` is an OPTIONAL dependency. This module must never
    # raise, never require the gem itself, and never assume the host has it.
    module OTel
      class << self
        # Returns true when the OpenTelemetry SDK is loaded and the
        # SpanProcessor base class is reachable (Task 2.2 subclasses it).
        # Memoized — host apps don't dynamically load gems mid-process.
        # Rescues any unexpected error to a hard false: a broken partial
        # install must never block a request in the host app.
        # @return [Boolean]
        def available?
          return @available unless @available.nil?
          @available = detect
        rescue StandardError
          @available = false
        end

        # Test hook — clears the memoized result so specs can flip
        # OpenTelemetry constants in/out between examples.
        def reset!
          @available = nil
        end

        private

        def detect
          return false unless defined?(::OpenTelemetry)
          return false unless defined?(::OpenTelemetry::SDK)
          return false unless defined?(::OpenTelemetry::SDK::Trace::SpanProcessor)
          true
        end
      end
    end
  end
end
