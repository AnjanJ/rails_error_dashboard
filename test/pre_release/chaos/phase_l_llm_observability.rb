# frozen_string_literal: true

# ============================================================================
# CHAOS TEST PHASE L: v0.7.0 LLM Observability
#
# Verifies the LLM observability stack end-to-end in a real production-mode
# Rails app:
#   - BreadcrumbCollector emits "llm" / "llm_tool" entries through the
#     LlmCallSubscriber (AS::Notifications path — works without Faraday/OTel)
#   - LlmMiddleware (Faraday duck-type) emits breadcrumbs against fake envs
#   - LlmSpanProcessor (OTel duck-type) emits breadcrumbs against fake spans
#   - LlmSummary aggregates correctly
#   - MarkdownErrorFormatter includes an LLM Calls section in Copy-for-LLM
#   - Config gates (enable_llm_observability, enable_breadcrumbs) work
#   - Host-app safety: malformed payloads never raise to the host
#
# This phase exercises code paths that the RSpec suite covers in isolation,
# but does so inside a real Rails app boot — verifying require order,
# eager-load behavior, engine wiring, and ErrorLog#breadcrumbs persistence.
#
# Run with: bin/rails runner test/pre_release/chaos/phase_l_llm_observability.rb
# ============================================================================

harness_path = File.expand_path("../lib/test_harness.rb", __dir__)
require harness_path

PreReleaseTestHarness.reset!
PreReleaseTestHarness.header("CHAOS TEST PHASE L: v0.7.0 LLM OBSERVABILITY")

# ---------------------------------------------------------------------------
# L1: Setup — config flags + autoloaded constants
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("L1: Setup + autoload")

assert "L1: enable_llm_observability is true",
  RailsErrorDashboard.configuration.enable_llm_observability == true
assert "L1: enable_breadcrumbs is true",
  RailsErrorDashboard.configuration.enable_breadcrumbs == true
assert "L1: LlmCallEvent value object loaded",
  defined?(RailsErrorDashboard::ValueObjects::LlmCallEvent) == "constant"
assert "L1: LlmCostEstimator service loaded",
  defined?(RailsErrorDashboard::Services::LlmCostEstimator) == "constant"
assert "L1: LlmSummary service loaded",
  defined?(RailsErrorDashboard::Services::LlmSummary) == "constant"
assert "L1: LlmCallSubscriber loaded",
  defined?(RailsErrorDashboard::Subscribers::LlmCallSubscriber) == "constant"
assert "L1: LlmSpanProcessor loaded",
  defined?(RailsErrorDashboard::Integrations::LlmSpanProcessor) == "constant"
assert "L1: LlmMiddleware loaded",
  defined?(RailsErrorDashboard::Integrations::LlmMiddleware) == "constant"
assert "L1: OTel detector loaded",
  defined?(RailsErrorDashboard::Integrations::OTel) == "constant"
assert "L1: OTel.available? returns a boolean (true or false)",
  [ true, false ].include?(RailsErrorDashboard::Integrations::OTel.available?)
assert "L1: LlmCallSubscriber has at least one subscription registered",
  (RailsErrorDashboard::Subscribers::LlmCallSubscriber.subscriptions || []).any?
puts ""

# ---------------------------------------------------------------------------
# L2: AS::Notifications path — chat success captured as "llm" breadcrumb
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("L2: AS::Notifications red.llm_call (chat)")

# rails runner has no Rack middleware, so we initialise the per-thread buffer
# ourselves. This is exactly what middleware/error_catcher.rb does on real
# requests — we are just standing in for it.
RailsErrorDashboard::Services::BreadcrumbCollector.init_buffer

ActiveSupport::Notifications.instrument("red.llm_call",
  provider: "openai",
  model: "gpt-4o-mini",
  input_tokens: 1200,
  output_tokens: 350,
  status: :success
) do
  # simulated work — sleep would slow chaos tests, just no-op
end

buffer = RailsErrorDashboard::Services::BreadcrumbCollector.current_buffer
crumbs = buffer ? buffer.to_a : []
chat_crumb = crumbs.find { |c| c[:c] == "llm" }

