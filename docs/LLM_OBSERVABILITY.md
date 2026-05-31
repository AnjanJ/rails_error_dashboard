---
layout: default
title: "LLM Observability Guide"
permalink: /docs/LLM_OBSERVABILITY
---

# LLM Observability Guide

Capture every LLM call your application makes — model, latency, token counts, estimated USD cost, and tool-use requests — as breadcrumbs on the error that follows. When a request crashes, you see the chat completion that preceded it: which model was called, how long it took, what it cost, and which tools it asked to invoke.

**⚙️ Optional Feature** — disabled by default. Enable it in your initializer:

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_breadcrumbs        = true   # required — LLM crumbs ride the breadcrumb pipeline
  config.enable_llm_observability  = true
end
```

## Table of Contents

- [Overview](#overview)
- [Three Capture Paths](#three-capture-paths)
- [What Gets Captured](#what-gets-captured)
- [Cost Estimation](#cost-estimation)
- [Configuration](#configuration)
- [AS::Notifications Payload Contract](#asnotifications-payload-contract)
- [Where LLM Data Appears](#where-llm-data-appears)
- [Privacy & Content Capture](#privacy--content-capture)
- [Host App Safety](#host-app-safety)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)

## Overview

LLM observability records each LLM call as a structured breadcrumb attached to the request's error trail. When something fails downstream of an LLM call, you can see exactly:

- **Which model** answered (provider + model name, with response model preferred over request model)
- **How big** the call was (input/output token counts)
- **How long** it took (millisecond-precision duration)
- **How much** it cost (estimated USD, computed from a built-in pricing table)
- **What tools** it asked to invoke (function names and counts)
- **Whether it failed** (timeout / HTTP error / upstream exception)

The data lives in the existing breadcrumb pipeline — no separate table, no schema migration, no new background job. If you already have breadcrumbs enabled, turning on LLM observability adds two new categories (`llm` and `llm_tool`) to the same per-request ring buffer.

### Why You Want This

When an LLM-powered feature breaks, the failure is rarely at the LLM boundary itself — it's three function calls later, when your code tried to parse the model's reply, or routed on a tool call that didn't materialize, or hit a downstream service that the LLM's plan didn't account for. The traceback shows you *where* it broke, but not *what the model said.*

LLM observability fills that gap. The error detail page shows:

- A sidebar card with totals (calls, tokens, cost, errors)
- Each LLM call inline in the breadcrumb trail, with tool calls visually nested under their parent chat
- The Copy-for-LLM markdown export includes an `## LLM Calls` section so you can paste the whole picture into your AI debugger

## Three Capture Paths

Pick whichever matches your stack. You can use more than one — the paths are additive, not exclusive.

### Path A — `ruby-openai` (Faraday middleware)

`ruby-openai` (v8.x) uses Faraday internally and accepts user middleware via a block passed to `OpenAI::Client.new`. Insert ours and every call gets captured:

```ruby
client = OpenAI::Client.new do |f|
  f.use RailsErrorDashboard::Integrations::LlmMiddleware
end

client.chat(parameters: { model: "gpt-4o-mini", messages: [ ... ] })
# → breadcrumb emitted automatically with provider, model, tokens, cost, tool calls
```

The middleware:
- Detects `api.openai.com` requests by URL host
- Reads `usage.prompt_tokens` / `usage.completion_tokens` from the response body
- Captures tool-call requests from `choices[0].message.tool_calls`
- Skips streaming responses (`content-type: text/event-stream`) — token counts aren't in the stream until the final SSE event, and we don't buffer
- Records a breadcrumb whether the call succeeded, returned an HTTP error (4xx/5xx), or raised mid-flight
- **Always re-raises upstream exceptions** — never interferes with your error handling

### Path B — `ruby_llm` (OpenTelemetry)

`ruby_llm` doesn't expose a Faraday hook. Instead, use the thoughtbot OTel instrumentation gem — it emits GenAI-semconv spans that our `LlmSpanProcessor` picks up automatically.

```ruby
# Gemfile
gem "ruby_llm"
gem "opentelemetry-sdk"
gem "opentelemetry-instrumentation-ruby_llm"

# config/initializers/opentelemetry.rb
OpenTelemetry::SDK.configure do |c|
  c.use "OpenTelemetry::Instrumentation::RubyLLM"
end
```

