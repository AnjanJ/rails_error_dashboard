# frozen_string_literal: true

require "rails_helper"

RSpec.describe "LLM Health Summary page", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.enable_breadcrumbs = false
    RailsErrorDashboard.configuration.enable_llm_observability = false
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

  describe "GET /error_dashboard/errors/llm_health_summary" do
    context "when LLM observability is disabled" do
      before do
        RailsErrorDashboard.configuration.enable_breadcrumbs = true
        RailsErrorDashboard.configuration.enable_llm_observability = false
      end

      it "returns 200 with the disabled-feature empty state" do
        get "/error_dashboard/errors/llm_health_summary"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("LLM Observability Not Enabled")
        expect(response.body).to include("enable_llm_observability = true")
      end
    end

    context "when breadcrumbs are disabled but llm observability is on" do
      before do
        RailsErrorDashboard.configuration.enable_breadcrumbs = false
        # Configuration.validate! auto-disables llm_observability when
        # breadcrumbs are off, but we may still hit the controller during
        # ad-hoc toggling. Treat it as disabled.
        RailsErrorDashboard.configuration.enable_llm_observability = true
      end

      it "returns 200 with the disabled-feature empty state" do
        get "/error_dashboard/errors/llm_health_summary"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("LLM Observability Not Enabled")
      end
    end

    context "when both are enabled" do
      before do
        RailsErrorDashboard.configuration.enable_breadcrumbs = true
        RailsErrorDashboard.configuration.enable_llm_observability = true
      end

      it "returns 200" do
        get "/error_dashboard/errors/llm_health_summary"
        expect(response).to have_http_status(:ok)
      end

      it "shows the no-data empty state with all three instrumentation paths" do
        get "/error_dashboard/errors/llm_health_summary"
        expect(response.body).to include("No LLM Calls Detected")
        expect(response.body).to include("OpenTelemetry")
        expect(response.body).to include("Faraday")
        expect(response.body).to include("Manual")
        expect(response.body).to include("red.llm_call")
      end

      it "displays per-model rows with provider, calls, and cost" do
        create(:error_log,
          application: application,
          breadcrumbs: [
            llm_crumb(provider: "anthropic", model: "claude-3-5-sonnet",
                      input_tokens: 1200, output_tokens: 350, cost_usd: 0.0125)
          ].to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/llm_health_summary"
        expect(response.body).to include("anthropic")
        expect(response.body).to include("claude-3-5-sonnet")
        expect(response.body).to include("1,200")  # avg input tokens, formatted
      end

      it "displays summary cards with totals" do
        create(:error_log,
          application: application,
          breadcrumbs: [ llm_crumb(cost_usd: 0.05) ].to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/llm_health_summary"
        expect(response.body).to include("LLM Calls")
        expect(response.body).to include("Models")
        expect(response.body).to include("Total Cost")
        expect(response.body).to include("$0.05")
      end

      it "color-codes high error rate as danger" do
        # 10% error rate hits the danger threshold
        crumbs = ([ llm_crumb(status: "success") ] * 9) +
                 [ llm_crumb(status: "error", error_class: "Anthropic::RateLimitError") ]

        create(:error_log,
          application: application,
          breadcrumbs: crumbs.to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/llm_health_summary"
        expect(response.body).to include("bg-danger")
        expect(response.body).to include("10.0%")
        expect(response.body).to include("Anthropic::RateLimitError")
      end

      it "accepts days parameter" do
        get "/error_dashboard/errors/llm_health_summary", params: { days: 7 }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("7 Days")
      end

      it "scopes by application_id" do
        other_app = create(:application, name: "Other")
        create(:error_log,
          application: application,
          breadcrumbs: [ llm_crumb(model: "gpt-4o") ].to_json,
          occurred_at: 1.day.ago)
        create(:error_log,
          application: other_app,
          breadcrumbs: [ llm_crumb(model: "claude-3-5-sonnet") ].to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/llm_health_summary", params: { application_id: application.id }
        expect(response.body).to include("gpt-4o")
        expect(response.body).not_to include("claude-3-5-sonnet")
      end
    end
  end
end