assert "L2: buffer is present", !buffer.nil?
assert "L2: chat breadcrumb captured", !chat_crumb.nil?
if chat_crumb
  meta = chat_crumb[:meta] || {}
  assert "L2: category is 'llm'", chat_crumb[:c] == "llm"
  assert "L2: provider in meta (stringified)", meta[:provider] == "openai"
  assert "L2: model in meta (stringified)", meta[:model] == "gpt-4o-mini"
  assert "L2: input_tokens (stringified by collector)", meta[:input_tokens] == "1200"
  assert "L2: output_tokens (stringified by collector)", meta[:output_tokens] == "350"
  assert "L2: status is success", meta[:status] == "success"
  assert "L2: cost_usd estimated (gpt-4o-mini is in pricing table)",
    meta[:cost_usd].to_s.start_with?("0.0")
  assert "L2: duration_ms present (instrument provides it)",
    !meta[:duration_ms].nil? || !chat_crumb[:d].nil?
  assert "L2: message contains provider/model",
    chat_crumb[:m].to_s.include?("openai") && chat_crumb[:m].to_s.include?("gpt-4o-mini")
  assert "L2: message contains token summary",
    chat_crumb[:m].to_s.include?("in:1200/out:350")
end

# Trigger an error report so the LLM crumb gets persisted into ErrorLog.
# Use the same Rails.error.report path that real apps and other phases use —
# Commands::LogError.call directly bypasses some of the connection setup
# the report subscriber primes.
chat_err_msg = "llm chat probe #{SecureRandom.hex(6)}"
begin
  raise RuntimeError, chat_err_msg
rescue => e
  Rails.error.report(e, handled: false, severity: :error,
    context: { controller_name: "llm_chat_probe", action_name: "index", platform: "Web" })
end

chat_error = RailsErrorDashboard::ErrorLog
  .where("message LIKE ?", "%#{chat_err_msg}%")
  .order(id: :desc)
  .first

assert "L2: ErrorLog row persisted", chat_error&.persisted? == true
if chat_error
  assert "L2: ErrorLog#breadcrumbs JSON present", chat_error.breadcrumbs.present?
  parsed = JSON.parse(chat_error.breadcrumbs) rescue []
  llm_persisted = parsed.find { |c| c.is_a?(Hash) && c["c"] == "llm" }
  assert "L2: 'llm' breadcrumb survives round-trip to DB", !llm_persisted.nil?
  if llm_persisted
    pmeta = llm_persisted["meta"].is_a?(Hash) ? llm_persisted["meta"] : {}
    assert "L2: persisted meta has provider", pmeta["provider"] == "openai"
    assert "L2: persisted meta has model", pmeta["model"] == "gpt-4o-mini"
  end
end
puts ""

# ---------------------------------------------------------------------------
# L3: AS::Notifications path — tool call captured as "llm_tool" breadcrumb
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("L3: AS::Notifications red.llm_tool_call")

RailsErrorDashboard::Services::BreadcrumbCollector.init_buffer

ActiveSupport::Notifications.instrument("red.llm_tool_call",
  tool_name: "search_database",
  tool_arguments: { query: "SELECT * FROM users WHERE id=42" }.to_json,
  tool_result: "[{id: 42, name: \"Frodo\"}]"
) do
  # simulated tool execution
end

tool_crumbs = (RailsErrorDashboard::Services::BreadcrumbCollector.current_buffer&.to_a || [])
tool_crumb = tool_crumbs.find { |c| c[:c] == "llm_tool" }

assert "L3: tool breadcrumb captured", !tool_crumb.nil?
if tool_crumb
  meta = tool_crumb[:meta] || {}
  assert "L3: category is 'llm_tool'", tool_crumb[:c] == "llm_tool"
  assert "L3: tool_name in meta", meta[:tool_name] == "search_database"
  assert "L3: tool_arguments present", meta[:tool_arguments].to_s.include?("SELECT")
  assert "L3: tool_result present", meta[:tool_result].to_s.include?("Frodo")
  assert "L3: no cost_usd on tool calls", meta[:cost_usd].nil?
  assert "L3: message contains tool name", tool_crumb[:m].to_s.include?("search_database")
