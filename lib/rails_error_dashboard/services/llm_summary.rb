# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Roll up LLM breadcrumbs into a per-error summary.
    #
    # Operates on already-captured breadcrumb data at display time only —
    # zero runtime cost. Same pattern as CacheAnalyzer / NplusOneDetector.
    #
    # NOTE on string coercion: BreadcrumbCollector#truncate_metadata stringifies
    # every metadata value (input_tokens "42", cost_usd "0.0003", etc.). This
    # service does the `.to_i` / `.to_f` itself so callers don't have to.
    #
    # @example
    #   RailsErrorDashboard::Services::LlmSummary.call(breadcrumbs)
    #   # => { total_calls: 3, total_tool_calls: 2, total_input_tokens: 1450,
    #   #      total_output_tokens: 220, total_tokens: 1670,
    #   #      total_cost_usd: 0.00821, error_count: 1, total_duration_ms: 4321.5,
    #   #      providers: ["anthropic", "openai"],
    #   #      by_model: [ { provider: "openai", model: "gpt-4o-mini",
    #   #                    calls: 2, tokens: 800, cost_usd: 0.0042 }, ... ] }
    class LlmSummary
      # @param breadcrumbs [Array<Hash>] Parsed breadcrumb array
      # @return [Hash, nil] Summary hash, or nil if no LLM breadcrumbs present
      def self.call(breadcrumbs)
        return nil unless breadcrumbs.is_a?(Array)

        llm_crumbs = breadcrumbs.select { |c| c.is_a?(Hash) && c["c"] == "llm" }
        tool_crumbs = breadcrumbs.select { |c| c.is_a?(Hash) && c["c"] == "llm_tool" }
        return nil if llm_crumbs.empty? && tool_crumbs.empty?

        total_input = 0
        total_output = 0
        total_cost = 0.0
        total_duration = 0.0
        error_count = 0
        providers = {}
        by_model = {}

        llm_crumbs.each do |crumb|
          meta = crumb["meta"].is_a?(Hash) ? crumb["meta"] : {}
          provider = meta["provider"].to_s
          model = meta["model"].to_s
          input = meta["input_tokens"].to_i
          output = meta["output_tokens"].to_i
          cost = meta["cost_usd"].to_f
          duration = crumb["d"].to_f
          status = meta["status"].to_s

          total_input += input
          total_output += output
          total_cost += cost
          total_duration += duration
          error_count += 1 unless status == "success" || status == ""

          providers[provider] = true unless provider.empty?

          key = [ provider, model ]
          by_model[key] ||= { provider: provider, model: model, calls: 0, tokens: 0, cost_usd: 0.0 }
          by_model[key][:calls] += 1
          by_model[key][:tokens] += input + output
          by_model[key][:cost_usd] += cost
        end

        # Tool calls also contribute to duration (visible request impact)
        tool_crumbs.each do |crumb|
          total_duration += crumb["d"].to_f
        end

        {
          total_calls: llm_crumbs.size,
          total_tool_calls: tool_crumbs.size,
          total_input_tokens: total_input,
          total_output_tokens: total_output,
          total_tokens: total_input + total_output,
          total_cost_usd: total_cost.round(6),
          error_count: error_count,
          total_duration_ms: total_duration.round(1),
          providers: providers.keys.sort,
          by_model: by_model.values.sort_by { |row| -row[:calls] }.map { |row|
            row[:cost_usd] = row[:cost_usd].round(6)
            row
          }
        }
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] LlmSummary.call failed: #{e.message}")
        nil
      end
    end
  end
end
