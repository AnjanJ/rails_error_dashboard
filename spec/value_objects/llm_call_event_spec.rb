# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::ValueObjects::LlmCallEvent do
  describe "#initialize" do
    it "constructs a minimal event with just the required fields" do
      event = described_class.new(provider: "anthropic", model: "claude-sonnet-4-6", status: :success)

      expect(event.provider).to eq("anthropic")
      expect(event.model).to eq("claude-sonnet-4-6")
      expect(event.status).to eq(:success)
      expect(event.input_tokens).to be_nil
      expect(event.output_tokens).to be_nil
      expect(event.duration_ms).to be_nil
      expect(event.tool_name).to be_nil
    end

    it "accepts full LLM call metadata" do
      event = described_class.new(
        provider: "openai",
        model: "gpt-4o",
        status: :success,
        input_tokens: 1234,
        output_tokens: 56,
        duration_ms: 421.5,
        cost_usd_estimate: 0.012
      )

      expect(event.input_tokens).to eq(1234)
      expect(event.output_tokens).to eq(56)
      expect(event.duration_ms).to eq(421.5)
      expect(event.cost_usd_estimate).to eq(0.012)
    end

    it "freezes the instance to prevent mutation" do
      event = described_class.new(provider: "anthropic", model: "x", status: :success)
      expect(event).to be_frozen
    end

    it "coerces provider and model to strings" do
      event = described_class.new(provider: :openai, model: :gpt_4o, status: :success)
      expect(event.provider).to eq("openai")
      expect(event.model).to eq("gpt_4o")
    end

    it "falls back to :success for unknown statuses" do
      event = described_class.new(provider: "x", model: "y", status: :weird)
      expect(event.status).to eq(:success)
    end

    it "accepts the three valid statuses" do
      described_class::STATUSES.each do |s|
        event = described_class.new(provider: "x", model: "y", status: s)
        expect(event.status).to eq(s)
      end
    end
  end

  describe "tool call fields" do
    it "is not a tool call without tool_name" do
      event = described_class.new(provider: "openai", model: "gpt-4o", status: :success)
      expect(event.tool_call?).to be false
    end

    it "is a tool call when tool_name is given" do
      event = described_class.new(
        provider: "anthropic", model: "claude-sonnet-4-6", status: :success,
        tool_name: "search_database"
      )
      expect(event.tool_call?).to be true
    end

    it "truncates tool arguments exceeding the limit" do
      long = "a" * 1000
      event = described_class.new(
        provider: "x", model: "y", status: :success,
        tool_name: "t", tool_arguments: long
      )
      expect(event.tool_arguments_truncated.length).to eq(described_class::MAX_TOOL_ARG_LENGTH + 1) # +1 for ellipsis
      expect(event.tool_arguments_truncated).to end_with("…")
    end

    it "truncates tool results exceeding the limit" do
      long = "b" * 1000
      event = described_class.new(
        provider: "x", model: "y", status: :success,
        tool_name: "t", tool_result: long
      )
      expect(event.tool_result_truncated).to end_with("…")
    end

    it "leaves short tool args/results untouched" do
      event = described_class.new(
        provider: "x", model: "y", status: :success,
        tool_name: "t", tool_arguments: "short", tool_result: "ok"
      )
      expect(event.tool_arguments_truncated).to eq("short")
      expect(event.tool_result_truncated).to eq("ok")
    end

    it "coerces non-string tool args via to_s" do
      event = described_class.new(
        provider: "x", model: "y", status: :success,
        tool_name: "t", tool_arguments: { query: "active users" }
      )
      expect(event.tool_arguments_truncated).to include("query")
    end
  end

  describe "error fields" do
    it "truncates long error messages" do
      event = described_class.new(
        provider: "x", model: "y", status: :error,
        error_class: "Net::ReadTimeout", error_message: "x" * 500
      )
      expect(event.error_message).to end_with("…")
      expect(event.error_class).to eq("Net::ReadTimeout")
    end
  end

  describe "#to_breadcrumb_metadata" do
    it "omits nil keys for compact storage" do
      event = described_class.new(provider: "anthropic", model: "claude-sonnet-4-6", status: :success)
      meta = event.to_breadcrumb_metadata

      expect(meta.keys).to contain_exactly(:provider, :model, :status)
      expect(meta).to eq(provider: "anthropic", model: "claude-sonnet-4-6", status: "success")
    end

    it "serializes all set fields with status as a string" do
      event = described_class.new(
        provider: "openai", model: "gpt-4o", status: :error,
        input_tokens: 100, output_tokens: 0, duration_ms: 30_000,
        error_class: "Net::ReadTimeout", error_message: "timed out",
        cost_usd_estimate: 0.003
      )
      meta = event.to_breadcrumb_metadata

      expect(meta[:provider]).to eq("openai")
      expect(meta[:model]).to eq("gpt-4o")
      expect(meta[:status]).to eq("error")
      expect(meta[:input_tokens]).to eq(100)
      expect(meta[:output_tokens]).to eq(0) # 0 is not nil, must remain
      expect(meta[:cost_usd]).to eq(0.003)
      expect(meta[:error_class]).to eq("Net::ReadTimeout")
    end

    it "includes tool fields for tool calls" do
      event = described_class.new(
        provider: "anthropic", model: "claude-sonnet-4-6", status: :success,
        tool_name: "search_db", tool_arguments: '{"q":"users"}', tool_result: "[1,2,3]"
      )
      meta = event.to_breadcrumb_metadata
      expect(meta[:tool_name]).to eq("search_db")
      expect(meta[:tool_arguments]).to eq('{"q":"users"}')
      expect(meta[:tool_result]).to eq("[1,2,3]")
    end
  end

  describe "#to_breadcrumb_message" do
    it "renders a tool call message" do
      event = described_class.new(
        provider: "anthropic", model: "claude-sonnet-4-6", status: :success,
        tool_name: "search_db"
      )
      expect(event.to_breadcrumb_message).to eq("tool: search_db")
    end

    it "renders provider · model · in/out for a normal call" do
      event = described_class.new(
        provider: "openai", model: "gpt-4o", status: :success,
        input_tokens: 100, output_tokens: 50
      )
      expect(event.to_breadcrumb_message).to eq("openai · gpt-4o · in:100/out:50")
    end

    it "omits tokens when not present" do
      event = described_class.new(provider: "openai", model: "gpt-4o", status: :success)
      expect(event.to_breadcrumb_message).to eq("openai · gpt-4o")
    end

    it "appends status when non-success" do
      event = described_class.new(provider: "openai", model: "gpt-4o", status: :timeout)
      expect(event.to_breadcrumb_message).to include("timeout")
    end
  end

  describe "safety" do
    it "does not raise on nil tool_arguments" do
      expect {
        described_class.new(provider: "x", model: "y", status: :success, tool_name: "t", tool_arguments: nil)
      }.not_to raise_error
    end

    it "does not raise on objects with weird to_s" do
      obj = Object.new
      def obj.to_s; raise "boom"; end
      event = described_class.new(provider: "x", model: "y", status: :success, tool_name: "t", tool_arguments: obj)
      expect(event.tool_arguments_truncated).to be_nil
    end
  end
end