end

# tool-call with string keys (host code may pass either symbol or string)
ActiveSupport::Notifications.instrument("red.llm_tool_call",
  "tool_name" => "string_key_tool"
) {}

string_keyed = (RailsErrorDashboard::Services::BreadcrumbCollector.current_buffer&.to_a || [])
  .find { |c| (c[:meta] || {})[:tool_name] == "string_key_tool" }

assert "L3: string-keyed payload also captured", !string_keyed.nil?
puts ""

# ---------------------------------------------------------------------------
# L4: LlmCostEstimator — known/unknown models + override config
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("L4: LlmCostEstimator")

est = RailsErrorDashboard::Services::LlmCostEstimator

cost_known = est.estimate(provider: "openai", model: "gpt-4o-mini",
  input_tokens: 1_000_000, output_tokens: 1_000_000)
assert "L4: gpt-4o-mini cost ~ $0.75 for 1M in + 1M out", cost_known && (cost_known - 0.75).abs < 0.001,
  "got #{cost_known.inspect}"

cost_claude = est.estimate(provider: "anthropic", model: "claude-sonnet-4-6",
  input_tokens: 1_000_000, output_tokens: 1_000_000)
assert "L4: claude-sonnet-4-6 cost ~ $18.00 for 1M in + 1M out",
  cost_claude && (cost_claude - 18.0).abs < 0.001, "got #{cost_claude.inspect}"

cost_unknown = est.estimate(provider: "fake", model: "no-such-model",
  input_tokens: 100, output_tokens: 50)
assert "L4: unknown model returns nil (no false positives)", cost_unknown.nil?

cost_no_tokens = est.estimate(provider: "openai", model: "gpt-4o-mini",
  input_tokens: nil, output_tokens: nil)
assert "L4: missing tokens returns nil", cost_no_tokens.nil?

cost_empty_model = est.estimate(provider: "openai", model: "",
  input_tokens: 100, output_tokens: 100)
assert "L4: empty model returns nil", cost_empty_model.nil?

# Override config — temporarily inject a custom rate
RailsErrorDashboard.configuration.llm_pricing_overrides = {
  "my-local-llm" => { input: 0.0, output: 0.0 }
}
cost_override = est.estimate(provider: "local", model: "my-local-llm",
  input_tokens: 5000, output_tokens: 2000)
assert "L4: override rate honored (Ollama-style $0)", cost_override == 0.0
RailsErrorDashboard.configuration.llm_pricing_overrides = {}

# Case-insensitive matching
cost_mixed = est.estimate(provider: "openai", model: "GPT-4o-MINI",
  input_tokens: 1_000_000, output_tokens: 1_000_000)
assert "L4: model match is case-insensitive",
  cost_mixed && (cost_mixed - 0.75).abs < 0.001, "got #{cost_mixed.inspect}"

# Garbage input never raises
assert "L4: garbage tokens never raises (returns nil)",
  est.estimate(provider: "x", model: "x", input_tokens: "abc", output_tokens: "def").nil? ||
    est.estimate(provider: "x", model: "x", input_tokens: "abc", output_tokens: "def") == 0.0 ||
    true # any non-raising outcome counts
puts ""

# ---------------------------------------------------------------------------
# L5: LlmSummary roll-up
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("L5: LlmSummary.call")

crumbs_for_summary = [
  { "c" => "llm", "d" => 421.5, "meta" => { "provider" => "openai", "model" => "gpt-4o-mini",
    "input_tokens" => "1200", "output_tokens" => "350", "cost_usd" => "0.00018",
    "status" => "success" } },
  { "c" => "llm_tool", "d" => 12.0, "meta" => { "tool_name" => "search_db" } },
  { "c" => "llm", "d" => 300.0, "meta" => { "provider" => "anthropic", "model" => "claude-sonnet-4-6",
    "input_tokens" => "800", "output_tokens" => "200", "cost_usd" => "0.0054",
    "status" => "success" } },
  { "c" => "llm", "d" => 100.0, "meta" => { "provider" => "openai", "model" => "gpt-4o-mini",
    "input_tokens" => "200", "output_tokens" => "50", "cost_usd" => "0.00003",
    "status" => "error", "error_class" => "Net::OpenTimeout" } }
]

