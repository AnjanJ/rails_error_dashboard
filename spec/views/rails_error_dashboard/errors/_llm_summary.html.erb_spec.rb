# frozen_string_literal: true

require "rails_helper"

RSpec.describe "rails_error_dashboard/errors/_llm_summary.html.erb", type: :view do
  before(:all) do
    ActionView::TestCase::TestController.helper(RailsErrorDashboard::ApplicationHelper)
  end

  before do
    RailsErrorDashboard.configuration.enable_breadcrumbs = true
    RailsErrorDashboard.configuration.enable_llm_observability = true
  end

  after do
    RailsErrorDashboard.reset_configuration!
  end

  def render_partial(error)
    render template: "rails_error_dashboard/errors/_llm_summary", locals: { error: error }
  rescue ActionView::MissingTemplate
    render partial: "rails_error_dashboard/errors/llm_summary", locals: { error: error }
  end

  let(:llm_chat_crumb) do
    {
      "t" => 1, "c" => "llm", "m" => "openai · gpt-4o-mini", "d" => 421.5,
      "meta" => {
        "provider" => "openai", "model" => "gpt-4o-mini", "status" => "success",
        "input_tokens" => "100", "output_tokens" => "20", "cost_usd" => "0.0005"
      }
    }
  end

  let(:llm_chat_crumb_b) do
    {
      "t" => 2, "c" => "llm", "m" => "anthropic · claude-sonnet-4-5", "d" => 800.0,
      "meta" => {
        "provider" => "anthropic", "model" => "claude-sonnet-4-5", "status" => "success",
        "input_tokens" => "500", "output_tokens" => "100", "cost_usd" => "0.0050"
      }
    }
  end

  let(:llm_tool_crumb) do
    {
      "t" => 3, "c" => "llm_tool", "m" => "tool: get_weather", "d" => 12.3,
      "meta" => { "tool_name" => "get_weather" }
    }
  end

  let(:llm_error_crumb) do
    {
      "t" => 4, "c" => "llm", "m" => "anthropic · claude-sonnet-4-5 · timeout", "d" => 30_000.0,
      "meta" => {
        "provider" => "anthropic", "model" => "claude-sonnet-4-5", "status" => "timeout",
        "error_class" => "Net::OpenTimeout"
      }
    }
  end

  let(:error) { create(:error_log, breadcrumbs: breadcrumbs_json) }

  context "with a single LLM chat call" do
    let(:breadcrumbs_json) { [ llm_chat_crumb ].to_json }

    it "renders the card with the correct call count" do
      render_partial(error)
      expect(rendered).to include('id="section-llm-summary"')
      expect(rendered).to include("LLM Calls")
      expect(rendered).to match(/<span class="badge bg-info text-dark">1<\/span>/)
    end

    it "renders total tokens with delimiters" do
      render_partial(error)
      expect(rendered).to include("120")  # 100 + 20
    end

    it "renders total cost formatted to four decimals" do
      render_partial(error)
      expect(rendered).to include("$0.0005")
    end

    it "renders input/output breakdown" do
      render_partial(error)
      expect(rendered).to include("Input")
      expect(rendered).to include("Output")
      expect(rendered).to include("<strong>100</strong>")
      expect(rendered).to include("<strong>20</strong>")
    end

    it "renders the by_model row" do
      render_partial(error)
      expect(rendered).to include("By model")
      expect(rendered).to include("gpt-4o-mini")
      expect(rendered).to include("openai")
    end

    it "does not use word-break: break-all on the model name (Bug 3 regression)" do
      # v0.7.0 used `word-break: break-all` which split "gemini-2.5-flash"
      # mid-word as "gemini-2.5-fla" + "sh". Fix uses overflow-wrap: anywhere,
      # which respects natural break points (hyphens) and only breaks mid-word
      # as a last resort.
      render_partial(error)
      expect(rendered).not_to include("word-break: break-all")
      expect(rendered).to include("overflow-wrap: anywhere")
    end

    it "adds a title tooltip showing the full provider · model string" do
      render_partial(error)
      expect(rendered).to include('title="openai · gpt-4o-mini"')
    end

    it "does not render an error alert when all calls succeed" do
      render_partial(error)
      expect(rendered).not_to include("failed call")
      expect(rendered).not_to include("alert-danger")
    end
  end

  context "with two providers and tool calls" do
    let(:breadcrumbs_json) { [ llm_chat_crumb, llm_chat_crumb_b, llm_tool_crumb ].to_json }

    it "shows the combined call count" do
      render_partial(error)
      expect(rendered).to match(/<span class="badge bg-info text-dark">2<\/span>/)
    end

    it "renders the tool calls row when tool calls exist" do
      render_partial(error)
      expect(rendered).to include("Tool calls")
      expect(rendered).to include("<strong>1</strong>")
    end

    it "lists both models in the by_model breakdown" do
      render_partial(error)
      expect(rendered).to include("gpt-4o-mini")
      expect(rendered).to include("claude-sonnet-4-5")
    end

    it "totals the cost across providers" do
      render_partial(error)
      # 0.0005 + 0.0050 = 0.0055
      expect(rendered).to include("$0.0055")
    end
  end

  context "with a failed call" do
    let(:breadcrumbs_json) { [ llm_chat_crumb, llm_error_crumb ].to_json }

    it "renders the error count badge" do
      render_partial(error)
      expect(rendered).to include("Errors")
      expect(rendered).to match(/<span class="badge bg-danger">1<\/span>/)
    end

    it "renders the danger alert message" do
      render_partial(error)
      expect(rendered).to include("alert-danger")
      expect(rendered).to include("1 failed call")
    end
  end

  context "with no LLM breadcrumbs" do
    let(:breadcrumbs_json) do
      [ { "t" => 1, "c" => "sql", "m" => "SELECT 1", "d" => 1.0 } ].to_json
    end

    it "renders nothing" do
      render_partial(error)
      expect(rendered).not_to include("section-llm-summary")
      expect(rendered).not_to include("LLM Calls")
    end
  end

  context "with no breadcrumbs at all" do
    let(:error) { create(:error_log, breadcrumbs: nil) }

    it "renders nothing" do
      render_partial(error)
      expect(rendered).not_to include("section-llm-summary")
    end
  end

  context "when enable_llm_observability is off" do
    let(:breadcrumbs_json) { [ llm_chat_crumb ].to_json }

    before do
      RailsErrorDashboard.configuration.enable_llm_observability = false
    end

    it "renders nothing even when LLM breadcrumbs are present" do
      render_partial(error)
      expect(rendered).not_to include("section-llm-summary")
    end
  end

  context "when breadcrumbs is invalid JSON" do
    let(:breadcrumbs_json) { "not-json" }

    it "renders nothing without raising" do
      expect { render_partial(error) }.not_to raise_error
      expect(rendered).not_to include("section-llm-summary")
    end
  end

  context "with a chat call that has zero cost" do
    let(:llm_zero_cost) do
      {
        "t" => 1, "c" => "llm", "m" => "ollama · llama3", "d" => 50.0,
        "meta" => {
          "provider" => "ollama", "model" => "llama3", "status" => "success",
          "input_tokens" => "10", "output_tokens" => "5", "cost_usd" => "0.0"
        }
      }
    end
    let(:breadcrumbs_json) { [ llm_zero_cost ].to_json }

    it "renders -- for the cost stat instead of $0.0000" do
      render_partial(error)
      expect(rendered).to match(/<span class="text-muted">--<\/span>/)
    end

    it "omits the cost suffix from the by_model row when cost is zero" do
      render_partial(error)
      # by_model row should still appear, but without "· $0.0000"
      expect(rendered).to include("llama3")
      expect(rendered).not_to include("· $0.0000")
    end
  end
end