Our `LlmSpanProcessor` registers itself with `OpenTelemetry.tracer_provider` during engine boot — no extra wiring. The processor maps:

| GenAI semconv attribute | Breadcrumb metadata field |
|-------------------------|---------------------------|
| `gen_ai.provider.name` (or deprecated `gen_ai.system`) | `provider` |
| `gen_ai.response.model` → `gen_ai.request.model` | `model` |
| `gen_ai.usage.input_tokens` (or `prompt_tokens`) | `input_tokens` |
| `gen_ai.usage.output_tokens` (or `completion_tokens`) | `output_tokens` |
| `gen_ai.tool.name` (or `operation.name == "execute_tool"`) | routes to `llm_tool` category |
| `error.type` | sets status to `:error` |

Spans without GenAI attributes are skipped after a cheap pre-filter (5 hash lookups, well under a microsecond).

### Path C — anything else (AS::Notifications)

The official `anthropic` gem uses `Net::HTTP` directly (no Faraday hook), and many local-inference setups (Ollama, llama.cpp, custom gRPC clients) don't run OTel. For all of these, wrap the call in `ActiveSupport::Notifications.instrument`:

```ruby
payload = { provider: "anthropic", model: "claude-sonnet-4-6" }

ActiveSupport::Notifications.instrument("red.llm_call", payload) do
  response = Anthropic::Client.new.messages.create(
    model: "claude-sonnet-4-6",
    messages: [ { role: "user", content: "hi" } ]
  )
  # Mutate the payload AFTER the call so token counts are recorded
  payload[:input_tokens]  = response.usage.input_tokens
  payload[:output_tokens] = response.usage.output_tokens
end

# Tool execution — captured as its own llm_tool breadcrumb
ActiveSupport::Notifications.instrument("red.llm_tool_call",
  tool_name: "search_database",
  tool_arguments: { query: "SELECT ..." }
) do
  # run the tool
end
```

The instrument-then-mutate pattern works because AS::Notifications passes the **same Hash object** to the subscriber after the block returns. The subscriber reads it as the canonical source of truth.

## What Gets Captured

For every chat call (`llm` category):

```
provider       — "openai" / "anthropic" / "ollama" / your string
model          — "gpt-4o-mini" / "claude-sonnet-4-6" / etc.
input_tokens   — Integer
output_tokens  — Integer
duration_ms    — Float, monotonic clock
status         — "success" / "error" / "timeout"
cost_usd       — Float (auto-estimated; see Cost Estimation)
error_class    — present when status != success
error_message  — truncated to 200 chars, present when status != success
tool_arguments — present when the model requested tools (Path A only):
                 "tools:N name1,name2,name3 +X more"
```

For every tool execution (`llm_tool` category):

```
tool_name      — "search_database" / "calculator" / etc.
tool_arguments — JSON-ish string, truncated to 500 chars
tool_result    — JSON-ish string, truncated to 500 chars
duration_ms    — Float
```

All values are persisted as strings via `BreadcrumbCollector#truncate_metadata`. The dashboard's view and Markdown formatter handle coercion (`to_i` / `to_f`) when rendering or aggregating.

## Cost Estimation

The `LlmCostEstimator` service computes USD cost from token counts + a pricing table. The built-in table covers the major models as of 2026-05:

| Provider | Models |
|----------|--------|
| Anthropic | `claude-opus-4-7`, `claude-sonnet-4-6`, `claude-haiku-4-5` |
| OpenAI | `gpt-4o`, `gpt-4o-mini`, `gpt-4-turbo`, `o1`, `o1-mini` |
| Google | `gemini-2.5-pro`, `gemini-2.5-flash` |