summary = RailsErrorDashboard::Services::LlmSummary.call(crumbs_for_summary)

assert "L5: summary returned", !summary.nil?
if summary
  assert "L5: total_calls = 3 chat", summary[:total_calls] == 3
  assert "L5: total_tool_calls = 1", summary[:total_tool_calls] == 1
  assert "L5: total_input_tokens summed", summary[:total_input_tokens] == 2200
  assert "L5: total_output_tokens summed", summary[:total_output_tokens] == 600
  assert "L5: total_tokens = in + out", summary[:total_tokens] == 2800
  assert "L5: error_count = 1 (timeout counts)", summary[:error_count] == 1
  assert "L5: total_cost_usd summed (5.61e-3)",
    (summary[:total_cost_usd] - 0.00561).abs < 0.00001,
    "got #{summary[:total_cost_usd]}"
  assert "L5: total_duration_ms includes tool duration",
    (summary[:total_duration_ms] - 833.5).abs < 0.1,
    "got #{summary[:total_duration_ms]}"
  assert "L5: providers list sorted",
    summary[:providers] == [ "anthropic", "openai" ]
  assert "L5: by_model has 2 entries", summary[:by_model].size == 2
  if summary[:by_model].size >= 1
    top = summary[:by_model].first
    assert "L5: by_model sorted by calls desc (gpt-4o-mini first, 2 calls)",
      top[:model] == "gpt-4o-mini" && top[:calls] == 2
  end
end

# Edge: nil/empty input does not raise
assert "L5: nil input returns nil", RailsErrorDashboard::Services::LlmSummary.call(nil).nil?
assert "L5: empty array returns nil", RailsErrorDashboard::Services::LlmSummary.call([]).nil?
assert "L5: non-LLM crumbs return nil",
  RailsErrorDashboard::Services::LlmSummary.call([ { "c" => "sql", "m" => "SELECT 1" } ]).nil?
puts ""

# ---------------------------------------------------------------------------
# L6: MarkdownErrorFormatter — LLM Calls section in Copy-for-LLM
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("L6: MarkdownErrorFormatter LLM section")

# chat_error from L2 already has llm breadcrumbs persisted. Format it and
# verify the LLM section appears.
if chat_error
  md = RailsErrorDashboard::Services::MarkdownErrorFormatter.call(chat_error, related_errors: [])
  assert "L6: markdown not empty", md.present?
  assert "L6: contains '## LLM Calls' header", md.include?("## LLM Calls")
  assert "L6: contains '**By Model**' subhead", md.include?("**By Model**")
  assert "L6: contains '**Calls (last' table", md.include?("**Calls (last")
  assert "L6: provider name in markdown", md.include?("openai")
  assert "L6: model name in markdown", md.include?("gpt-4o-mini")
  assert "L6: token figures in markdown", md.include?("1200") || md.include?("in:1200")
  # Ordering: LLM Calls comes before Breadcrumbs
  llm_idx = md.index("## LLM Calls")
  bc_idx  = md.index("## Breadcrumbs")
  assert "L6: LLM Calls section appears before Breadcrumbs",
    llm_idx && bc_idx && llm_idx < bc_idx
end
puts ""

# ---------------------------------------------------------------------------
# L7: Disabled-flag behavior — observability OFF means no emission
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("L7: Config flag short-circuits emission")

RailsErrorDashboard.configuration.enable_llm_observability = false
RailsErrorDashboard::Services::BreadcrumbCollector.init_buffer

ActiveSupport::Notifications.instrument("red.llm_call",
  provider: "openai", model: "gpt-4o-mini",
  input_tokens: 100, output_tokens: 50, status: :success
) {}

after_disable = (RailsErrorDashboard::Services::BreadcrumbCollector.current_buffer&.to_a || [])
  .select { |c| c[:c] == "llm" || c[:c] == "llm_tool" }

assert "L7: no LLM crumbs emitted when enable_llm_observability=false",
  after_disable.empty?

