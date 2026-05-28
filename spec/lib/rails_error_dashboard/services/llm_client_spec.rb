# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::LlmClient do
  let!(:application) { create(:application) }
  let(:error) { create(:error_log, application: application, error_type: "RuntimeError", message: "boom") }
  let(:context) { "## RuntimeError\nboom\napp/models/user.rb:10" }

  around do |example|
    original = RailsErrorDashboard.configuration
    RailsErrorDashboard.configuration = RailsErrorDashboard::Configuration.new
    example.run
  ensure
    RailsErrorDashboard.configuration = original
  end

  describe ".call" do
    it "calls OpenAI Responses API by default" do
      configure_llm(provider: :openai, model: "gpt-5")

      stub = stub_request(:post, "https://api.openai.com/v1/responses")
        .with do |request|
          body = JSON.parse(request.body)
          request.headers["Authorization"] == "Bearer test-key" &&
            body["model"] == "gpt-5" &&
            body["input"].include?("User question:")
        end
        .to_return(status: 200, body: {
          output: [
            {
              type: "message",
              content: [
                { type: "output_text", text: "Check the failing model callback." }
              ]
            }
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      result = described_class.call(error: error, question: "What should I check?", context: context)

      expect(stub).to have_been_requested
      expect(result).to include(
        answer: "Check the failing model callback.",
        provider: "openai",
        model: "gpt-5"
      )
    end

    it "supports the OpenAI Chat Completions endpoint when configured" do
      configure_llm(provider: :openai, model: "gpt-4.1")
      RailsErrorDashboard.configuration.llm_openai_endpoint = :chat_completions

      stub = stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .with do |request|
          body = JSON.parse(request.body)
          body["model"] == "gpt-4.1" &&
            body["messages"].last["content"].include?("RuntimeError")
        end
        .to_return(status: 200, body: {
          choices: [
            { message: { content: "Inspect the request params and backtrace." } }
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      result = described_class.call(error: error, question: "How do I debug it?", context: context)

      expect(stub).to have_been_requested
      expect(result[:answer]).to eq("Inspect the request params and backtrace.")
    end

    it "calls Anthropic Messages API" do
      configure_llm(provider: :anthropic, model: "claude-sonnet-4-20250514")

      stub = stub_request(:post, "https://api.anthropic.com/v1/messages")
        .with do |request|
          body = JSON.parse(request.body)
          request.headers["X-Api-Key"] == "test-key" &&
            request.headers["Anthropic-Version"] == "2023-06-01" &&
            body["model"] == "claude-sonnet-4-20250514" &&
            body["messages"].first["content"].include?("RuntimeError")
        end
        .to_return(status: 200, body: {
          content: [
            { type: "text", text: "The registry lookup is missing a row." }
          ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      result = described_class.call(error: error, question: "Why is this failing?", context: context)

      expect(stub).to have_been_requested
      expect(result).to include(
        answer: "The registry lookup is missing a row.",
        provider: "anthropic",
        model: "claude-sonnet-4-20250514"
      )
    end

    it "raises a request error for provider failures" do
      configure_llm(provider: :openai, model: "gpt-5")

      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 401, body: { error: { message: "bad key" } }.to_json)

      expect {
        described_class.call(error: error, question: "What failed?", context: context)
      }.to raise_error(described_class::RequestError, /bad key/)
    end
  end

  describe ".stream" do
    it "streams OpenAI Responses API text deltas" do
      configure_llm(provider: :openai, model: "gpt-5")

      stub = stub_request(:post, "https://api.openai.com/v1/responses")
        .with do |request|
          body = JSON.parse(request.body)
          body["model"] == "gpt-5" &&
            body["stream"] == true &&
            body["input"].include?("RuntimeError")
        end
        .to_return(status: 200, body: [
          "event: response.output_text.delta",
          'data: {"type":"response.output_text.delta","delta":"Check"}',
          "",
          "event: response.output_text.delta",
          'data: {"type":"response.output_text.delta","delta":" callbacks"}',
          "",
          "event: response.completed",
          'data: {"type":"response.completed"}',
          ""
        ].join("\n"), headers: { "Content-Type" => "text/event-stream" })

      chunks = []
      result = described_class.stream(error: error, question: "What should I check?", context: context) do |text|
        chunks << text
      end

      expect(stub).to have_been_requested
      expect(chunks).to eq([ "Check", " callbacks" ])
      expect(result).to include(provider: "openai", model: "gpt-5")
    end

    it "streams OpenAI Chat Completions content deltas" do
      configure_llm(provider: :openai, model: "gpt-4.1")
      RailsErrorDashboard.configuration.llm_openai_endpoint = :chat_completions

      stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(status: 200, body: [
          'data: {"choices":[{"delta":{"content":"Inspect"}}]}',
          "",
          'data: {"choices":[{"delta":{"content":" params"}}]}',
          "",
          "data: [DONE]",
          ""
        ].join("\n"), headers: { "Content-Type" => "text/event-stream" })

      chunks = []
      described_class.stream(error: error, question: "How do I debug it?", context: context) do |text|
        chunks << text
      end

      expect(chunks).to eq([ "Inspect", " params" ])
    end

    it "streams Anthropic text deltas" do
      configure_llm(provider: :anthropic, model: "claude-sonnet-4-20250514")

      stub = stub_request(:post, "https://api.anthropic.com/v1/messages")
        .with do |request|
          body = JSON.parse(request.body)
          body["model"] == "claude-sonnet-4-20250514" &&
            body["stream"] == true &&
            body["messages"].first["content"].include?("RuntimeError")
        end
        .to_return(status: 200, body: [
          "event: message_start",
          'data: {"type":"message_start","message":{"content":[]}}',
          "",
          "event: content_block_delta",
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Missing"}}',
          "",
          "event: content_block_delta",
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" row"}}',
          "",
          "event: message_stop",
          'data: {"type":"message_stop"}',
          ""
        ].join("\n"), headers: { "Content-Type" => "text/event-stream" })

      chunks = []
      result = described_class.stream(error: error, question: "Why?", context: context) do |text|
        chunks << text
      end

      expect(stub).to have_been_requested
      expect(chunks).to eq([ "Missing", " row" ])
      expect(result).to include(provider: "anthropic", model: "claude-sonnet-4-20250514")
    end
  end

  def configure_llm(provider:, model:)
    RailsErrorDashboard.configuration.llm_provider = provider
    RailsErrorDashboard.configuration.llm_api_key = "test-key"
    RailsErrorDashboard.configuration.llm_model = model
  end
end
