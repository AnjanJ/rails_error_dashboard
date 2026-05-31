# frozen_string_literal: true

module RailsErrorDashboard
  module Integrations
    # Faraday middleware that captures LLM calls to OpenAI and Anthropic APIs
    # as breadcrumbs. The Tier 2 path — for hosts using `ruby-openai` or
    # `anthropic-sdk-ruby` directly without OpenTelemetry instrumentation.
    #
    # Install in the host app:
    #
    #   # Anthropic SDK
    #   Anthropic::Client.new do |f|
    #     f.use RailsErrorDashboard::Integrations::LlmMiddleware
    #   end
    #
    #   # ruby-openai
    #   OpenAI::Client.new do |f|
    #     f.use RailsErrorDashboard::Integrations::LlmMiddleware
    #   end
    #
    # IMPORTANT — does NOT subclass ::Faraday::Middleware. Doing so would
    # NameError at file-load time on hosts without Faraday. Faraday accepts
    # any object that responds to `#call(env)` and is initialized with `app`.
    # Hosts that don't use OpenAI/Anthropic SDKs simply won't reference this
    # class and never load the constant.
    #
    # HOST APP SAFETY:
    # - Wraps the upstream call in rescue, but ALWAYS re-raises (we are in
    #   the host's request path — swallowing would break their app logic)
    # - Our own bookkeeping (response parsing, breadcrumb emission) is wrapped
    #   separately in rescue StandardError => nil
    # - No work happens unless enable_llm_observability AND enable_breadcrumbs
    # - Non-LLM URLs (anything but api.openai.com / api.anthropic.com) skip
    #   straight through with one host-string comparison
    # - Streaming responses (SSE) skipped — token counts only available in
    #   the final stream event, which we'd need to buffer to read
    class LlmMiddleware
      OPENAI_HOSTS    = [ "api.openai.com" ].freeze
      ANTHROPIC_HOSTS = [ "api.anthropic.com" ].freeze

      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless RailsErrorDashboard.configuration.enable_llm_observability
        return @app.call(env) unless RailsErrorDashboard.configuration.enable_breadcrumbs

        provider = detect_provider(env)
        return @app.call(env) unless provider

        request_body = safe_parse_body(env.body)
        model        = request_body.is_a?(Hash) ? request_body["model"] : nil
        started_at   = monotonic_ms

        response = nil
        upstream_error = nil
        begin
          response = @app.call(env)
        rescue StandardError => e
          upstream_error = e
          raise
        ensure
          # Record the breadcrumb whether the call succeeded, returned an HTTP
          # error, or raised mid-flight. NEVER raise from this block — the
          # host's app.call has either returned or is propagating an exception
          # via `raise` above, and we must not interfere with either path.
          begin
            duration_ms = (monotonic_ms - started_at).round(2)
            emit_breadcrumb(provider, model, request_body, response, upstream_error, duration_ms)
          rescue StandardError => e
            RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] LlmMiddleware.emit failed: #{e.message}")
          end
        end

        response
      end

      private

      def detect_provider(env)
        host = env.url&.host
        return nil unless host
        return "openai"    if OPENAI_HOSTS.include?(host)
        return "anthropic" if ANTHROPIC_HOSTS.include?(host)
        nil
      end

      def safe_parse_body(body)
        return body if body.is_a?(Hash)
        return {} if body.nil? || (body.respond_to?(:empty?) && body.empty?)
        JSON.parse(body.to_s)
      rescue StandardError
        {}
      end

      def streaming_response?(response)
        return false unless response
        ct = response.respond_to?(:headers) ? response.headers&.[]("content-type") : nil
        ct.is_a?(String) && ct.include?("text/event-stream")
      end

      def emit_breadcrumb(provider, model, request_body, response, upstream_error, duration_ms)
        if upstream_error
          event = build_error_event(provider, model, upstream_error, duration_ms)
          add_crumb(event)
          return
        end

        # Streaming — token counts aren't available without buffering the
        # stream, which would defeat the SDK's streaming behavior. Skip for
        # v0.7.0; a future release can add an SSE parser if demand warrants.
        if streaming_response?(response)
          RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] LlmMiddleware skipping streaming response (#{provider})")
          return
        end

        status      = response.respond_to?(:status) ? response.status : nil
        body        = parse_response_body(response)

        if status && status >= 400
          add_crumb(build_http_error_event(provider, model, status, body, duration_ms))
          return
        end

        add_crumb(build_success_event(provider, model, request_body, body, duration_ms))
      end

      def parse_response_body(response)
        body = response.respond_to?(:body) ? response.body : nil
        return body if body.is_a?(Hash)
        return {} if body.nil? || (body.respond_to?(:empty?) && body.empty?)
        JSON.parse(body.to_s)
      rescue StandardError
        {}
      end

      def build_success_event(provider, request_model, request_body, response_body, duration_ms)
        response_model = response_body.is_a?(Hash) ? response_body["model"] : nil
        model = response_model || request_model

        input_tokens, output_tokens = extract_tokens(provider, response_body)
        tool_calls_requested        = extract_tool_calls(provider, response_body)

        cost = Services::LlmCostEstimator.estimate(
          provider: provider,
          model: model,
          input_tokens: input_tokens,
          output_tokens: output_tokens
        )

        ValueObjects::LlmCallEvent.new(
          provider: provider,
          model: model || "unknown",
          status: :success,
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          duration_ms: duration_ms,
          cost_usd_estimate: cost,
          tool_arguments: tool_calls_metadata(tool_calls_requested)
        )
      end

      def build_http_error_event(provider, model, status, body, duration_ms)
        err_class = "HTTP #{status}"
        err_msg   = extract_error_message(body)

        ValueObjects::LlmCallEvent.new(
          provider: provider,
          model: model || "unknown",
          status: :error,
          duration_ms: duration_ms,
          error_class: err_class,
          error_message: err_msg
        )
      end

      def build_error_event(provider, model, exception, duration_ms)
        status = exception_status(exception)
        ValueObjects::LlmCallEvent.new(
          provider: provider,
          model: model || "unknown",
          status: status,
          duration_ms: duration_ms,
          error_class: exception.class.name,
          error_message: exception.message
        )
      end

      def exception_status(exception)
        klass = exception.class.name.to_s
        return :timeout if klass.include?("Timeout") || klass.include?("TimedOut")
        :error
      end

      # @return [Array(Integer|nil, Integer|nil)] (input_tokens, output_tokens)
      def extract_tokens(provider, body)
        return [ nil, nil ] unless body.is_a?(Hash)
        usage = body["usage"]
        return [ nil, nil ] unless usage.is_a?(Hash)

        case provider
        when "openai"
          [ usage["prompt_tokens"], usage["completion_tokens"] ]
        when "anthropic"
          [ usage["input_tokens"], usage["output_tokens"] ]
        else
          [ nil, nil ]
        end
      end

      # Returns an Array of tool-call descriptors: [{ name: "...", id: "..." }, ...]
      # Empty when the model didn't request any tools.
      def extract_tool_calls(provider, body)
        return [] unless body.is_a?(Hash)

        case provider
        when "openai"
          choices = body["choices"]
          return [] unless choices.is_a?(Array) && choices.any?
          tool_calls = choices.first.dig("message", "tool_calls")
          return [] unless tool_calls.is_a?(Array)
          tool_calls.filter_map do |tc|
            next unless tc.is_a?(Hash)
            name = tc.dig("function", "name")
            name ? { name: name, id: tc["id"] } : nil
          end
        when "anthropic"
          content = body["content"]
          return [] unless content.is_a?(Array)
          content.filter_map do |c|
            next unless c.is_a?(Hash) && c["type"] == "tool_use"
            { name: c["name"], id: c["id"] }
          end
        else
          []
        end
      end

      # Compact summary of tool calls — packed into the
      # `tool_arguments` field on LlmCallEvent so it lands in breadcrumb
      # metadata under `:tool_arguments`. (We reuse the existing slot rather
      # than adding a new field for v0.7.0; UI in 4.1 reads it back.)
      # Returns nil when no tools were requested so the field omits from JSON.
      def tool_calls_metadata(tool_calls)
        return nil if tool_calls.nil? || tool_calls.empty?
        names = tool_calls.first(3).map { |tc| tc[:name] }.compact
        suffix = tool_calls.size > 3 ? "+#{tool_calls.size - 3} more" : nil
        [ "tools:#{tool_calls.size}", names.join(","), suffix ].compact.join(" ")
      end

      def extract_error_message(body)
        return nil unless body.is_a?(Hash)
        # OpenAI: { "error": { "message": "...", "type": "...", "code": "..." } }
        # Anthropic: { "error": { "type": "...", "message": "..." }, "type": "error" }
        err = body["error"]
        return nil unless err.is_a?(Hash)
        err["message"] || err["type"]
      end

      def add_crumb(event)
        category = event.tool_call? ? "llm_tool" : "llm"
        Services::BreadcrumbCollector.add(
          category,
          event.to_breadcrumb_message,
          duration_ms: event.duration_ms,
          metadata: event.to_breadcrumb_metadata
        )
      end

      def monotonic_ms
        Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000.0
      end
    end
  end
end
