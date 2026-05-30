# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::LlmSummary do
  # Production breadcrumbs come from BreadcrumbCollector which stringifies all
  # metadata values. Test fixtures mirror that contract — strings everywhere.
  def llm_crumb(provider: "openai", model: "gpt-4o-mini",
                input: "100", output: "20", cost: "0.0005",
                status: "success", duration: 250.0, **extra)
    {
      "t" => 1, "c" => "llm", "m" => "#{provider} · #{model}", "d" => duration,
      "meta" => {
        "provider" => provider, "model" => model, "status" => status,
        "input_tokens" => input, "output_tokens" => output,
        "cost_usd" => cost
      }.merge(extra.transform_keys(&:to_s))
    }
  end

  def tool_crumb(name: "get_weather", duration: 12.0)
    {
      "t" => 2, "c" => "llm_tool", "m" => "tool: #{name}", "d" => duration,
      "meta" => { "tool_name" => name }
    }
  end

  describe ".call" do
    context "with no breadcrumbs at all" do
      it "returns nil for an empty array" do
        expect(described_class.call([])).to be_nil
      end

      it "returns nil for nil input" do
        expect(described_class.call(nil)).to be_nil
      end

      it "returns nil for non-array input" do
        expect(described_class.call("not an array")).to be_nil
      end
    end

    context "with no LLM breadcrumbs" do
      it "returns nil when only non-LLM breadcrumbs are present" do
        result = described_class.call([
          { "c" => "sql", "m" => "SELECT 1", "d" => 1.0 },
          { "c" => "cache", "m" => "cache read: foo", "d" => 0.5 }
        ])
        expect(result).to be_nil
      end
    end

    context "with a single successful LLM call" do
      it "returns totals matching that single call" do
        result = described_class.call([ llm_crumb ])
        expect(result[:total_calls]).to eq(1)
        expect(result[:total_tool_calls]).to eq(0)
        expect(result[:total_input_tokens]).to eq(100)
        expect(result[:total_output_tokens]).to eq(20)
        expect(result[:total_tokens]).to eq(120)
        expect(result[:total_cost_usd]).to eq(0.0005)
        expect(result[:error_count]).to eq(0)
        expect(result[:total_duration_ms]).to eq(250.0)
        expect(result[:providers]).to eq([ "openai" ])
      end

      it "puts the single provider/model into by_model" do
        result = described_class.call([ llm_crumb ])
        expect(result[:by_model]).to eq([
          { provider: "openai", model: "gpt-4o-mini", calls: 1, tokens: 120, cost_usd: 0.0005 }
        ])
      end
    end

    context "with multiple calls across two providers" do
      let(:breadcrumbs) do
        [
          llm_crumb(provider: "openai",    model: "gpt-4o-mini", input: "100", output: "20",  cost: "0.0005", duration: 250.0),
          llm_crumb(provider: "openai",    model: "gpt-4o-mini", input: "200", output: "30",  cost: "0.0008", duration: 300.0),
          llm_crumb(provider: "anthropic", model: "claude-sonnet-4-5", input: "500", output: "100", cost: "0.0050", duration: 800.0)
        ]
      end

      it "sums tokens, cost, and duration across all calls" do
        result = described_class.call(breadcrumbs)
        expect(result[:total_calls]).to eq(3)
        expect(result[:total_input_tokens]).to eq(800)
        expect(result[:total_output_tokens]).to eq(150)
        expect(result[:total_tokens]).to eq(950)
        expect(result[:total_cost_usd]).to eq(0.0063)
        expect(result[:total_duration_ms]).to eq(1350.0)
      end

      it "lists both providers sorted alphabetically" do
        expect(described_class.call(breadcrumbs)[:providers]).to eq([ "anthropic", "openai" ])
      end

      it "groups by_model and orders by call count desc" do
        result = described_class.call(breadcrumbs)
        expect(result[:by_model].first).to eq(
          provider: "openai", model: "gpt-4o-mini", calls: 2, tokens: 350, cost_usd: 0.0013
        )
        expect(result[:by_model].last).to eq(
          provider: "anthropic", model: "claude-sonnet-4-5", calls: 1, tokens: 600, cost_usd: 0.005
        )
      end
    end

    context "with error and timeout statuses" do
      it "counts non-success calls as errors" do
        result = described_class.call([
          llm_crumb(status: "success"),
          llm_crumb(status: "error"),
          llm_crumb(status: "timeout")
        ])
        expect(result[:error_count]).to eq(2)
      end

      it "treats missing status as success (does not count)" do
        crumb = llm_crumb
        crumb["meta"].delete("status")
        expect(described_class.call([ crumb ])[:error_count]).to eq(0)
      end
    end

    context "with tool calls" do
      it "counts tool calls separately from chat calls" do
        result = described_class.call([ llm_crumb, tool_crumb, tool_crumb(name: "lookup") ])
        expect(result[:total_calls]).to eq(1)
        expect(result[:total_tool_calls]).to eq(2)
      end

      it "adds tool durations to total_duration_ms" do
        result = described_class.call([
          llm_crumb(duration: 100.0),
          tool_crumb(duration: 25.0),
          tool_crumb(duration: 10.0)
        ])
        expect(result[:total_duration_ms]).to eq(135.0)
      end

      it "returns a summary when ONLY tool calls are present (no chat)" do
        result = described_class.call([ tool_crumb ])
        expect(result).not_to be_nil
        expect(result[:total_calls]).to eq(0)
        expect(result[:total_tool_calls]).to eq(1)
      end
    end

    context "with missing or malformed metadata" do
      it "handles a crumb whose meta is nil" do
        crumb = { "c" => "llm", "m" => "no meta", "d" => 50.0 }
        result = described_class.call([ crumb ])
        expect(result[:total_calls]).to eq(1)
        expect(result[:total_input_tokens]).to eq(0)
        expect(result[:total_output_tokens]).to eq(0)
        expect(result[:total_cost_usd]).to eq(0.0)
      end

      it "skips empty-string provider when listing providers" do
        crumb = llm_crumb
        crumb["meta"]["provider"] = ""
        expect(described_class.call([ crumb ])[:providers]).to eq([])
      end

      it "ignores non-Hash entries in the array" do
        result = described_class.call([ "garbage", nil, llm_crumb ])
        expect(result[:total_calls]).to eq(1)
      end
    end

    context "host-app safety" do
      it "returns nil rather than raising when an internal error occurs" do
        # Force an internal exception by passing an array of frozen objects that
        # break the .select path — using a raising fake.
        weird = Object.new
        def weird.is_a?(_klass); raise "boom"; end
        expect(described_class.call([ weird ])).to be_nil
      end
    end
  end
end
