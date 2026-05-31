# frozen_string_literal: true

require "rails_helper"

RSpec.describe "rails_error_dashboard/errors/_breadcrumbs_group.html.erb", type: :view do
  # The engine's ApplicationHelper is not picked up by ActionView in isolated view
  # specs (the controller wired in by RSpec's `:view` type is host-app
  # ApplicationController, which does not `helper :all` into the engine namespace).
  # Include it manually so `breadcrumb_badge_color` resolves.
  before(:all) do
    ActionView::TestCase::TestController.helper(RailsErrorDashboard::ApplicationHelper)
  end

  before do
    RailsErrorDashboard.configuration.enable_breadcrumbs = true
  end

  after do
    RailsErrorDashboard.reset_configuration!
  end

  # The partial sits inside the engine namespace; tell ActionView the lookup root
  # so `render "breadcrumbs_group"` style refs from siblings keep working in
  # production code, while this spec resolves the full template path explicitly.
  def render_partial(error)
    render template: "rails_error_dashboard/errors/_breadcrumbs_group", locals: { error: error }
  rescue ActionView::MissingTemplate
    # Fallback for environments that route the underscore-prefixed name as a partial
    render partial: "rails_error_dashboard/errors/breadcrumbs_group", locals: { error: error }
  end

  let(:llm_chat_crumb) do
    {
      t: 1700000000000, c: "llm", m: "openai · gpt-4o-mini · in:42/out:7", d: 421.5,
      meta: {
        "provider" => "openai", "model" => "gpt-4o-mini", "status" => "success",
        "input_tokens" => "42", "output_tokens" => "7",
        "duration_ms" => "421.5", "cost_usd" => "0.0003"
      }
    }
  end

  let(:llm_tool_crumb) do
    {
      t: 1700000000100, c: "llm_tool", m: "tool: get_weather", d: 12.3,
      meta: {
        "tool_name" => "get_weather",
        "tool_arguments" => '{"location":"SF"}',
        "tool_result" => "65F sunny"
      }
    }
  end

  let(:llm_error_crumb) do
    {
      t: 1700000000200, c: "llm", m: "anthropic · claude-sonnet-4-5 · timeout", d: 30_000.0,
      meta: {
        "provider" => "anthropic", "model" => "claude-sonnet-4-5", "status" => "timeout",
        "error_class" => "Net::OpenTimeout", "error_message" => "execution expired"
      }
    }
  end

  let(:error) do
    create(:error_log, breadcrumbs: breadcrumbs_json)
  end

  context "with a single LLM chat call" do
    let(:breadcrumbs_json) { [ llm_chat_crumb ].to_json }

    it "renders the breadcrumbs card" do
      render_partial(error)
      expect(rendered).to include("Breadcrumbs")
    end

    it "renders the llm badge with the info color" do
      render_partial(error)
      expect(rendered).to include('class="badge bg-info"')
      expect(rendered).to match(/<span class="badge bg-info">llm<\/span>/)
    end

    it "renders provider, model, tokens, and cost in the meta line" do
      render_partial(error)
      expect(rendered).to include("openai")
      expect(rendered).to include("gpt-4o-mini")
      expect(rendered).to include("in:<strong>42</strong>")
      expect(rendered).to include("out:<strong>7</strong>")
      expect(rendered).to include("$0.000300")
    end

    it "does not render a status pill on success" do
      render_partial(error)
      expect(rendered).not_to match(/<span class="badge bg-danger">success<\/span>/)
    end
  end

  context "with a chat followed by a tool call" do
    let(:breadcrumbs_json) { [ llm_chat_crumb, llm_tool_crumb ].to_json }

    it "renders both rows" do
      render_partial(error)
      expect(rendered).to include('class="badge bg-info">llm<')
      expect(rendered).to include('class="badge bg-warning">llm_tool<')
    end

    it "nests the tool row visually under the chat row" do
      render_partial(error)
      expect(rendered).to include('class="llm-tool-row"')
      expect(rendered).to include("padding-left: 2rem")
      expect(rendered).to include("bi-arrow-return-right")
    end

    it "renders tool name, arguments, and result" do
      render_partial(error)
      expect(rendered).to include("get_weather")
      expect(rendered).to include("location")
      expect(rendered).to include("65F sunny")
    end
  end

  context "with a tool call NOT preceded by an LLM chat row" do
    let(:breadcrumbs_json) { [ { t: 1, c: "sql", m: "SELECT 1" }, llm_tool_crumb ].to_json }

    it "does not apply nested indentation when the prior row is non-LLM" do
      render_partial(error)
      expect(rendered).not_to include('class="llm-tool-row"')
      expect(rendered).not_to include("padding-left: 2rem")
    end
  end

  context "with a failed LLM call" do
    let(:breadcrumbs_json) { [ llm_error_crumb ].to_json }

    it "renders the failure status pill" do
      render_partial(error)
      expect(rendered).to match(/<span class="badge bg-danger">timeout<\/span>/)
    end

    it "renders the error class and message in the danger color" do
      render_partial(error)
      expect(rendered).to include("text-danger")
      expect(rendered).to include("Net::OpenTimeout")
      expect(rendered).to include("execution expired")
    end
  end

  context "with non-LLM breadcrumbs only" do
    let(:breadcrumbs_json) do
      [ { t: 1, c: "sql", m: "SELECT * FROM users", d: 2.1, meta: { "name" => "User Load" } } ].to_json
    end

    it "still falls back to the generic meta.inspect rendering for unknown categories" do
      render_partial(error)
      expect(rendered).to include("User Load")
    end

    it "does not render LLM-specific markup" do
      render_partial(error)
      expect(rendered).not_to include("llm-tool-row")
      expect(rendered).not_to include("bi-cpu")
    end
  end

  context "when breadcrumbs is invalid JSON" do
    let(:breadcrumbs_json) { "not-json" }

    it "renders nothing without raising" do
      expect { render_partial(error) }.not_to raise_error
    end
  end

  context "when enable_breadcrumbs is disabled" do
    let(:breadcrumbs_json) { [ llm_chat_crumb ].to_json }

    before { RailsErrorDashboard.configuration.enable_breadcrumbs = false }

    it "renders nothing user-visible" do
      render_partial(error)
      # The static HTML comment at the top of the partial is still emitted, but
      # nothing inside the guard is — assert on visible markup absence.
      expect(rendered).not_to include('<div class="card mb-4" id="section-breadcrumbs">')
      expect(rendered).not_to include("badge bg-info")
      expect(rendered).not_to include("openai")
      expect(rendered).not_to include("gpt-4o-mini")
    end
  end
end
