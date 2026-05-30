# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Integrations::LlmMiddleware do
  # Lightweight Faraday env double — only the fields we read. Built as a
  # Struct so the spec runs without faraday installed in the bundle.
  FakeUrl  = Struct.new(:host, keyword_init: true)
  FakeEnv  = Struct.new(:url, :body, keyword_init: true)
  FakeResp = Struct.new(:status, :body, :headers, keyword_init: true)

  let(:collector) { RailsErrorDashboard::Services::BreadcrumbCollector }

  let(:app) do
    ->(_env) {
      FakeResp.new(status: 200, body: openai_chat_response_body.to_json, headers: { "content-type" => "application/json" })
    }
  end

  subject(:middleware) { described_class.new(app) }

  let(:openai_chat_response_body) do
    {
      "id" => "chatcmpl-abc",
      "model" => "gpt-4o-mini",
      "choices" => [
        { "index" => 0, "message" => { "role" => "assistant", "content" => "hello" }, "finish_reason" => "stop" }
      ],
      "usage" => { "prompt_tokens" => 120, "completion_tokens" => 35, "total_tokens" => 155 }
    }
  end

  def openai_env(body: { "model" => "gpt-4o-mini", "messages" => [ { "role" => "user", "content" => "hi" } ] })
    FakeEnv.new(url: FakeUrl.new(host: "api.openai.com"), body: body.to_json)
  end

  def anthropic_env(body: { "model" => "claude-sonnet-4-6", "messages" => [ { "role" => "user", "content" => "hi" } ] })
    FakeEnv.new(url: FakeUrl.new(host: "api.anthropic.com"), body: body.to_json)
  end

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

  describe "#call — pass-through when disabled" do
    it "does not record a breadcrumb when enable_llm_observability is off" do
      RailsErrorDashboard.configuration.enable_llm_observability = false
      expect { middleware.call(openai_env) }.not_to change { collector.current_breadcrumbs.size }
    end

    it "does not record a breadcrumb when enable_breadcrumbs is off" do
      RailsErrorDashboard.configuration.enable_breadcrumbs = false
      expect { middleware.call(openai_env) }.not_to change { collector.current_breadcrumbs.size }
    end

    it "returns the upstream response in both disabled cases" do
      RailsErrorDashboard.configuration.enable_llm_observability = false
      response = middleware.call(openai_env)
      expect(response.status).to eq(200)
    end
  end

  describe "#call — non-LLM hosts" do
    it "skips with no breadcrumb and one host comparison" do
      env = FakeEnv.new(url: FakeUrl.new(host: "example.com"), body: "{}")
      expect { middleware.call(env) }.not_to change { collector.current_breadcrumbs.size }
    end

    it "tolerates a nil URL without raising" do
      env = FakeEnv.new(url: nil, body: nil)
      expect { middleware.call(env) }.not_to raise_error
      expect(collector.current_breadcrumbs).to be_empty
    end
  end

  describe "#call — successful OpenAI chat" do
    it "records an llm breadcrumb with provider, model, tokens, duration, and cost" do
      middleware.call(openai_env)

      crumbs = collector.current_breadcrumbs
      expect(crumbs.size).to eq(1)

      crumb = crumbs.first
      expect(crumb[:c]).to eq("llm")
      expect(crumb[:m]).to include("openai", "gpt-4o-mini", "in:120/out:35")
      expect(crumb[:d]).to be_a(Numeric)
      expect(crumb[:d]).to be > 0

      # BreadcrumbCollector stringifies metadata values (lesson 14a).
      meta = crumb[:meta]
      expect(meta[:provider]).to eq("openai")
      expect(meta[:model]).to eq("gpt-4o-mini")
      expect(meta[:status]).to eq("success")
      expect(meta[:input_tokens]).to eq("120")
      expect(meta[:output_tokens]).to eq("35")
      # Cost: 120 * 0.15 + 35 * 0.60 = 18 + 21 = 39 / 1M = 0.000039
      expect(meta[:cost_usd]).to eq("3.9e-05")
    end

    it "prefers the response.model over the request model" do
      app_with_versioned_model = ->(_env) {
        body = openai_chat_response_body.merge("model" => "gpt-4o-mini-2026-04-01")
        FakeResp.new(status: 200, body: body.to_json, headers: { "content-type" => "application/json" })
      }
      mw = described_class.new(app_with_versioned_model)

      mw.call(openai_env)
      expect(collector.current_breadcrumbs.first[:meta][:model]).to eq("gpt-4o-mini-2026-04-01")
    end

    it "accepts already-parsed Hash bodies (some adapters skip JSON encoding)" do
      hash_body_app = ->(_env) {
        FakeResp.new(status: 200, body: openai_chat_response_body, headers: { "content-type" => "application/json" })
      }
      mw = described_class.new(hash_body_app)

      env = FakeEnv.new(url: FakeUrl.new(host: "api.openai.com"),
                       body: { "model" => "gpt-4o-mini", "messages" => [] })
      mw.call(env)

      meta = collector.current_breadcrumbs.first[:meta]
      expect(meta[:model]).to eq("gpt-4o-mini")
      expect(meta[:input_tokens]).to eq("120")
    end
  end

  describe "#call — successful Anthropic chat" do
    let(:anthropic_response_body) do
      {
        "id" => "msg_abc",
        "model" => "claude-sonnet-4-6",
        "content" => [ { "type" => "text", "text" => "hi" } ],
        "usage" => { "input_tokens" => 1500, "output_tokens" => 420 },
        "stop_reason" => "end_turn"
      }
    end

    it "maps Anthropic usage fields (input_tokens/output_tokens)" do
      anthropic_app = ->(_env) {
        FakeResp.new(status: 200, body: anthropic_response_body.to_json, headers: { "content-type" => "application/json" })
      }
      mw = described_class.new(anthropic_app)

      mw.call(anthropic_env)

      meta = collector.current_breadcrumbs.first[:meta]
      expect(meta[:provider]).to eq("anthropic")
      expect(meta[:model]).to eq("claude-sonnet-4-6")
      expect(meta[:input_tokens]).to eq("1500")
      expect(meta[:output_tokens]).to eq("420")
      # 1500 * 3.0 + 420 * 15.0 = 4500 + 6300 = 10800 / 1M = 0.0108
      expect(meta[:cost_usd]).to eq("0.0108")
    end
  end

  describe "#call — tool-call responses" do
    it "records tool_calls_requested summary for OpenAI tool_calls" do
      response_body = {
        "id" => "chatcmpl-tools",
        "model" => "gpt-4o",
        "choices" => [ {
          "message" => {
            "tool_calls" => [
              { "id" => "call_1", "type" => "function", "function" => { "name" => "search_db", "arguments" => "{}" } },
              { "id" => "call_2", "type" => "function", "function" => { "name" => "send_email", "arguments" => "{}" } }
            ]
          },
          "finish_reason" => "tool_calls"
        } ],
        "usage" => { "prompt_tokens" => 200, "completion_tokens" => 90 }
      }
      app_with_tools = ->(_env) {
        FakeResp.new(status: 200, body: response_body.to_json, headers: { "content-type" => "application/json" })
      }
      mw = described_class.new(app_with_tools)

      mw.call(openai_env)

      meta = collector.current_breadcrumbs.first[:meta]
      expect(meta[:tool_arguments]).to include("tools:2", "search_db", "send_email")
      # Still emitted as the chat (llm) category — tool execution is captured
      # separately by the OTel path or the application's own instrumentation.
      expect(collector.current_breadcrumbs.first[:c]).to eq("llm")
    end

    it "summarises only the first 3 tool names and counts the remainder" do
      response_body = {
        "model" => "gpt-4o",
        "choices" => [ {
          "message" => {
            "tool_calls" => 5.times.map { |i|
              { "id" => "c#{i}", "type" => "function", "function" => { "name" => "tool_#{i}" } }
            }
          }
        } ],
        "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5 }
      }
      app_with_many = ->(_env) {
        FakeResp.new(status: 200, body: response_body.to_json, headers: { "content-type" => "application/json" })
      }
      mw = described_class.new(app_with_many)
      mw.call(openai_env)

      meta = collector.current_breadcrumbs.first[:meta]
      # truncated metadata caps at 200 chars but the summary is short
      expect(meta[:tool_arguments]).to include("tools:5", "tool_0", "tool_1", "tool_2", "+2 more")
      expect(meta[:tool_arguments]).not_to include("tool_3")
    end

    it "records Anthropic tool_use blocks" do
      response_body = {
        "model" => "claude-sonnet-4-6",
        "content" => [
          { "type" => "text", "text" => "Let me check" },
          { "type" => "tool_use", "id" => "toolu_1", "name" => "search_db", "input" => {} }
        ],
        "usage" => { "input_tokens" => 100, "output_tokens" => 40 },
        "stop_reason" => "tool_use"
      }
      anthropic_tool_app = ->(_env) {
        FakeResp.new(status: 200, body: response_body.to_json, headers: { "content-type" => "application/json" })
      }
      mw = described_class.new(anthropic_tool_app)
      mw.call(anthropic_env)

      meta = collector.current_breadcrumbs.first[:meta]
      expect(meta[:tool_arguments]).to include("tools:1", "search_db")
    end
  end

  describe "#call — HTTP errors" do
    it "records an error breadcrumb for 4xx with the API error message" do
      error_app = ->(_env) {
        body = { "error" => { "message" => "rate limit exceeded", "type" => "rate_limit_error" } }.to_json
        FakeResp.new(status: 429, body: body, headers: { "content-type" => "application/json" })
      }
      mw = described_class.new(error_app)
      mw.call(openai_env)

      meta = collector.current_breadcrumbs.first[:meta]
      expect(meta[:status]).to eq("error")
      expect(meta[:error_class]).to eq("HTTP 429")
      expect(meta[:error_message]).to eq("rate limit exceeded")
      # No cost estimate on failure
      expect(meta).not_to have_key(:cost_usd)
    end

    it "records 5xx as error and tolerates a body that isn't JSON" do
      error_app = ->(_env) {
        FakeResp.new(status: 503, body: "<html>service unavailable</html>", headers: { "content-type" => "text/html" })
      }
      mw = described_class.new(error_app)
      mw.call(openai_env)

      meta = collector.current_breadcrumbs.first[:meta]
      expect(meta[:status]).to eq("error")
      expect(meta[:error_class]).to eq("HTTP 503")
    end
  end

  describe "#call — upstream exceptions" do
    it "re-raises the original exception (host-app safety #1: never swallow)" do
      boom_app = ->(_env) { raise Faraday::TimeoutError.new("timeout") if defined?(Faraday::TimeoutError); raise "timeout" }
      mw = described_class.new(boom_app)
      expect { mw.call(openai_env) }.to raise_error(StandardError, /timeout/)
    end

    it "still records a breadcrumb in the ensure block before re-raising" do
      boom_app = ->(_env) { raise StandardError, "connection reset" }
      mw = described_class.new(boom_app)

      begin
        mw.call(openai_env)
      rescue StandardError
        # expected
      end

      meta = collector.current_breadcrumbs.first[:meta]
      expect(meta[:status]).to eq("error")
      expect(meta[:error_class]).to eq("StandardError")
      expect(meta[:error_message]).to eq("connection reset")
    end

    it "classifies timeout exceptions as :timeout status" do
      timeout_class = Class.new(StandardError) do
        def self.name; "Net::OpenTimeout"; end
      end
      boom_app = ->(_env) { raise timeout_class, "too slow" }
      mw = described_class.new(boom_app)

      begin; mw.call(openai_env); rescue StandardError; end

      meta = collector.current_breadcrumbs.first[:meta]
      expect(meta[:status]).to eq("timeout")
    end
  end

  describe "#call — streaming responses" do
    it "skips emission when content-type is text/event-stream" do
      stream_app = ->(_env) {
        FakeResp.new(status: 200, body: "data: ...\n\n", headers: { "content-type" => "text/event-stream" })
      }
      mw = described_class.new(stream_app)
      mw.call(openai_env)

      expect(collector.current_breadcrumbs).to be_empty
    end

    it "still returns the streaming response unchanged" do
      stream_resp = FakeResp.new(status: 200, body: "data: ...\n\n", headers: { "content-type" => "text/event-stream" })
      stream_app = ->(_env) { stream_resp }
      mw = described_class.new(stream_app)

      expect(mw.call(openai_env)).to equal(stream_resp)
    end
  end

  describe "host app safety" do
    it "never raises when the response body is garbage" do
      garbage_app = ->(_env) {
        FakeResp.new(status: 200, body: "\x00\x01garbage}}{{", headers: { "content-type" => "application/json" })
      }
      mw = described_class.new(garbage_app)

      expect { mw.call(openai_env) }.not_to raise_error
      # The call still recorded — model came from the request body, tokens nil
      crumb = collector.current_breadcrumbs.first
      expect(crumb).not_to be_nil
      expect(crumb[:meta][:model]).to eq("gpt-4o-mini")
    end

    it "never raises when the request body is garbage" do
      bad_env = FakeEnv.new(url: FakeUrl.new(host: "api.openai.com"), body: "<<<not json>>>")
      expect { middleware.call(bad_env) }.not_to raise_error
    end

    it "still returns the upstream response when breadcrumb emission itself errors" do
      # Force an internal failure by mocking BreadcrumbCollector.add to raise.
      allow(RailsErrorDashboard::Services::BreadcrumbCollector)
        .to receive(:add).and_raise(StandardError, "boom in collector")

      response = middleware.call(openai_env)
      expect(response.status).to eq(200)
    end
  end
end
