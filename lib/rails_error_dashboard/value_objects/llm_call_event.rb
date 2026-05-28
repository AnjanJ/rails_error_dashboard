# frozen_string_literal: true

module RailsErrorDashboard
  module ValueObjects
    # Immutable value object representing a single LLM call observed in the
    # host application. One canonical shape that all capture paths (OTel
    # SpanProcessor, Faraday middleware, future native subscribers) normalize
    # to before handing off to BreadcrumbCollector.
    #
    # Fields are read-only after initialization. Unknown / unavailable fields
    # are nil — never raise, never block, never allocate large strings.
    class LlmCallEvent
      STATUSES = [ :success, :error, :timeout ].freeze
      MAX_TOOL_ARG_LENGTH = 500
      MAX_TOOL_RESULT_LENGTH = 500
      MAX_ERROR_MESSAGE_LENGTH = 200

      attr_reader :provider, :model, :input_tokens, :output_tokens,
                  :duration_ms, :status, :error_class, :error_message,
                  :tool_name, :tool_arguments_truncated, :tool_result_truncated,
                  :cost_usd_estimate

      def initialize(provider:, model:, status:,
                     input_tokens: nil, output_tokens: nil, duration_ms: nil,
                     error_class: nil, error_message: nil,
                     tool_name: nil, tool_arguments: nil, tool_result: nil,
                     cost_usd_estimate: nil)
        @provider = provider.to_s
        @model = model.to_s
        @status = STATUSES.include?(status) ? status : :success
        @input_tokens = input_tokens
        @output_tokens = output_tokens
        @duration_ms = duration_ms
        @error_class = error_class
        @error_message = truncate(error_message, MAX_ERROR_MESSAGE_LENGTH)
        @tool_name = tool_name
        @tool_arguments_truncated = truncate(tool_arguments, MAX_TOOL_ARG_LENGTH)
        @tool_result_truncated = truncate(tool_result, MAX_TOOL_RESULT_LENGTH)
        @cost_usd_estimate = cost_usd_estimate
        freeze
      end

      def tool_call?
        !@tool_name.nil?
      end

      # Hash shape passed to BreadcrumbCollector.add(..., metadata:).
      # Only includes non-nil keys — keeps the breadcrumb JSON compact.
      def to_breadcrumb_metadata
        {
          provider: @provider,
          model: @model,
          status: @status.to_s,
          input_tokens: @input_tokens,
          output_tokens: @output_tokens,
          duration_ms: @duration_ms,
          error_class: @error_class,
          error_message: @error_message,
          tool_name: @tool_name,
          tool_arguments: @tool_arguments_truncated,
          tool_result: @tool_result_truncated,
          cost_usd: @cost_usd_estimate
        }.compact
      end

      # Short human-readable message for the breadcrumb (rendered in UI).
      def to_breadcrumb_message
        if tool_call?
          "tool: #{@tool_name}"
        else
          parts = [ @provider, @model ]
          if @input_tokens && @output_tokens
            parts << "in:#{@input_tokens}/out:#{@output_tokens}"
          end
          parts << @status.to_s if @status != :success
          parts.compact.join(" · ")
        end
      end

      private

      def truncate(value, limit)
        return nil if value.nil?
        str = value.to_s
        return str if str.length <= limit
        "#{str[0, limit]}…"
      rescue
        nil
      end
    end
  end
end