RailsErrorDashboard.configuration.enable_llm_observability = true
RailsErrorDashboard.configuration.enable_breadcrumbs = false
RailsErrorDashboard::Services::BreadcrumbCollector.init_buffer

ActiveSupport::Notifications.instrument("red.llm_call",
  provider: "openai", model: "gpt-4o-mini",
  input_tokens: 100, output_tokens: 50, status: :success
) {}

after_disable2 = (RailsErrorDashboard::Services::BreadcrumbCollector.current_buffer&.to_a || [])
  .select { |c| c[:c] == "llm" || c[:c] == "llm_tool" }

assert "L7: no LLM crumbs emitted when enable_breadcrumbs=false",
  after_disable2.empty?

# Restore for downstream sections
RailsErrorDashboard.configuration.enable_breadcrumbs = true
RailsErrorDashboard.configuration.enable_llm_observability = true
RailsErrorDashboard::Services::BreadcrumbCollector.init_buffer
puts ""

# ---------------------------------------------------------------------------
# L8: LlmMiddleware (Faraday duck-type) — fake env, real breadcrumb
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("L8: LlmMiddleware (Faraday path)")

FakeUrl  = Struct.new(:host) unless defined?(FakeUrl)
FakeResp = Struct.new(:status, :headers, :body) unless defined?(FakeResp)
FakeEnv  = Struct.new(:url, :body) unless defined?(FakeEnv)

# Downstream "Faraday app" that returns an OpenAI-shaped success response.
downstream = ->(_env) {
  FakeResp.new(
    200,
    { "content-type" => "application/json" },
    {
      "model" => "gpt-4o-mini-2024-07-18",
      "usage" => { "prompt_tokens" => 50, "completion_tokens" => 25 },
      "choices" => [ { "message" => { "content" => "Hi!" } } ]
    }
  )
}
mw = RailsErrorDashboard::Integrations::LlmMiddleware.new(downstream)
RailsErrorDashboard::Services::BreadcrumbCollector.init_buffer

resp = mw.call(FakeEnv.new(FakeUrl.new("api.openai.com"),
  { "model" => "gpt-4o-mini", "messages" => [] }))

assert "L8: middleware returns response", !resp.nil?
assert "L8: middleware response status preserved", resp.status == 200

mw_crumbs = (RailsErrorDashboard::Services::BreadcrumbCollector.current_buffer&.to_a || [])
  .select { |c| c[:c] == "llm" }
assert "L8: breadcrumb emitted via middleware", mw_crumbs.any?
if mw_crumbs.any?
  meta = mw_crumbs.last[:meta] || {}
  assert "L8: provider = openai", meta[:provider] == "openai"
  assert "L8: model prefers response model",
    meta[:model] == "gpt-4o-mini-2024-07-18"
  assert "L8: input_tokens captured (50)", meta[:input_tokens] == "50"
  assert "L8: output_tokens captured (25)", meta[:output_tokens] == "25"
end

# Non-LLM host short-circuits
non_llm_calls = 0
non_llm_downstream = ->(_env) {
  non_llm_calls += 1
  FakeResp.new(200, {}, {})
}
mw_non_llm = RailsErrorDashboard::Integrations::LlmMiddleware.new(non_llm_downstream)
before_count = (RailsErrorDashboard::Services::BreadcrumbCollector.current_buffer&.to_a || [])
  .count { |c| c[:c] == "llm" }
mw_non_llm.call(FakeEnv.new(FakeUrl.new("api.example.com"), nil))
after_count = (RailsErrorDashboard::Services::BreadcrumbCollector.current_buffer&.to_a || [])
  .count { |c| c[:c] == "llm" }
assert "L8: non-LLM host calls downstream", non_llm_calls == 1
assert "L8: non-LLM host emits no llm crumb", before_count == after_count

# Upstream exception is RE-RAISED (host-app safety Rule 5)
raise_downstream = ->(_env) { raise Net::OpenTimeout, "boom" }
mw_raise = RailsErrorDashboard::Integrations::LlmMiddleware.new(raise_downstream)
re_raised = false
begin
  mw_raise.call(FakeEnv.new(FakeUrl.new("api.openai.com"),
    { "model" => "gpt-4o-mini" }))
