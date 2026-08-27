# K — LLM / OTel / mobile / real-time / AI Help / MCP verification

## Repo reality (verified in source)
- LLM gems: ruby-openai via Faraday middleware (hosts api.openai.com/api.anthropic.com; skips streaming); ruby_llm only via thoughtbot opentelemetry-instrumentation-ruby_llm GenAI spans → LlmSpanProcessor; everything else manual AS::Notifications("red.llm_call"/"red.llm_tool_call"). No langchainrb.
- Per-model health page real (0.7.2). Content capture: `llm_observability_content_capture` is a reserved NO-OP — prompts/completions never captured at all (stronger than "off by default").
- OTel inbound: GenAI-semconv spans only (gen_ai.* keys). Generic spans NOT turned into breadcrumbs. Outbound real (0.8.0): rails_error_dashboard.<op> spans, per-kind opt-in, needs opentelemetry-api.
- Mobile: no ingest endpoint, no header detection, no client SDK. Guide = write your own Api::V1::MobileErrorsController calling LogError with source: :mobile_app. Platform from UA regex (iPhone/iPad/Android/Expo) or explicit arg.
- Platform classes auto = iOS / Android / Mobile / API only. "Web" never auto-assigned; a desktop browser request is classified "API". Job/console are `source` strings, not platforms.
- Real-time: after_create_commit → Turbo::StreamsChannel.broadcast_prepend_to; needs turbo-rails + ActionCable; Turbo JS from jsdelivr CDN.
- AI Help: post :ai_help; BYO key (openai/anthropic); SSE Markdown; nothing persisted; context through filter_sensitive_data; contributed by @antarr 0.7.0 (#123).
- MCP: none (0 hits).

## K1 LLM observability inside a self-hosted in-process tracker — UNIQUE-AMONG-SELF-HOSTED
- "LLM observability for Ruby" is NOT unique: New Relic Ruby agent v9.8.0 auto-instruments ruby-openai (chat/embeddings; ai_monitoring.enabled off by default); Braintrust official Ruby SDK 0.4.1 (2026-08-19) auto-instruments ruby_llm (messages, tokens incl. cached, tool spans, streaming TTFT — captures prompts by default); thoughtbot OTel gem feeds Langfuse/LangSmith/Phoenix via OTLP (no Ruby SDKs); OpenLLMetry Ruby alpha; Helicone/Portkey gateways. Sentry AI Agents Monitoring for Ruby = manual spans only. Datadog LLM Obs: no Ruby SDK (unverified). Honeybadger/AppSignal/Rollbar/Bugsnag/Airbrake/Raygun: none for Ruby.
- No self-hosted tracker (solid_errors, Errbit, Bugsink, GlitchTip, faultline-rails, Telebugs) has LLM call capture.
- Qualifiers: RED's ruby_llm support is thoughtbot's gem + a span processor; Faraday path skips streaming and knows two hosts; content capture unimplemented (privacy-first no-content is a genuine differentiator vs Braintrust/Sentry).

## K2 OTel inbound — SHARED-WITH Sentry (sentry-opentelemetry SpanProcessor consumes ALL spans same-process, links errors via trace context — broader than RED's GenAI-only). AppSignal/Honeybadger product-level only; Datadog OTLP to agent. Among self-hosted Rails trackers RED is the only in-process OTel consumer. Narrow the claim to "GenAI-semconv spans".

## K3 OTel outbound self-instrumentation — UNIQUE (qualified: no competitor found exporting its own capture pipeline as named child spans; Datadog/NR internal telemetry not user-visible as spans, docs unreachable). Constraint: needs opentelemetry-api + host SDK/exporter.

## K4 Mobile — WEAKER-THAN-COMPETITORS. Sentry RN (native crash, source maps, replay, offline), Bugsnag RN, Raygun RN (native crash, offline store-and-resend), Honeybadger RN (auto iOS/Android/JS), Airbrake iOS. RailsNexus same UA tagging. Describe as "mobile-originated errors can be logged through your own API and tagged by platform", not a mobile feature.

## K5 Platform detection/comparison — SHARED-WITH RailsNexus ("Platform Detection — iOS, Android, Web, and API"; "Platform Health — per-platform error rates"), Bugsnag partial (auto app-type rails/rake/sidekiq — the job/console classification RED does NOT do). Fix the "Web"-never-assigned/desktop="API" bug before marketing platform comparison.

## K6 Real-time — UNIQUE-AMONG-SELF-HOSTED (solid_errors no; faultline-rails no broadcast evidence; Errbit no; GlitchTip/Bugsink/Telebugs no mention). Needs turbo-rails + ActionCable; Turbo from CDN.

## K7 AI Help — SHARED-WITH Raygun AI Error Resolution (BYO OpenAI/Azure key, cost pass-through, included with Crash Reporting; not self-hosted). Sentry Seer = vendor-hosted paid add-on $40/active contributor/mo. Honeybadger/AppSignal/Telebugs/Rollbar: MCP only. UNIQUE-AMONG-SELF-HOSTED for an in-dashboard streamed BYO-key drawer. It's Q&A, not Seer-style autonomous fix/PR.

## K8 MCP — GAP (WEAKER). Sentry (mcp.sentry.dev), Honeybadger (hosted + Docker, read-only default), Scout (hosted OAuth, self-hosted option), AppSignal (hosted + Docker proxy), Raygun (hosted PAT), Rollbar (local stdio MIT), **GlitchTip built-in /mcp (17 tools)**, **Telebugs built-in**. Two self-hosted peers ship MCP in-product.

## RailsNexus note
- faultline-rails (tamiru, 1.0.0, 2026-08-21) → github.com/tamiru/rails_nexus (MIT, 0 stars, 2.1.4 on 2026-08-24). Feature list mirrors RED's (platform detection/health, storm protection 50/s, baseline monitoring, correlation insights, N+1, database health). GitHub code search for RailsErrorDashboard/PlatformDetector = 0 hits; no direct code reuse found; manual diff warranted. The 2017 `faultline` gem by k1LoW is unrelated; dlt/faultline (Jan 2026, 87 stars, MCP + local vars) is a THIRD, separate project cited in F/G cohorts.
- Unverified (network): Datadog LLM Obs Ruby, Bugsnag AI, Rollbar AI Assistant, Airbrake Android/RN.
