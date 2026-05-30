# frozen_string_literal: true

module RailsErrorDashboard
  module Subscribers
    # ActiveSupport::Notifications subscriber for manually-instrumented LLM
    # calls. The Tier 3 path — for hosts that don't run OpenTelemetry AND
    # don't use Faraday-based LLM SDKs (e.g., direct Net::HTTP, gRPC clients,
    # custom adapters, or hosts that want to layer in extra LLM activity that
    # the automatic paths can't see, like local inference servers).
    #
    # Usage in the host app:
    #
    #   ActiveSupport::Notifications.instrument("red.llm_call",
    #     provider: "ollama",
    #     model: "llama3:8b",
    #     input_tokens: 1200,
    #     output_tokens: 350
    #   ) do
    #     # ... call your LLM ...
    #   end
    #
    #   # Tool execution
    #   ActiveSupport::Notifications.instrument("red.llm_tool_call",
    #     tool_name: "search_database",
    #     tool_arguments: { query: "..." },
    #     tool_result: "[...]"
    #   ) do
    #     # ... execute tool ...
    #   end
    #
    # Payload contract = LlmCallEvent constructor kwargs:
    #   :provider, :model, :status, :input_tokens, :output_tokens,
    #   :duration_ms, :error_class, :error_message, :tool_name,
    #   :tool_arguments, :tool_result, :cost_usd_estimate
    #
    # Duration: defaults to `event.duration` (host wraps `.instrument` around
    # the work); payload `:duration_ms` overrides if explicitly supplied.
    # Cost: auto-estimated from provider/model/tokens unless payload supplies
    # `:cost_usd_estimate`.
    #
    # SAFETY RULES (HOST_APP_SAFETY.md):
    # - Every callback wrapped in rescue => e; nil
    # - Never raise from subscriber callbacks
    # - Skip if buffer is nil (not in a request context)
    # - Re-read config on every event (host may toggle at runtime)
    class LlmCallSubscriber
      CHAT_EVENT = "red.llm_call"
      TOOL_EVENT = "red.llm_tool_call"
      EVENTS = [ CHAT_EVENT, TOOL_EVENT ].freeze

      @subscriptions = []

      class << self
        attr_reader :subscriptions

        # Idempotent — re-subscribing first tears down previous subscriptions
        # so Spring reloads / repeated engine boots don't pile up duplicates.
        def subscribe!
          unsubscribe!
          @subscriptions = EVENTS.map { |name| subscribe_event(name) }
        end

        def unsubscribe!
          (@subscriptions || []).each do |sub|
            ActiveSupport::Notifications.unsubscribe(sub) if sub
          rescue StandardError
            nil
          end
          @subscriptions = []
        end

        private

        def subscribe_event(event_name)
          ActiveSupport::Notifications.subscribe(event_name) do |*args|
            event = ActiveSupport::Notifications::Event.new(*args)
            handle_event(event, event_name)
          rescue StandardError => e
            RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] LlmCallSubscriber callback failed: #{e.message}")
            nil
          end
        end

        def handle_event(event, event_name)
          return unless RailsErrorDashboard.configuration.enable_llm_observability
          return unless RailsErrorDashboard.configuration.enable_breadcrumbs
          return unless Services::BreadcrumbCollector.current_buffer

          payload = event.payload || {}
          # Symbolize-ish access — hosts may pass either symbol or string keys
          payload = payload.transform_keys(&:to_sym) if payload.respond_to?(:transform_keys)

          tool_name = payload[:tool_name] || (event_name == TOOL_EVENT ? "unknown" : nil)
          provider  = payload[:provider]
          model     = payload[:model]

          duration_ms = payload[:duration_ms]
          duration_ms ||= event.duration if event.respond_to?(:duration)

          status = normalize_status(payload[:status], payload[:error_class])

          cost = payload[:cost_usd_estimate]
          if cost.nil? && tool_name.nil? && status == :success && model
            cost = Services::LlmCostEstimator.estimate(
              provider: provider,
              model: model,
              input_tokens: payload[:input_tokens],
              output_tokens: payload[:output_tokens]
            )
          end

          llm_event = ValueObjects::LlmCallEvent.new(
            provider: provider || "unknown",
            model: model || "unknown",
            status: status,
            input_tokens: payload[:input_tokens],
            output_tokens: payload[:output_tokens],
            duration_ms: duration_ms,
            error_class: payload[:error_class],
            error_message: payload[:error_message],
            tool_name: tool_name,
            tool_arguments: payload[:tool_arguments],
            tool_result: payload[:tool_result],
            cost_usd_estimate: cost
          )

          category = llm_event.tool_call? ? "llm_tool" : "llm"

          Services::BreadcrumbCollector.add(
            category,
            llm_event.to_breadcrumb_message,
            duration_ms: llm_event.duration_ms,
            metadata: llm_event.to_breadcrumb_metadata
          )
        end

        # Status precedence: explicit payload status (if valid) → :error when
        # error_class present → :success.
        def normalize_status(payload_status, error_class)
          if payload_status
            sym = payload_status.to_sym rescue nil
            return sym if ValueObjects::LlmCallEvent::STATUSES.include?(sym)
          end
          return :error if error_class
          :success
        end
      end
    end
  end
end