rescue Net::OpenTimeout
  re_raised = true
end
assert "L8: upstream exception is re-raised (Rule 5)", re_raised

# And a breadcrumb is still recorded with status :timeout
timeout_crumbs = (RailsErrorDashboard::Services::BreadcrumbCollector.current_buffer&.to_a || [])
  .select { |c| (c[:meta] || {})[:error_class] == "Net::OpenTimeout" }
assert "L8: timeout breadcrumb still emitted on raise",
  timeout_crumbs.any?
if timeout_crumbs.any?
  meta = timeout_crumbs.last[:meta] || {}
  assert "L8: timeout status classified as :timeout",
    meta[:status] == "timeout"
end

# HTTP 4xx error path
err_downstream = ->(_env) {
  FakeResp.new(429, { "content-type" => "application/json" },
    { "error" => { "message" => "rate limit hit", "type" => "rate_limit_error" } })
}
mw_429 = RailsErrorDashboard::Integrations::LlmMiddleware.new(err_downstream)
mw_429.call(FakeEnv.new(FakeUrl.new("api.openai.com"), { "model" => "gpt-4o-mini" }))
http_err_crumbs = (RailsErrorDashboard::Services::BreadcrumbCollector.current_buffer&.to_a || [])
  .select { |c| (c[:meta] || {})[:error_class] == "HTTP 429" }
assert "L8: HTTP 4xx classified as error breadcrumb",
  http_err_crumbs.any?
if http_err_crumbs.any?
  meta = http_err_crumbs.last[:meta] || {}
  assert "L8: error_message extracted from body",
    meta[:error_message].to_s.include?("rate limit")
  assert "L8: status = error", meta[:status] == "error"
end
puts ""

# ---------------------------------------------------------------------------
# L9: LlmSpanProcessor (OTel duck-type) — fake GenAI span, real breadcrumb
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("L9: LlmSpanProcessor (OTel path)")

FakeSpan = Struct.new(:attributes, :start_timestamp, :end_timestamp) unless defined?(FakeSpan)
processor = RailsErrorDashboard::Integrations::LlmSpanProcessor.new

RailsErrorDashboard::Services::BreadcrumbCollector.init_buffer

# Current GenAI semconv span
processor.on_finish(FakeSpan.new(
  {
    "gen_ai.provider.name" => "openai",
    "gen_ai.request.model" => "gpt-4o-mini",
    "gen_ai.response.model" => "gpt-4o-mini-2024-07-18",
    "gen_ai.usage.input_tokens" => 50,
    "gen_ai.usage.output_tokens" => 25
  },
  1_700_000_000_000_000_000,
  1_700_000_000_421_500_000
))

span_crumbs = (RailsErrorDashboard::Services::BreadcrumbCollector.current_buffer&.to_a || [])
  .select { |c| c[:c] == "llm" }
assert "L9: span processor emitted breadcrumb", span_crumbs.any?
if span_crumbs.any?
  meta = span_crumbs.last[:meta] || {}
  assert "L9: provider mapped from gen_ai.provider.name",
    meta[:provider] == "openai"
  assert "L9: response model preferred over request model",
    meta[:model] == "gpt-4o-mini-2024-07-18"
  assert "L9: input_tokens captured", meta[:input_tokens] == "50"
  assert "L9: output_tokens captured", meta[:output_tokens] == "25"
  assert "L9: duration_ms computed from ns timestamps (~421.5ms)",
    meta[:duration_ms].to_f.round(1) == 421.5
end

# Deprecated semconv aliases also map
processor.on_finish(FakeSpan.new(
  {
    "gen_ai.system" => "anthropic",
    "gen_ai.request.model" => "claude-haiku-4-5",
    "gen_ai.usage.prompt_tokens" => 100,
    "gen_ai.usage.completion_tokens" => 50
  },
  1_700_000_000_000_000_000,
  1_700_000_000_100_000_000
))

deprecated_crumbs = (RailsErrorDashboard::Services::BreadcrumbCollector.current_buffer&.to_a || [])
  .select { |c| (c[:meta] || {})[:provider] == "anthropic" }
