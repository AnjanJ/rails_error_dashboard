# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module RailsErrorDashboard
  module Services
    class LlmClient
      class ConfigurationError < StandardError; end
      class RequestError < StandardError; end

      OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses"
      OPENAI_CHAT_COMPLETIONS_URL = "https://api.openai.com/v1/chat/completions"
      ANTHROPIC_MESSAGES_URL = "https://api.anthropic.com/v1/messages"
      ANTHROPIC_VERSION = "2023-06-01"

      attr_reader :config

      def self.call(error:, question:, context:)
        new.call(error: error, question: question, context: context)
      end

      def initialize(config: RailsErrorDashboard.configuration)
        @config = config
      end

      def call(error:, question:, context:)
        raise ConfigurationError, "AI Help is not configured" unless config.llm_configured?

        case config.effective_llm_provider
        when :openai
          openai_response(error: error, question: question, context: context)
        when :anthropic
          anthropic_response(error: error, question: question, context: context)
        else
          raise ConfigurationError, "Unsupported LLM provider: #{config.llm_provider.inspect}"
        end
      end

      private

      def openai_response(error:, question:, context:)
        model = config.effective_llm_model
        mode = openai_endpoint_for(model)

        if mode == :chat_completions
          response = post_json(
            OPENAI_CHAT_COMPLETIONS_URL,
            openai_headers,
            openai_chat_payload(error: error, question: question, context: context, model: model)
          )
          answer = response.dig("choices", 0, "message", "content")
        else
          response = post_json(
            OPENAI_RESPONSES_URL,
            openai_headers,
            openai_responses_payload(error: error, question: question, context: context, model: model)
          )
          answer = extract_openai_response_text(response)
        end

        provider_result(answer, :openai, model)
      end

      def anthropic_response(error:, question:, context:)
        model = config.effective_llm_model
        response = post_json(
          ANTHROPIC_MESSAGES_URL,
          anthropic_headers,
          anthropic_payload(error: error, question: question, context: context, model: model)
        )
        answer = Array(response["content"]).filter_map { |part| part["text"] if part["type"] == "text" }.join("\n\n")

        provider_result(answer, :anthropic, model)
      end

      def openai_endpoint_for(model)
        configured = config.llm_openai_endpoint&.to_sym || :auto
        return configured unless configured == :auto

        :responses
      end

      def openai_headers
        {
          "Authorization" => "Bearer #{config.effective_llm_api_key}",
          "Content-Type" => "application/json"
        }
      end

      def anthropic_headers
        {
          "x-api-key" => config.effective_llm_api_key,
          "anthropic-version" => ANTHROPIC_VERSION,
          "Content-Type" => "application/json"
        }
      end

      def openai_responses_payload(error:, question:, context:, model:)
        payload = {
          model: model,
          instructions: system_prompt,
          input: user_prompt(error: error, question: question, context: context),
          max_output_tokens: config.llm_max_output_tokens.to_i
        }

        payload
      end

      def openai_chat_payload(error:, question:, context:, model:)
        {
          model: model,
          messages: [
            { role: "system", content: system_prompt },
            { role: "user", content: user_prompt(error: error, question: question, context: context) }
          ],
          max_tokens: config.llm_max_output_tokens.to_i
        }
      end

      def anthropic_payload(error:, question:, context:, model:)
        {
          model: model,
          max_tokens: config.llm_max_output_tokens.to_i,
          system: system_prompt,
          messages: [
            { role: "user", content: user_prompt(error: error, question: question, context: context) }
          ]
        }
      end

      def system_prompt
        prompt = <<~PROMPT.strip
          You are helping debug a Rails exception from Rails Error Dashboard.
          Answer only from the provided error context unless you clearly label an inference.
          Focus on likely root cause, useful next checks, and concrete Rails code or data fixes.
          Do not ask for secrets, credentials, or unrelated source code.
        PROMPT

        [ prompt, config.llm_system_prompt.presence ].compact.join("\n\n")
      end

      def user_prompt(error:, question:, context:)
        <<~PROMPT
          Error ID: #{error.id}
          Error type: #{error.error_type}
          Severity: #{error.severity}
          Occurrences: #{error.occurrence_count}

          User question:
          #{question}

          Error context:
          #{context}
        PROMPT
      end

      def post_json(url, headers, payload)
        uri = URI.parse(url)
        request = Net::HTTP::Post.new(uri.request_uri, headers)
        request.body = JSON.generate(payload)

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
          open_timeout: config.llm_timeout_seconds.to_i,
          read_timeout: config.llm_timeout_seconds.to_i) do |http|
          http.request(request)
        end

        parsed = parse_json_response(response)
        return parsed if response.is_a?(Net::HTTPSuccess)

        message = parsed.dig("error", "message") || parsed["error"] || response.message
        raise RequestError, "LLM request failed (#{response.code}): #{message}"
      rescue JSON::ParserError
        raise RequestError, "LLM provider returned invalid JSON"
      rescue Net::OpenTimeout, Net::ReadTimeout
        raise RequestError, "LLM request timed out"
      rescue SocketError, SystemCallError => e
        raise RequestError, "LLM request failed: #{e.message}"
      end

      def parse_json_response(response)
        body = response.body.to_s
        body.present? ? JSON.parse(body) : {}
      end

      def extract_openai_response_text(response)
        return response["output_text"] if response["output_text"].present?

        Array(response["output"]).flat_map do |item|
          Array(item["content"]).filter_map { |part| part["text"] if part["type"] == "output_text" || part["type"] == "text" }
        end.join("\n\n")
      end

      def provider_result(answer, provider, model)
        raise RequestError, "LLM provider returned an empty answer" if answer.blank?

        { answer: answer, provider: provider.to_s, model: model }
      end
    end
  end
end
