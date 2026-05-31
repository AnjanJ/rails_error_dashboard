# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Aggregate LLM call breadcrumbs across all errors, grouped by
    # "provider · model". Scans error_logs breadcrumbs JSON, filters for "llm"
    # and "llm_tool" category crumbs, and computes per-model stats: call count,
    # tool count, avg tokens, avg latency, error rate, cost, top error class.
    #
    # Sorted by error rate desc, then unique-error count desc, then call volume
    # desc — so the model causing the most errors floats to the top.
    #
    # Cost is read straight from the breadcrumb metadata (already estimated at
    # capture time by LlmCallSubscriber via LlmCostEstimator). No re-estimation.
    class LlmHealthSummary
      DANGER_THRESHOLD = 10.0  # error rate %
      WARNING_THRESHOLD = 5.0

      def self.call(days = 30, application_id: nil)
        new(days, application_id: application_id).call
      end

      # Public helper so controllers can render an empty-state shell without
      # running the query (e.g., when the feature is disabled).
      def self.blank_totals
        {
          total_calls: 0,
          total_tool_calls: 0,
          model_count: 0,
          unique_error_count: 0,
          error_rate: 0.0,
          total_cost_usd: 0.0
        }
      end

      def initialize(days = 30, application_id: nil)
        @days = days
        @application_id = application_id
        @start_date = days.days.ago
      end

      def call
        models = aggregated_models
        {
          models: models,
          totals: totals_for(models)
        }
      end

      private

      def base_query
        scope = ErrorLog.where("occurred_at >= ?", @start_date)
                        .where.not(breadcrumbs: nil)
        scope = scope.where(application_id: @application_id) if @application_id.present?
        scope
      end

      def aggregated_models
        results = {}

        base_query.select(:id, :breadcrumbs, :occurred_at).find_each(batch_size: 500) do |error_log|
          crumbs = parse_breadcrumbs(error_log.breadcrumbs)
          next if crumbs.empty?

          llm_crumbs = crumbs.select { |c| c["c"] == "llm" || c["c"] == "llm_tool" }
          next if llm_crumbs.empty?

          llm_crumbs.each do |crumb|
            meta = crumb["meta"] || {}
            provider = meta["provider"].to_s.presence || "unknown"
            model = meta["model"].to_s.presence || "unknown"
            key = "#{provider}·#{model}"

            results[key] ||= new_entry(provider, model)
            entry = results[key]

            if crumb["c"] == "llm_tool"
              entry[:tool_call_count] += 1
            else
              entry[:call_count] += 1
            end

            status = meta["status"].to_s
            entry[:error_count] += 1 if status == "error" || status == "timeout"

            # BreadcrumbCollector#truncate_metadata stringifies every metadata
            # value (input_tokens "42", cost_usd "0.0003", etc.), so we coerce
            # back to numeric here using the same pattern as LlmSummary. nil and
            # blank values skip the accumulator entirely so they don't pollute
            # averages.
            if (it = meta["input_tokens"]).present?
              entry[:input_tokens_sum] += it.to_i
              entry[:input_tokens_seen] += 1
            end
            if (ot = meta["output_tokens"]).present?
              entry[:output_tokens_sum] += ot.to_i
              entry[:output_tokens_seen] += 1
            end
            duration_raw = meta["duration_ms"] || crumb["d"]
            if duration_raw.present?
              d = duration_raw.to_f
              if d > 0
                entry[:duration_sum] += d
                entry[:duration_seen] += 1
              end
            end
            if (cost = meta["cost_usd"]).present?
              entry[:cost_usd_sum] += cost.to_f
            end

            if (err_class = meta["error_class"]).is_a?(String) && !err_class.empty?
              entry[:error_classes][err_class] = (entry[:error_classes][err_class] || 0) + 1
            end

            entry[:error_ids] << error_log.id
            entry[:last_seen] = [ entry[:last_seen], error_log.occurred_at ].compact.max
          end
        end

        finalize(results)
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] LlmHealthSummary query failed: #{e.class}: #{e.message}")
        []
      end

      def new_entry(provider, model)
        {
          provider: provider,
          model: model,
          call_count: 0,
          tool_call_count: 0,
          error_count: 0,
          input_tokens_sum: 0,
          input_tokens_seen: 0,
          output_tokens_sum: 0,
          output_tokens_seen: 0,
          duration_sum: 0.0,
          duration_seen: 0,
          cost_usd_sum: 0.0,
          error_classes: {},
          error_ids: [],
          last_seen: nil
        }
      end

      def finalize(results)
        results.values.each do |r|
          r[:error_ids] = r[:error_ids].uniq
          r[:unique_error_count] = r[:error_ids].size

          total_attempts = r[:call_count] + r[:tool_call_count]
          r[:error_rate] = total_attempts.positive? ? (r[:error_count].to_f / total_attempts * 100).round(2) : 0.0
          r[:severity] = severity_for(r[:error_rate])

          r[:avg_input_tokens] = avg(r[:input_tokens_sum], r[:input_tokens_seen])
          r[:avg_output_tokens] = avg(r[:output_tokens_sum], r[:output_tokens_seen])
          r[:avg_duration_ms] = r[:duration_seen].positive? ? (r[:duration_sum] / r[:duration_seen]).round(2) : nil
          r[:cost_usd_sum] = r[:cost_usd_sum].round(4)

          top_class, top_count = r[:error_classes].max_by { |_, c| c }
          r[:top_error_class] = top_class
          r[:top_error_class_count] = top_count

          # Drop accumulators — view doesn't need them
          r.delete(:input_tokens_sum)
          r.delete(:input_tokens_seen)
          r.delete(:output_tokens_sum)
          r.delete(:output_tokens_seen)
          r.delete(:duration_sum)
          r.delete(:duration_seen)
          r.delete(:error_classes)
        end

        results.values.sort_by { |r| [ -r[:error_rate], -r[:unique_error_count], -r[:call_count] ] }
      end

      def avg(sum, count)
        return nil if count.zero?
        (sum.to_f / count).round
      end

      def severity_for(error_rate)
        return :danger  if error_rate >= DANGER_THRESHOLD
        return :warning if error_rate >= WARNING_THRESHOLD
        :success
      end

      def totals_for(models)
        return blank_totals if models.empty? || !models.is_a?(Array)

        total_calls = models.sum { |m| m[:call_count] }
        total_tool_calls = models.sum { |m| m[:tool_call_count] }
        total_errors = models.sum { |m| m[:error_count] }
        total_attempts = total_calls + total_tool_calls
        unique_error_ids = models.flat_map { |m| m[:error_ids] }.uniq

        {
          total_calls: total_calls,
          total_tool_calls: total_tool_calls,
          model_count: models.size,
          unique_error_count: unique_error_ids.size,
          error_rate: total_attempts.positive? ? (total_errors.to_f / total_attempts * 100).round(2) : 0.0,
          total_cost_usd: models.sum { |m| m[:cost_usd_sum] }.round(4)
        }
      end

      def blank_totals
        self.class.blank_totals
      end

      def parse_breadcrumbs(raw)
        return [] if raw.blank?
        JSON.parse(raw)
      rescue JSON::ParserError
        []
      end
    end
  end
end