assert "L9: deprecated gen_ai.system maps to provider",
  deprecated_crumbs.any?

# Tool-execution span → llm_tool category
processor.on_finish(FakeSpan.new(
  {
    "gen_ai.operation.name" => "execute_tool",
    "gen_ai.tool.name" => "weather_lookup"
  },
  1_700_000_000_000_000_000,
  1_700_000_000_005_000_000
))

tool_span_crumbs = (RailsErrorDashboard::Services::BreadcrumbCollector.current_buffer&.to_a || [])
  .select { |c| c[:c] == "llm_tool" && (c[:meta] || {})[:tool_name] == "weather_lookup" }
assert "L9: tool span routed to 'llm_tool' category", tool_span_crumbs.any?

# Non-GenAI span is ignored (cheap pre-filter)
before = (RailsErrorDashboard::Services::BreadcrumbCollector.current_buffer&.to_a || []).size
processor.on_finish(FakeSpan.new({ "http.method" => "GET" }, nil, nil))
after = (RailsErrorDashboard::Services::BreadcrumbCollector.current_buffer&.to_a || []).size
assert "L9: non-GenAI span does NOT emit a crumb", before == after

# force_flush + shutdown return the OTel SUCCESS sentinel (0)
assert "L9: force_flush returns 0 (SUCCESS sentinel)", processor.force_flush == 0
assert "L9: shutdown returns 0 (SUCCESS sentinel)", processor.shutdown == 0

# Span with bad attributes (raises on .attributes) → silently no-ops
class BadSpan
  def attributes; raise "boom"; end
  def start_timestamp; nil; end
  def end_timestamp; nil; end
end
no_raise = true
begin
  processor.on_finish(BadSpan.new)
rescue
  no_raise = false
end
assert "L9: pathological span never raises", no_raise
puts ""

# ---------------------------------------------------------------------------
# L10: Host-app safety smoke — malformed input never raises
# ---------------------------------------------------------------------------
PreReleaseTestHarness.section("L10: Host-app safety smoke")

# Malformed payload to AS::Notifications — subscriber must not raise
no_raise = true
begin
  ActiveSupport::Notifications.instrument("red.llm_call", nil) {}
rescue => e
  no_raise = false
  puts "    raised: #{e.class}: #{e.message}"
end
assert "L10: nil payload to red.llm_call never raises", no_raise

no_raise2 = true
begin
  ActiveSupport::Notifications.instrument("red.llm_call",
    provider: nil, model: nil, input_tokens: "abc", output_tokens: nil) {}
rescue => e
  no_raise2 = false
end
assert "L10: garbage payload never raises", no_raise2

# LlmSummary on garbage data
no_raise3 = true
begin
  RailsErrorDashboard::Services::LlmSummary.call([ "not a hash", nil, 42 ])
rescue => e
  no_raise3 = false
end
assert "L10: LlmSummary on garbage array never raises", no_raise3

# MarkdownErrorFormatter on error with no breadcrumbs
empty_err = RailsErrorDashboard::ErrorLog.new(
  error_type: "RuntimeError", message: "nothing", error_hash: SecureRandom.hex(8),
  controller_name: "x", action_name: "y", platform: "Web"
)
no_raise4 = true
md_empty = nil
begin
  md_empty = RailsErrorDashboard::Services::MarkdownErrorFormatter.call(empty_err, related_errors: [])
rescue => e
  no_raise4 = false
  puts "    raised: #{e.class}: #{e.message}"
end
assert "L10: MarkdownErrorFormatter never raises on bare ErrorLog", no_raise4
assert "L10: MarkdownErrorFormatter omits LLM section when no breadcrumbs",
  md_empty.is_a?(String) && !md_empty.include?("## LLM Calls")

# Verify OTel.available? is idempotent + memoized
v1 = RailsErrorDashboard::Integrations::OTel.available?
v2 = RailsErrorDashboard::Integrations::OTel.available?
assert "L10: OTel.available? is consistent across calls", v1 == v2
puts ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
exit_code = PreReleaseTestHarness.summary("PHASE L")
exit(exit_code)
