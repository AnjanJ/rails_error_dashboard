# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Estimates USD cost for an LLM call given provider, model, and token counts.
    #
    # Prices are stored as USD per 1,000,000 tokens (the canonical unit used
    # by OpenAI, Anthropic, and Google in their pricing pages).
    #
    # IMPORTANT: This is a best-effort estimate using a hardcoded snapshot.
    # Prices change frequently. Users SHOULD configure overrides via
    # `config.llm_pricing_overrides` for production accuracy.
    #
    # Returns nil for unknown models (no override AND not in the built-in table).
    # Never raises — wrapped in rescue.
    class LlmCostEstimator
      # Prices last refreshed: 2026-05 (approximate, see provider pricing pages).
      # Format: { "model-name" => { input: usd_per_1m, output: usd_per_1m } }
      PRICES = {
        # Anthropic
        "claude-opus-4-7" => { input: 15.0, output: 75.0 },
        "claude-sonnet-4-6" => { input: 3.0, output: 15.0 },
        "claude-haiku-4-5" => { input: 0.80, output: 4.0 },

        # OpenAI
        "gpt-4o" => { input: 2.50, output: 10.0 },
        "gpt-4o-mini" => { input: 0.15, output: 0.60 },
        "gpt-4-turbo" => { input: 10.0, output: 30.0 },
        "o1" => { input: 15.0, output: 60.0 },
        "o1-mini" => { input: 3.0, output: 12.0 },

        # Google
        "gemini-2.5-pro" => { input: 1.25, output: 5.0 },
        "gemini-2.5-flash" => { input: 0.075, output: 0.30 }
      }.freeze

      # @param provider [String, Symbol] currently informational only (not used in lookup)
      # @param model [String] model identifier — matched case-insensitively against PRICES
      # @param input_tokens [Integer, nil]
      # @param output_tokens [Integer, nil]
      # @return [Float, nil] estimated USD cost, or nil if model unknown / tokens missing
      def self.estimate(provider:, model:, input_tokens:, output_tokens:)
        return nil if model.nil? || model.to_s.empty?
        return nil if input_tokens.nil? && output_tokens.nil?

        rate = lookup_rate(model.to_s)
        return nil unless rate

        in_tokens = input_tokens.to_i
        out_tokens = output_tokens.to_i

        cost = (in_tokens * rate[:input] + out_tokens * rate[:output]) / 1_000_000.0
        cost.round(6)
      rescue
        nil
      end

      def self.lookup_rate(model)
        # User-configured override wins. Match case-insensitively on the model key.
        overrides = RailsErrorDashboard.configuration.llm_pricing_overrides || {}
        normalized = model.downcase

        overrides.each do |key, rate|
          return symbolize_rate(rate) if key.to_s.downcase == normalized
        end

        PRICES.each do |key, rate|
          return rate if key.downcase == normalized
        end

        nil
      end

      def self.symbolize_rate(rate)
        return nil unless rate.is_a?(Hash)
        {
          input: rate[:input] || rate["input"],
          output: rate[:output] || rate["output"]
        }
      end

      private_class_method :lookup_rate, :symbolize_rate
    end
  end
end