Prices are USD per 1,000,000 tokens (the canonical unit used by every major provider's pricing page).

### Overrides

Provider prices change. To override per-model rates — or to add a model not in the built-in table — set `llm_pricing_overrides`:

```ruby
config.llm_pricing_overrides = {
  "claude-sonnet-4-6" => { input: 3.0, output: 15.0 },
  "my-self-hosted-llama-70b" => { input: 0.0, output: 0.0 }
}
```

Keys are matched case-insensitively. User overrides win over built-in prices.

### Unknown Models

If the model is not in the override table OR the built-in `PRICES` constant, `cost_usd` is **omitted** from the breadcrumb. The breadcrumb itself still records — only the cost field is missing. Renderers display `—` for unknown costs so Ollama / local-model rows don't show `$0.000000`.

### Tool Calls

Tool calls do NOT carry a cost — they represent execution time on *your* infrastructure, not on the provider's. The `LlmSummary` rolls up tool durations into the visible-request impact total, but excludes them from cost totals.

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `enable_breadcrumbs` | `false` | Master switch for the breadcrumb pipeline. **Required** for LLM observability. |
| `enable_llm_observability` | `false` | Master switch for LLM capture. Requires `enable_breadcrumbs = true`. |
| `llm_pricing_overrides` | `{}` | Per-model rate overrides — Hash with `{ input:, output: }` USD/M tokens. |
| `llm_observability_content_capture` | `false` | (Reserved for future use — prompts/completions are not recorded in v0.7.0.) |
| `breadcrumb_buffer_size` | `40` | Maximum breadcrumbs per request — LLM crumbs share this buffer with sql / cache / etc. |

If `enable_llm_observability = true` but `enable_breadcrumbs = false`, the gem prints a warning at boot — LLM crumbs ride the breadcrumb pipeline and cannot work without it.

## AS::Notifications Payload Contract

The `red.llm_call` and `red.llm_tool_call` payloads accept exactly these keys (symbol or string — both work):

```ruby
{
  provider:           "openai",          # required for cost lookup
  model:              "gpt-4o-mini",     # required for cost lookup
  status:             :success,          # :success | :error | :timeout (default :success)
  input_tokens:       Integer,           # for cost + summary aggregation
  output_tokens:      Integer,
  duration_ms:        Float,             # override AS event's auto-timed duration
  error_class:        "Net::OpenTimeout",# implies :error status if status not given
  error_message:      "request timed out",
  tool_name:          "search_database", # presence routes to llm_tool category
  tool_arguments:     "...",             # truncated to 500 chars
  tool_result:        "...",             # truncated to 500 chars
  cost_usd_estimate:  Float              # override auto-computed cost
}
```

Defaults that you don't have to pass:
- `status` defaults to `:success` (or `:error` if `error_class` is set)
- `cost_usd_estimate` defaults to `LlmCostEstimator.estimate(...)` for chat calls; nil for tool calls
- `duration_ms` defaults to the AS::Notifications event's duration (the time spent inside the `.instrument` block)

If `tool_name` is present, the breadcrumb is categorized as `llm_tool` regardless of which event name (`red.llm_call` or `red.llm_tool_call`) was instrumented. This lets you emit tool spans through whichever event name fits your code structure.

## Where LLM Data Appears

Once captured, LLM data shows up in three places on the error detail page:

### Breadcrumb Trail

Each LLM call renders as a row with category badge (`llm` blue / `llm_tool` orange), provider · model, token counts, cost, and a status pill if non-success. Tool calls that follow an LLM chat call are visually nested with a `↪` indicator and 2rem of left padding — so the parent/child relationship is obvious at a glance.

### Sidebar Summary Card

When any LLM breadcrumb exists, a "LLM Calls" card appears in the sidebar with:
- Total calls / tokens / cost (3-column stat row)
- Input / output / tool calls / total time
- A red error count if any call failed
- Per-model rollup (provider · model · calls · tokens · cost)
- A danger banner if errors occurred

The card hides entirely when no LLM breadcrumbs exist or `enable_llm_observability` is off.

### Copy-for-LLM Markdown Export

The "Copy as Markdown" button produces an export that includes a full `## LLM Calls` section between Request Context and Breadcrumbs. It contains:

1. **One-line totals** — `3 calls · 1 tool call · 2200 tokens (in:1800/out:400) · $0.0061 · 833.5ms total · **1 error**`
2. **By Model table** — Provider, model, calls, tokens, cost (Markdown `|...|` table)
3. **Calls table** — Last 10 events with time, type (chat / tool), provider/model, status, tokens, cost, duration
4. **Failures bullet list** — Surfaces error class + message inline so the LLM consumer doesn't have to cross-reference the breadcrumb dump

Zero-cost rows render `—` instead of `$0.000000` to keep Ollama-style local-inference rows readable.

## Privacy & Content Capture

**Prompt and completion content is NEVER recorded in v0.7.0.** Only metadata — token counts, model names, durations, costs, tool names, and (when truncated and only on the AS::Notifications path) tool arguments / results.

This is intentional. LLM prompts often contain user PII (chat history, support tickets, code snippets), and recording them by default would silently exfiltrate sensitive data into error reports. If you want to record prompts for a specific call, do it yourself via the `tool_arguments` / `tool_result` fields with appropriate scrubbing.

The reserved `llm_observability_content_capture` config flag will be evaluated in a future release for users who explicitly want prompt logging in a controlled subset of calls. For v0.7.0, the answer is "no, we don't capture content."

### Sensitive Data Filtering

Breadcrumb metadata flows through the same `SensitiveDataFilter` as the rest of the gem. If you've added patterns to `config.sensitive_data_patterns`, they apply to LLM breadcrumb fields too:

```ruby
config.filter_sensitive_data = true
config.sensitive_data_patterns = [ /api_key/i, /authorization/i ]
```

Tool arguments / results are particularly worth scrubbing before they reach the breadcrumb — they often contain raw user input.

## Host App Safety

The three capture paths and the cost estimator are governed by the same rules as the rest of the gem. From `HOST_APP_SAFETY.md`:

- **Rule 1 (never raise in capture):** every callback wraps its body in `rescue StandardError`. The Faraday middleware emits the breadcrumb inside an `ensure` block with its own inner rescue, so a failure during breadcrumb emission cannot interfere with the upstream call's exception propagation.
- **Rule 2 (never block):** Config flags are re-read on every event. When disabled, the cost is one boolean read + an early return. Benchmarks show worst-case hot-path cost of **0.004 ms/op** — ~125× under the 0.5 ms-per-operation budget.
- **Rule 5 (re-raise upstream exceptions):** the `LlmMiddleware` re-raises every exception thrown by the upstream Faraday app via a bare `raise` statement. Sentry's Issue #1173 lesson is respected — we will never swallow your app's exceptions to record a breadcrumb.
- **Rule 6 (feature-detect):** the OTel processor is registered only if `OpenTelemetry::SDK` is loaded AND the active tracer provider supports `add_span_processor`. (A bare `OpenTelemetry.tracer_provider` returns a `ProxyTracerProvider` until `OpenTelemetry::SDK.configure` is called — it doesn't have `add_span_processor`. We check before calling.) The Faraday middleware loads without Faraday installed because it doesn't subclass `Faraday::Middleware`; it just exposes the duck-typed `initialize(app)` + `call(env)` interface.

## Troubleshooting

### "No LLM section in the error detail"

1. Verify both flags are on: `enable_breadcrumbs = true` AND `enable_llm_observability = true`.
2. Verify the request actually generated breadcrumbs — look at the Breadcrumbs section of the same error. If it's empty, the request happened outside the gem's middleware (e.g., a rake task).
3. For Path B (OTel): verify `OpenTelemetry::SDK.configure` runs at boot. A bare `OpenTelemetry.tracer_provider` without `.configure` returns a `ProxyTracerProvider`, which our `register!` correctly skips. Check engine boot logs for `LlmSpanProcessor.register! failed`.
4. For Path C (AS::Notifications): if you forgot to mutate the payload after the call, token counts will be missing — but the breadcrumb still records with `provider/model · in:?/out:?`. To debug, log the payload contents after the block.

### "Costs are wrong"

The built-in pricing table is a snapshot. Providers change rates; new models appear weekly. Override:

```ruby
config.llm_pricing_overrides = {
  "your-model" => { input: 3.0, output: 15.0 }  # USD per 1,000,000 tokens
}
```

Or open a PR adding the model to `lib/rails_error_dashboard/services/llm_cost_estimator.rb`.

### "Tool calls aren't nested under the chat that requested them"

Tool nesting is visual-only — it relies on temporal ordering in the breadcrumb buffer. A row gets the nested indent + `↪` glyph when:
- Its category is `llm_tool`, AND
- The immediately previous breadcrumb's category is `llm` or `llm_tool`

If unrelated breadcrumbs (a SQL query, a controller event) land between the chat and the tool call, the visual nesting won't trigger. The data is still recorded correctly — only the UI indent is missing.

### "I'm hitting the 40-breadcrumb buffer cap"

Increase `breadcrumb_buffer_size`. LLM crumbs share the buffer with all other categories — a busy request that emits 30 SQL crumbs plus 5 chat calls and 8 tool calls will wrap around.

```ruby
config.breadcrumb_buffer_size = 100
```

Each breadcrumb is ~1KB in storage, so a buffer of 100 adds ~100KB per error log row that captures a full request's activity.

### "Path A breadcrumbs show prompt body even though content capture is off"

Path A (`LlmMiddleware`) parses the **request** body to extract the model name — but it does NOT persist the prompt content. Only `model`, token counts, cost, and tool-call summaries reach the breadcrumb. If you see prompt text in the breadcrumb metadata, file a bug — that's a regression.

### "OpenTelemetry::Instrumentation::RubyLLM isn't available"

The thoughtbot gem is named `opentelemetry-instrumentation-ruby_llm` (note the underscore in `ruby_llm`). Add it to your Gemfile:

```ruby
gem "opentelemetry-instrumentation-ruby_llm"
```

Then `bundle install` and restart your server. Our `LlmSpanProcessor` will pick up the spans on the next request.

## FAQ

**Q: Why doesn't the official `anthropic` gem work with the Faraday middleware?**

The official `anthropic` gem (anthropics/anthropic-sdk-ruby, v1.x) uses a pooled `Net::HTTP` transport — no Faraday at all. Faraday-style `Anthropic::Client.new do |f| f.use ... end` snippets that appear in some tutorials are for the LEGACY `ruby-anthropic` gem (alexrudall/anthropic). For the official gem, use Path C (AS::Notifications).

**Q: Why does `ruby-openai` install Faraday middleware AFTER its own middleware?**

`ruby-openai` v8.x calls the user-supplied block in `OpenAI::Client.new(&block)` AFTER it has built the Faraday connection and added its own middleware stack (`MiddlewareErrors`, `:raise_error`, `:json`). So `f.use OurMiddleware` appends ours at the *end* of the stack. This means HTTP errors raised by `:raise_error` reach our `call(env)` *via the upstream exception path*, not via a 4xx response. Our middleware handles both — the `ensure` block emits an error breadcrumb either way.

**Q: How much overhead does this add per request?**

Worst case per breadcrumb emission is **~4 microseconds**. A request with 10 LLM calls and 20 tool calls pays ~120μs of LLM-observability overhead. The dominant cost is the actual LLM call (often 100ms+), so observability overhead is in the noise.

**Q: Can I use this for non-LLM HTTP APIs (e.g., Stripe, Twilio)?**

The Faraday middleware only matches `api.openai.com` and `api.anthropic.com` by URL host. Other hosts short-circuit with one string comparison. For arbitrary outbound API calls, use AS::Notifications with whatever event name you like — the dashboard's `red.llm_call` event name is hard-coded as the AS::Notifications subscriber's filter, but nothing prevents you from creating a sibling subscriber for `red.http_call` in your own initializer.

**Q: Does this affect my AI bill?**

No. We never *make* LLM calls — we only observe yours. Token counts come from the provider's response body (no extra inference needed). Cost estimation is a local multiplication.

**Q: Will streaming responses ever be supported?**

Probably, in a future minor release. Streaming requires parsing the SSE final event to extract token usage. The current middleware skips streaming because doing it correctly means buffering the stream, which defeats the SDK's streaming behavior. If you need streaming observability now, use Path B (OTel) — `ruby_llm`'s OTel instrumentation handles streaming correctly.

**Q: Why aren't prompts captured by default?**

Privacy. LLM prompts routinely include user PII (support chats, code, documents). Defaulting to capture would silently exfiltrate this into error reports. If you want prompts for a specific call, log them yourself via `tool_arguments` with appropriate scrubbing.

---

[← Back to Features](FEATURES.md) · [Configuration reference](guides/CONFIGURATION.md) · [Host App Safety](https://github.com/AnjanJ/rails_error_dashboard/blob/main/HOST_APP_SAFETY.md)
