# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::LlmHealthSummary do
  def breadcrumbs_json(*crumbs)
    crumbs.to_json
  end

  def llm_crumb(provider: "anthropic", model: "claude-3-5-sonnet", status: "success",
                input_tokens: nil, output_tokens: nil, duration_ms: nil,
                cost_usd: nil, error_class: nil)
    {
      "c" => "llm",
      "m" => "#{provider} · #{model}",
      "meta" => {
        "provider" => provider,
        "model" => model,
        "status" => status,
        "input_tokens" => input_tokens,
        "output_tokens" => output_tokens,
        "duration_ms" => duration_ms,
        "cost_usd" => cost_usd,
        "error_class" => error_class
      }.compact
    }
  end

  def tool_crumb(provider: "anthropic", model: "claude-3-5-sonnet", tool_name: "search_db", duration_ms: nil)
    {
      "c" => "llm_tool",
      "m" => "tool: #{tool_name}",
      "meta" => {
        "provider" => provider,
        "model" => model,
        "status" => "success",
        "tool_name" => tool_name,
        "duration_ms" => duration_ms
      }.compact
    }
  end

  def sql_crumb(message = "SELECT 1")
    { "c" => "sql", "m" => message, "d" => 1.2 }
  end

  describe ".call" do
    it "returns empty models when no errors exist" do
      result = described_class.call(30)
      expect(result[:models]).to eq([])
      expect(result[:totals][:total_calls]).to eq(0)
      expect(result[:totals][:model_count]).to eq(0)
    end

    it "returns empty models when errors have no breadcrumbs" do
      create(:error_log, breadcrumbs: nil, occurred_at: 1.day.ago)
      result = described_class.call(30)
      expect(result[:models]).to eq([])
    end

    it "returns empty models when breadcrumbs have no llm crumbs" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(sql_crumb),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:models]).to eq([])
    end

    it "groups calls by provider+model" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          llm_crumb(provider: "anthropic", model: "claude-3-5-sonnet"),
          llm_crumb(provider: "openai",    model: "gpt-4o-mini"),
          llm_crumb(provider: "anthropic", model: "claude-3-5-sonnet")
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:models].size).to eq(2)

      claude = result[:models].find { |m| m[:model] == "claude-3-5-sonnet" }
      gpt = result[:models].find { |m| m[:model] == "gpt-4o-mini" }

      expect(claude[:provider]).to eq("anthropic")
      expect(claude[:call_count]).to eq(2)
      expect(gpt[:call_count]).to eq(1)
    end

    it "uses 'unknown' when provider or model is missing" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          { "c" => "llm", "m" => "?", "meta" => {} }
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:models].first[:provider]).to eq("unknown")
      expect(result[:models].first[:model]).to eq("unknown")
    end

    it "tracks tool calls in a separate counter" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          llm_crumb,
          llm_crumb,
          tool_crumb,
          tool_crumb,
          tool_crumb
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      entry = result[:models].first
      expect(entry[:call_count]).to eq(2)
      expect(entry[:tool_call_count]).to eq(3)
    end

    it "counts error and timeout statuses toward error_count" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          llm_crumb(status: "success"),
          llm_crumb(status: "success"),
          llm_crumb(status: "error", error_class: "Anthropic::RateLimitError"),
          llm_crumb(status: "timeout", error_class: "Net::ReadTimeout")
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      entry = result[:models].first
      expect(entry[:error_count]).to eq(2)
      expect(entry[:call_count]).to eq(4)
      expect(entry[:error_rate]).to eq(50.0)
    end

    it "computes severity from error rate" do
      # 1 of 10 = 10% → danger
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          *([ llm_crumb(status: "success") ] * 9),
          llm_crumb(status: "error", error_class: "X")
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:models].first[:error_rate]).to eq(10.0)
      expect(result[:models].first[:severity]).to eq(:danger)
    end

    it "computes warning severity between 5% and 10%" do
      # 3 of 50 = 6%
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          *([ llm_crumb(status: "success") ] * 47),
          *([ llm_crumb(status: "error", error_class: "X") ] * 3)
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:models].first[:error_rate]).to eq(6.0)
      expect(result[:models].first[:severity]).to eq(:warning)
    end

    it "computes success severity below 5%" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          *([ llm_crumb(status: "success") ] * 99),
          llm_crumb(status: "error", error_class: "X")
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:models].first[:error_rate]).to eq(1.0)
      expect(result[:models].first[:severity]).to eq(:success)
    end

    it "computes avg tokens skipping nil values" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          llm_crumb(input_tokens: 100, output_tokens: 50),
          llm_crumb(input_tokens: 200, output_tokens: 100),
          llm_crumb(input_tokens: nil, output_tokens: nil)
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      entry = result[:models].first
      expect(entry[:avg_input_tokens]).to eq(150)
      expect(entry[:avg_output_tokens]).to eq(75)
    end

    it "returns nil avg tokens when no token data" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(llm_crumb),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      entry = result[:models].first
      expect(entry[:avg_input_tokens]).to be_nil
      expect(entry[:avg_output_tokens]).to be_nil
    end

    it "computes avg latency from duration_ms" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          llm_crumb(duration_ms: 1000),
          llm_crumb(duration_ms: 2000),
          llm_crumb(duration_ms: 3000)
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:models].first[:avg_duration_ms]).to eq(2000.0)
    end

    it "sums cost_usd across calls and rounds to 4 decimals" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          llm_crumb(cost_usd: 0.0125),
          llm_crumb(cost_usd: 0.0250),
          llm_crumb(cost_usd: 0.0050)
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:models].first[:cost_usd_sum]).to eq(0.0425)
    end

    it "tracks top error class with count" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          llm_crumb(status: "error", error_class: "Anthropic::RateLimitError"),
          llm_crumb(status: "error", error_class: "Anthropic::RateLimitError"),
          llm_crumb(status: "error", error_class: "Anthropic::RateLimitError"),
          llm_crumb(status: "error", error_class: "Net::ReadTimeout")
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      entry = result[:models].first
      expect(entry[:top_error_class]).to eq("Anthropic::RateLimitError")
      expect(entry[:top_error_class_count]).to eq(3)
    end

    it "tracks unique error count per model" do
      e1 = create(:error_log,
        breadcrumbs: breadcrumbs_json(llm_crumb, llm_crumb),
        occurred_at: 1.day.ago)
      e2 = create(:error_log,
        breadcrumbs: breadcrumbs_json(llm_crumb),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      entry = result[:models].first
      expect(entry[:unique_error_count]).to eq(2)
      expect(entry[:error_ids]).to contain_exactly(e1.id, e2.id)
    end

    it "sorts by error rate desc, then unique error count desc, then call count desc" do
      # Model A: 50% error rate
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          llm_crumb(provider: "openai", model: "gpt-3", status: "success"),
          llm_crumb(provider: "openai", model: "gpt-3", status: "error", error_class: "X")
        ),
        occurred_at: 1.day.ago)

      # Model B: 0% error rate, 10 calls
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          *([ llm_crumb(provider: "anthropic", model: "claude-3-5-sonnet") ] * 10)
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:models].first[:model]).to eq("gpt-3")
      expect(result[:models].last[:model]).to eq("claude-3-5-sonnet")
    end

    it "tracks last_seen as max occurred_at" do
      old = 5.days.ago
      recent = 1.day.ago
      create(:error_log, breadcrumbs: breadcrumbs_json(llm_crumb), occurred_at: old)
      create(:error_log, breadcrumbs: breadcrumbs_json(llm_crumb), occurred_at: recent)

      result = described_class.call(30)
      expect(result[:models].first[:last_seen]).to be_within(1.second).of(recent)
    end

    it "respects time range" do
      create(:error_log, breadcrumbs: breadcrumbs_json(llm_crumb), occurred_at: 5.days.ago)
      create(:error_log, breadcrumbs: breadcrumbs_json(llm_crumb), occurred_at: 60.days.ago)

      result = described_class.call(7)
      expect(result[:models].size).to eq(1)
      expect(result[:models].first[:unique_error_count]).to eq(1)
    end

    it "filters by application_id" do
      app1 = create(:application, name: "App1")
      app2 = create(:application, name: "App2")

      create(:error_log,
        breadcrumbs: breadcrumbs_json(llm_crumb),
        application: app1, occurred_at: 1.day.ago)
      create(:error_log,
        breadcrumbs: breadcrumbs_json(llm_crumb),
        application: app2, occurred_at: 1.day.ago)

      result = described_class.call(30, application_id: app1.id)
      expect(result[:models].size).to eq(1)
      expect(result[:models].first[:unique_error_count]).to eq(1)
    end

    it "handles malformed breadcrumbs JSON gracefully" do
      create(:error_log, breadcrumbs: "not json{", occurred_at: 1.day.ago)
      result = described_class.call(30)
      expect(result[:models]).to eq([])
    end

    it "totals: counts calls, tool calls, models, errors, cost across all models" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          llm_crumb(provider: "openai", model: "gpt-4o", cost_usd: 0.10),
          llm_crumb(provider: "openai", model: "gpt-4o", cost_usd: 0.20, status: "error", error_class: "X"),
          llm_crumb(provider: "anthropic", model: "claude-3-5-sonnet", cost_usd: 0.30),
          tool_crumb(provider: "openai", model: "gpt-4o")
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      totals = result[:totals]

      expect(totals[:total_calls]).to eq(3)
      expect(totals[:total_tool_calls]).to eq(1)
      expect(totals[:model_count]).to eq(2)
      expect(totals[:unique_error_count]).to eq(1)
      expect(totals[:total_cost_usd]).to eq(0.60)
      # 1 error / 4 attempts = 25%
      expect(totals[:error_rate]).to eq(25.0)
    end

    it "totals: returns zeros when no data" do
      result = described_class.call(30)
      totals = result[:totals]

      expect(totals[:total_calls]).to eq(0)
      expect(totals[:total_tool_calls]).to eq(0)
      expect(totals[:model_count]).to eq(0)
      expect(totals[:unique_error_count]).to eq(0)
      expect(totals[:error_rate]).to eq(0.0)
      expect(totals[:total_cost_usd]).to eq(0.0)
    end

    it "drops accumulator-only keys from the result" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(llm_crumb(input_tokens: 100, output_tokens: 50, duration_ms: 1000)),
        occurred_at: 1.day.ago)

      entry = described_class.call(30)[:models].first
      expect(entry).not_to have_key(:input_tokens_sum)
      expect(entry).not_to have_key(:input_tokens_seen)
      expect(entry).not_to have_key(:duration_sum)
      expect(entry).not_to have_key(:duration_seen)
      expect(entry).not_to have_key(:error_classes)
    end
  end
end
