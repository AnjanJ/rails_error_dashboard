# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Subscribers::LlmCallSubscriber do
  let(:collector) { RailsErrorDashboard::Services::BreadcrumbCollector }

  before do
    RailsErrorDashboard.configuration.enable_breadcrumbs = true
    RailsErrorDashboard.configuration.enable_llm_observability = true
    RailsErrorDashboard.configuration.breadcrumb_categories = nil
    collector.init_buffer
  end

  after do
    described_class.unsubscribe!
    collector.clear_buffer
    RailsErrorDashboard.reset_configuration!
  end

  describe ".subscribe!" do
    it "registers subscribers for both red.llm_call and red.llm_tool_call" do
      subscriptions = described_class.subscribe!
      expect(subscriptions).to be_an(Array)
      expect(subscriptions.size).to eq(2)
    end

    it "is idempotent — re-subscribing tears down the previous subscriptions" do
      described_class.subscribe!
      first = described_class.subscriptions

      described_class.subscribe!
      second = described_class.subscriptions

      # Same count, but different subscription objects (old ones unsubscribed).
      expect(second.size).to eq(2)
      expect(second).not_to eq(first)

      # And only one breadcrumb per emitted event, not two.
      ActiveSupport::Notifications.instrument("red.llm_call",
                                              provider: "openai", model: "gpt-4o-mini",
                                              input_tokens: 10, output_tokens: 5) { }
      expect(collector.current_breadcrumbs.size).to eq(1)
    end
  end

  describe ".unsubscribe!" do
    it "removes all subscriptions and stops capturing events" do
      described_class.subscribe!
      described_class.unsubscribe!
      expect(described_class.subscriptions).to be_empty

      ActiveSupport::Notifications.instrument("red.llm_call",
                                              provider: "openai", model: "gpt-4o-mini") { }
      expect(collector.current_breadcrumbs).to be_empty
    end
  end

  describe "red.llm_call event" do
    before { described_class.subscribe! }

    it "records an llm breadcrumb with provider, model, tokens, duration, cost" do
      ActiveSupport::Notifications.instrument("red.llm_call",
                                              provider: "openai",
                                              model: "gpt-4o-mini",
                                              input_tokens: 1000,
                                              output_tokens: 250) do
        sleep 0.001
      end

      crumb = collector.current_breadcrumbs.first
      expect(crumb[:c]).to eq("llm")
      expect(crumb[:m]).to include("openai", "gpt-4o-mini", "in:1000/out:250")
      expect(crumb[:d]).to be_a(Numeric)
      expect(crumb[:d]).to be > 0

      meta = crumb[:meta]
      expect(meta[:provider]).to eq("openai")
      expect(meta[:model]).to eq("gpt-4o-mini")
      expect(meta[:status]).to eq("success")
      expect(meta[:input_tokens]).to eq("1000")
      expect(meta[:output_tokens]).to eq("250")
      # 1000 * 0.15 + 250 * 0.60 = 150 + 150 = 300 / 1M = 0.0003
      expect(meta[:cost_usd]).to eq("0.0003")
    end

    it "accepts string-keyed payloads (some hosts use strings everywhere)" do
      ActiveSupport::Notifications.instrument("red.llm_call",
                                              "provider" => "anthropic",
                                              "model" => "claude-sonnet-4-6",
                                              "input_tokens" => 100,
                                              "output_tokens" => 50) { }

      meta = collector.current_breadcrumbs.first[:meta]
      expect(meta[:provider]).to eq("anthropic")
      expect(meta[:input_tokens]).to eq("100")
    end

    # README Path C documents this exact pattern — passing a mutable payload
    # Hash so token counts can be filled in AFTER the LLM call returns.
    # This test guards the documented pattern against accidental regression.
    it "sees payload values mutated inside the instrument block" do
      payload = { provider: "anthropic", model: "claude-sonnet-4-6" }
      ActiveSupport::Notifications.instrument("red.llm_call", payload) do
        payload[:input_tokens]  = 1500
        payload[:output_tokens] = 420
      end

      meta = collector.current_breadcrumbs.first[:meta]
      expect(meta[:input_tokens]).to eq("1500")
      expect(meta[:output_tokens]).to eq("420")
      # 1500 * 3.0 + 420 * 15.0 = 4500 + 6300 = 10800 / 1M = 0.0108
      expect(meta[:cost_usd]).to eq("0.0108")
    end

    it "honors explicit duration_ms in the payload (overrides event.duration)" do
      ActiveSupport::Notifications.instrument("red.llm_call",
                                              provider: "openai", model: "gpt-4o",
                                              duration_ms: 4242.0) { sleep 0.001 }

      expect(collector.current_breadcrumbs.first[:d]).to eq(4242.0)
    end

    it "honors explicit cost_usd_estimate in the payload (skips auto-estimation)" do
      ActiveSupport::Notifications.instrument("red.llm_call",
                                              provider: "openai", model: "gpt-4o-mini",
                                              input_tokens: 1_000_000, output_tokens: 1_000_000,
                                              cost_usd_estimate: 99.99) { }

      expect(collector.current_breadcrumbs.first[:meta][:cost_usd]).to eq("99.99")
    end

    it "defaults provider and model to 'unknown' when omitted" do
      ActiveSupport::Notifications.instrument("red.llm_call", input_tokens: 5) { }
      meta = collector.current_breadcrumbs.first[:meta]
      expect(meta[:provider]).to eq("unknown")
      expect(meta[:model]).to eq("unknown")
    end

    it "marks status :error when error_class is present" do
      ActiveSupport::Notifications.instrument("red.llm_call",
                                              provider: "openai", model: "gpt-4o",
                                              error_class: "OpenAI::RateLimit",
                                              error_message: "throttled") { }

      meta = collector.current_breadcrumbs.first[:meta]
      expect(meta[:status]).to eq("error")
      expect(meta[:error_class]).to eq("OpenAI::RateLimit")
      expect(meta[:error_message]).to eq("throttled")
      expect(meta).not_to have_key(:cost_usd)
    end

    it "accepts an explicit :timeout status from payload" do
      ActiveSupport::Notifications.instrument("red.llm_call",
                                              provider: "openai", model: "gpt-4o",
                                              status: :timeout,
                                              error_class: "Net::ReadTimeout") { }

      expect(collector.current_breadcrumbs.first[:meta][:status]).to eq("timeout")
    end

    it "ignores invalid payload status and falls back to :success" do
      ActiveSupport::Notifications.instrument("red.llm_call",
                                              provider: "openai", model: "gpt-4o",
                                              status: :nonsense) { }

      expect(collector.current_breadcrumbs.first[:meta][:status]).to eq("success")
    end
  end

  describe "red.llm_tool_call event" do
    before { described_class.subscribe! }

    it "records an llm_tool breadcrumb with tool_name and skips cost" do
      ActiveSupport::Notifications.instrument("red.llm_tool_call",
                                              tool_name: "search_database",
                                              tool_arguments: { query: "users" },
                                              tool_result: "[12 rows]") { sleep 0.001 }

      crumb = collector.current_breadcrumbs.first
      expect(crumb[:c]).to eq("llm_tool")
      expect(crumb[:m]).to eq("tool: search_database")
      expect(crumb[:d]).to be > 0

      meta = crumb[:meta]
      expect(meta[:tool_name]).to eq("search_database")
      expect(meta[:tool_arguments]).to include("query")
      expect(meta[:tool_result]).to include("12 rows")
      expect(meta).not_to have_key(:cost_usd)
    end

    it "defaults tool_name to 'unknown' if the event fires without one" do
      ActiveSupport::Notifications.instrument("red.llm_tool_call",
                                              tool_arguments: { x: 1 }) { }

      crumb = collector.current_breadcrumbs.first
      expect(crumb[:c]).to eq("llm_tool")
      expect(crumb[:meta][:tool_name]).to eq("unknown")
    end

    it "routes red.llm_call events with tool_name to the llm_tool category" do
      # Some hosts may use the generic event name but include a tool_name —
      # presence of tool_name is what defines a tool call in LlmCallEvent.
      ActiveSupport::Notifications.instrument("red.llm_call",
                                              tool_name: "fetch_user",
                                              provider: "anthropic") { }

      crumb = collector.current_breadcrumbs.first
      expect(crumb[:c]).to eq("llm_tool")
      expect(crumb[:meta][:tool_name]).to eq("fetch_user")
    end
  end

  describe "configuration gating" do
    before { described_class.subscribe! }

    it "does nothing when enable_llm_observability is off" do
      RailsErrorDashboard.configuration.enable_llm_observability = false
      ActiveSupport::Notifications.instrument("red.llm_call",
                                              provider: "openai", model: "gpt-4o-mini") { }
      expect(collector.current_breadcrumbs).to be_empty
    end

    it "does nothing when enable_breadcrumbs is off" do
      RailsErrorDashboard.configuration.enable_breadcrumbs = false
      ActiveSupport::Notifications.instrument("red.llm_call",
                                              provider: "openai", model: "gpt-4o-mini") { }
      expect(collector.current_breadcrumbs).to be_empty
    end

    it "re-reads config on each event (host can toggle at runtime)" do
      # Subscribed once; flip the flag off then on between two events.
      RailsErrorDashboard.configuration.enable_llm_observability = false
      ActiveSupport::Notifications.instrument("red.llm_call",
                                              provider: "openai", model: "gpt-4o-mini") { }
      expect(collector.current_breadcrumbs).to be_empty

      RailsErrorDashboard.configuration.enable_llm_observability = true
      ActiveSupport::Notifications.instrument("red.llm_call",
                                              provider: "openai", model: "gpt-4o-mini") { }
      expect(collector.current_breadcrumbs.size).to eq(1)
    end
  end

  describe "safety" do
    before { described_class.subscribe! }

    it "skips when no breadcrumb buffer is active" do
      collector.clear_buffer
      ActiveSupport::Notifications.instrument("red.llm_call",
                                              provider: "openai", model: "gpt-4o-mini") { }
      collector.init_buffer
      expect(collector.current_breadcrumbs).to be_empty
    end

    it "handles an empty payload without raising" do
      expect {
        ActiveSupport::Notifications.instrument("red.llm_call") { }
      }.not_to raise_error

      crumb = collector.current_breadcrumbs.first
      expect(crumb).not_to be_nil
      expect(crumb[:meta][:provider]).to eq("unknown")
    end

    it "rescues internal exceptions and never raises into the host's instrument block" do
      allow(RailsErrorDashboard::Services::BreadcrumbCollector)
        .to receive(:add).and_raise(StandardError, "boom")

      expect {
        ActiveSupport::Notifications.instrument("red.llm_call",
                                                provider: "openai", model: "gpt-4o-mini") { }
      }.not_to raise_error
    end
  end
end
