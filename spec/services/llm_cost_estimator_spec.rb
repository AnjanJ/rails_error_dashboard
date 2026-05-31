# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::LlmCostEstimator do
  describe ".estimate" do
    before { RailsErrorDashboard.configuration.llm_pricing_overrides = {} }

    context "known models" do
      it "estimates cost for claude-sonnet-4-6" do
        # 1M input @ $3 + 1M output @ $15 = $18
        cost = described_class.estimate(
          provider: "anthropic", model: "claude-sonnet-4-6",
          input_tokens: 1_000_000, output_tokens: 1_000_000
        )
        expect(cost).to eq(18.0)
      end

      it "estimates cost for gpt-4o-mini at small scale" do
        # 1000 input @ $0.15/M + 500 output @ $0.60/M
        cost = described_class.estimate(
          provider: "openai", model: "gpt-4o-mini",
          input_tokens: 1000, output_tokens: 500
        )
        expected = (1000 * 0.15 + 500 * 0.60) / 1_000_000.0
        expect(cost).to be_within(1e-9).of(expected)
      end

      it "matches model name case-insensitively" do
        cost = described_class.estimate(
          provider: "openai", model: "GPT-4o",
          input_tokens: 1_000_000, output_tokens: 0
        )
        expect(cost).to eq(2.50)
      end

      it "handles zero tokens on one side" do
        cost = described_class.estimate(
          provider: "anthropic", model: "claude-haiku-4-5",
          input_tokens: 1_000_000, output_tokens: 0
        )
        expect(cost).to eq(0.80)
      end

      it "rounds to 6 decimals" do
        cost = described_class.estimate(
          provider: "openai", model: "gpt-4o-mini",
          input_tokens: 1, output_tokens: 1
        )
        # Result is tiny but nonzero
        expect(cost).to be > 0.0
        expect(cost.to_s.split(".").last.length).to be <= 6
      end
    end

    context "unknown models" do
      it "returns nil for an unknown model with no override" do
        cost = described_class.estimate(
          provider: "openai", model: "future-model-99",
          input_tokens: 100, output_tokens: 50
        )
        expect(cost).to be_nil
      end

      it "returns nil when model is nil" do
        cost = described_class.estimate(
          provider: "openai", model: nil,
          input_tokens: 100, output_tokens: 50
        )
        expect(cost).to be_nil
      end

      it "returns nil when model is empty string" do
        cost = described_class.estimate(
          provider: "openai", model: "",
          input_tokens: 100, output_tokens: 50
        )
        expect(cost).to be_nil
      end
    end

    context "missing token counts" do
      it "returns nil when both token counts are nil" do
        cost = described_class.estimate(
          provider: "openai", model: "gpt-4o",
          input_tokens: nil, output_tokens: nil
        )
        expect(cost).to be_nil
      end

      it "treats a nil input_tokens as zero if output_tokens is present" do
        # Useful for streaming responses where only output tokens are emitted
        cost = described_class.estimate(
          provider: "anthropic", model: "claude-sonnet-4-6",
          input_tokens: nil, output_tokens: 1_000_000
        )
        expect(cost).to eq(15.0)
      end

      it "treats nil output_tokens as zero if input_tokens is present" do
        cost = described_class.estimate(
          provider: "anthropic", model: "claude-sonnet-4-6",
          input_tokens: 1_000_000, output_tokens: nil
        )
        expect(cost).to eq(3.0)
      end
    end

    context "user-supplied overrides" do
      it "uses override when set, ignoring the built-in table" do
        RailsErrorDashboard.configuration.llm_pricing_overrides = {
          "claude-sonnet-4-6" => { input: 99.0, output: 99.0 }
        }
        cost = described_class.estimate(
          provider: "anthropic", model: "claude-sonnet-4-6",
          input_tokens: 1_000_000, output_tokens: 0
        )
        expect(cost).to eq(99.0)
      end

      it "adds entries for new models not in the built-in table" do
        RailsErrorDashboard.configuration.llm_pricing_overrides = {
          "custom-model-x" => { input: 1.0, output: 2.0 }
        }
        cost = described_class.estimate(
          provider: "self", model: "custom-model-x",
          input_tokens: 1_000_000, output_tokens: 1_000_000
        )
        expect(cost).to eq(3.0)
      end

      it "accepts string keys in override rate hash" do
        RailsErrorDashboard.configuration.llm_pricing_overrides = {
          "weird-model" => { "input" => 5.0, "output" => 10.0 }
        }
        cost = described_class.estimate(
          provider: "x", model: "weird-model",
          input_tokens: 1_000_000, output_tokens: 0
        )
        expect(cost).to eq(5.0)
      end

      it "matches override model name case-insensitively" do
        RailsErrorDashboard.configuration.llm_pricing_overrides = {
          "Custom-Model" => { input: 7.0, output: 0.0 }
        }
        cost = described_class.estimate(
          provider: "x", model: "custom-model",
          input_tokens: 1_000_000, output_tokens: 0
        )
        expect(cost).to eq(7.0)
      end
    end

    context "safety" do
      it "never raises on weird input" do
        expect {
          described_class.estimate(
            provider: nil, model: Object.new,
            input_tokens: "not-a-number", output_tokens: { weird: true }
          )
        }.not_to raise_error
      end

      it "returns nil when an override is malformed" do
        RailsErrorDashboard.configuration.llm_pricing_overrides = {
          "broken-model" => "not a hash"
        }
        cost = described_class.estimate(
          provider: "x", model: "broken-model",
          input_tokens: 100, output_tokens: 50
        )
        expect(cost).to be_nil
      end
    end
  end

  describe "::PRICES" do
    it "is frozen" do
      expect(described_class::PRICES).to be_frozen
    end

    it "covers the headline models from each major provider" do
      expect(described_class::PRICES).to include(
        "claude-sonnet-4-6", "claude-opus-4-7", "gpt-4o", "gpt-4o-mini", "gemini-2.5-pro"
      )
    end
  end
end
