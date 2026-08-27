# What is actually unique about RED — a verified ledger

> **Date:** 2026-08-27 · **RED version audited:** 0.11.0 · **Companion artifact:** https://claude.ai/code/artifact/27824d8a-9c49-4683-9541-dddb4e9236e4 · **Companion study:** `oss-business-case-file.md`
>
> **Question:** which RED features are not provided by any other product — free or paid — and how much value does RED therefore represent for Rails apps and the people who maintain them?
>
> **Rule for this document:** a feature is only listed as unique if (a) it was found in RED's code, not just its docs, and (b) an adversarial check of every named competitor's docs or source failed to find it. Where a check could not be completed, the row says so. Several claims currently in RED's README, FEATURES.md and ROADMAP.md failed this test and are listed in §8 for correction.

## Contents

1. [The honest answer](#answer)
2. [Method and confidence](#method)
3. [Tier 1 — Unique: no product or gem found, free or paid](#tier1)
4. [Tier 2 — Unique among error trackers (a standalone gem does it)](#tier2)
5. [Tier 3 — Unique among self-hosted Rails tools (a SaaS has it)](#tier3)
6. [Tier 4 — Shared or table stakes: do not market as unique](#tier4)
7. [Gaps: where RED is weaker than competitors](#gaps)
8. [Claims in RED's own docs that must be corrected](#corrections)
9. [What this means for Rails maintainers — the value statement](#value)
10. [Competitive watch: RailsNexus](#nexus)
11. [Evidence index](#evidence)

---

<a id="answer"></a>
## 1. The honest answer

RED's uniqueness is **not** a long list of features nobody else has. Most individual features — local variables, breadcrumbs, N+1 detection, crash capture, cache and ActionCable monitoring, workflow, digests — exist in Sentry, Honeybadger, AppSignal, Datadog or a standalone gem, and three of RED's own "no other tool does this" claims are false.

What survives adversarial checking is narrower and more defensible:

**The defensible headline.** *RED is the only Rails error tracker that records what the process looked like at the moment it failed — GC, memory, file descriptors, load, DB pool, Puma, job queues, RubyVM/YJIT — on the error record itself, inside your app, in your own database, and turns that record into things you can act on: a runnable RSpec test, a curl command, an LLM prompt, an issue in your tracker.* Every competitor has some of those metrics as time-series graphs; none attaches them to the error.

**Nine things nothing else does (free or paid), as far as six verification passes could find:**

| # | Feature | Closest thing elsewhere |
|---|---|---|
| 1 | Runtime state stored on the error record and correlated across errors | Datadog runtime metrics tagged by runtime-id (a graph next to the trace) |
| 2 | "Copy as RSpec" — a runnable spec generated from the captured request | Sentry has "Copy as curl" only |
| 3 | Storm accounting: per-fingerprint caps → context shedding → deterministic sampling; exact count-only mode; async-enqueue gating; a persisted Storm History ledger; on by default | RailsNexus (crude global breaker, random 10%, in-memory, off by default); Sentry client discard reports (protect Sentry's quota, not your DB) |
| 4 | Swallowed-exception *aggregate* — raise-vs-rescue ratio per location, no APM span needed | Datadog detects rescued exceptions (paid, needs a span, no aggregate) |
| 5 | Cross-error analytics: cascades/correlation, occurrence patterns (time-of-day/day-of-week), platform comparison | Not found (Datadog/New Relic UI unverified) |
| 6 | Local `git blame` in the dashboard with no repo OAuth | Sentry/Rollbar suspect commits require a GitHub/GitLab integration |
| 7 | Rack::Attack event ledger with UI, per-discriminator stats and AI-agent user-agent classification | rack-attack ships no UI; nobody subscribes to its events |
| 8 | Codeberg issue tracking (create, auto-create, lifecycle sync, inbound webhooks) | Not found anywhere, including Errbit's plugin ecosystem |
| 9 | The tracker instruments *itself* — exports its own capture pipeline as OpenTelemetry spans so you can audit its overhead in your APM | Not found (vendor internal telemetry is not exposed as spans) |

**Five more that no error tracker integrates, though a standalone gem provides them** (§4): instance variables of `self` at the raise point; production code-path coverage; deprecation tracking; PgHero-style database health; a stored, browsable diagnostic dump.

**Eleven more that no self-hosted Rails tool has, though a SaaS does** (§5) — headed by LLM observability with a strict no-content policy, in-page BYO-key AI help, two-way issue sync, and the widest localisation of any self-hosted Rails tracker.

**And four gaps where RED is behind** (§7): no MCP server (GlitchTip and Telebugs ship one built-in), no mobile SDK or ingest endpoint, no merge/split, no Telegram.

---

<a id="method"></a>
## 2. Method and confidence

Six independent passes on 2026-08-27:

1. **Code audit** of `rails_error_dashboard` 0.11.0 — every claimed feature located in `lib/` or `app/`, with config flag, default, mechanism, constraints and a spec file. 247 spec files. Features that exist only in docs were flagged (§7–8).
2. **Five adversarial competitor checks**, grouped by feature area, each instructed to *disprove* uniqueness and to default to "shared" when in doubt. Evidence is direct fetches of vendor documentation or vendor SDK source on GitHub (agents were cloned and grepped for `TracePoint`, `:rescue`, `at_exit`, `Coverage.`, `each_caller_location`, etc.), plus READMEs of every self-hosted peer.

**Competitor set.** SaaS: Sentry, Honeybadger (+Insights), AppSignal, Rollbar, Bugsnag/Insight Hub, Airbrake, Raygun, New Relic, Datadog, Scout APM, Skylight, RorVsWild, Better Stack, Highlight. Self-hosted / in-app: solid_errors, dlt/faultline, faultline-rails → RailsNexus, Errbit, exception_notification, exception_hunter, Telebugs, GlitchTip, Bugsink. Standalone gems where relevant: better_errors, exception_details, pretty_backtrace, binding_of_caller, Coverband, deep-cover, sigdump, rbtrace, PgHero, Bullet, Prosopite, rack-mini-profiler, deprecation_collector, deprecation_toolkit, next_rails, yabeda-*, Sidekiq Web, mission_control-jobs, good_job, rails_performance, Braintrust, OpenLLMetry-Ruby, thoughtbot's opentelemetry-instrumentation-ruby_llm, Langfuse/LangSmith/Phoenix/Helicone.

**Verdict classes used in every table:**

| Class | Meaning |
|---|---|
| **UNIQUE** | No product or gem found, free or paid |
| **UNIQUE-AMONG-TRACKERS** | A standalone gem provides it; no error tracker integrates it |
| **UNIQUE-AMONG-SELF-HOSTED** | A SaaS has it; no self-hosted Rails tool does |
| **UNIQUE-AT-ERROR-TIME** | Others have the metric as a time-series; nobody attaches it to the error record |
| **SHARED-WITH** | Named competitors have it |
| **TABLE-STAKES** | Standard across the category |
| **GAP** | Competitors have it; RED does not |

**Confidence limits.** Web search quota was exhausted partway through every pass, so evidence is from direct fetches rather than discovery searches; an obscure gem could have been missed (most relevant to Rack::Attack and deprecation rows). From the research sandbox, `docs.datadoghq.com`, `docs.newrelic.com`, `docs.bugsnag.com`, `airbrake.io` did not resolve and `docs.rollbar.com` was behind a challenge page; those vendors were checked through their public SDK source on GitHub instead, and product-UI claims for them are marked *unverified* rather than "No". Every "UNIQUE" verdict below therefore carries the implicit qualifier "…among the 30+ products and gems checked, with Datadog/New Relic/Bugsnag/Airbrake product UIs verified only via SDK source."

---

<a id="tier1"></a>
## 3. Tier 1 — Unique: no product or gem found, free or paid

### 3.1 Runtime state on the error record — UNIQUE-AT-ERROR-TIME (the umbrella)
- **What RED does:** `SystemHealthSnapshot.capture` runs at capture time and stores on the error row: `gc` (heap live/free slots, major GC count, total allocated), `gc_latest`, `process_memory` (VmRSS/VmSwap/VmHWM/Threads from `/proc/self/status`), `thread_count`, `connection_pool` (ActiveRecord `pool.stat`), `puma` (`Puma.stats`), `job_queue` (Sidekiq / SolidQueue / GoodJob auto-detected), `ruby_vm` (`RubyVM.stat`), `yjit`, `actioncable`, `file_descriptors`, `system_load`, `system_memory`, `tcp_connections`. The Job Health and Database Health pages then aggregate these snapshots *across* errors (e.g. sort errors by failed-job count at the time they occurred). — `lib/rails_error_dashboard/services/system_health_snapshot.rb`; spec `spec/services/system_health_snapshot_spec.rb`.
- **Who else:** Datadog runtime metrics (GC.stat, RubyVM.stat, threads, YJIT gauges) tagged `runtime-id` so they correlate to traces — the nearest thing, still a graph next to the trace. Honeybadger Insights Puma plugin + `/proc/meminfo` + loadavg as interval events (opt-in). AppSignal Ruby VM / Process Memory / Puma "magic dashboards" (time-series). New Relic VM snapshot (GC, heap, method/constant cache invalidations, threads) harvested as metrics. Scout memory bloat per request; Skylight allocation hogs; RorVsWild host metrics; rack-mini-profiler per-request GC. **None store it per error.** No self-hosted tool has any of it. Nobody was seen storing file-descriptor or TCP state at all.
- **Constraints to state:** opt-in (`enable_system_health`, default off); procfs fields are Linux-only (nil on macOS); Puma/job/YJIT sections conditional. The Job/DB Health pages are *not live monitors* — they aggregate error rows and are empty without `enable_system_health`.
- **Evidence:** dd-trace-rb `lib/datadog/core/runtime/metrics.rb`; honeybadger-ruby `lib/puma/plugin/honeybadger.rb`, `util/stats.rb`; docs.appsignal.com/metrics/magic-dashboards.html; newrelic-ruby-agent `lib/new_relic/agent/vm/snapshot.rb`; scoutapm.com/docs/features/insights.

### 3.2 "Copy as RSpec" — UNIQUE
- **What RED does:** `RspecGenerator` renders a runnable request spec from the captured method, path, params and headers; `CurlGenerator` renders the curl equivalent. — `lib/rails_error_dashboard/services/rspec_generator.rb`, `curl_generator.rb`; view `_request_context.html.erb`.
- **Who else:** Sentry's Request section has a curl toggle on every event (`static/app/components/events/interfaces/request/index.tsx`) — so **"Copy as curl" is SHARED-WITH Sentry**. No tracker generates a test. A GitHub-wide code search for `"Copy as RSpec"` returns only `AnjanJ/rails_error_dashboard`. Honeybadger exports Markdown/JSON; nobody else was found.
- **Constraint:** only when request context is present.

### 3.3 Storm accounting — UNIQUE mechanics (the phrase "storm protection" is now shared)
- **What RED does:** `StormProtection::Gate` runs after the exception filter: per-fingerprint per-minute caps with context shedding then deterministic sampling (fresh exemplar kept each minute); a global `CircuitBreaker` (closed → shedding → open → half-open) that flips to count-only mode under sustained floods with exact in-memory counts (`Concurrent::AtomicFixnum`) reconciled to error records every 30 s; async-mode gating (an enqueue is itself a DB write); one storm notification instead of hundreds; auto-issue creation capped (default 5 per 10 min, consumed by `IssueTrackerSubscriber`); a persisted `storm_events` table and Storm History page with exact shed counts and peak rates ("Counting is exact — no extrapolation", `count_buffer.rb:15`); fails open. **On by default** (`enable_storm_protection = true`). Shipped 0.8.2 on 2026-06-22. — `lib/rails_error_dashboard/services/storm_protection/`; specs in `spec/services/storm_protection/`, `spec/system/storm_protection_ui_spec.rb`.
- **Who else:** **RailsNexus** (ex faultline-rails, CHANGELOG 1.1.0 dated 2026-08-22, two months after RED): a single global counter at 50/s, when open `rand < 0.1` random pass-through (not count-only), shed counts in memory only, one `Rails.logger.warn`, no persistence or history page, no async gating, no per-fingerprint buckets, off by default. **Sentry**: server-side Spike Protection ("dynamic rate limit… discarding events") protects Sentry's quota, not your database; SDK client reports count discards by reason and the Stats page shows "Client Discard" — a real dropped-events ledger, but "no SDK-side mechanism caps events per fingerprint per minute". Honeybadger: quota throttling to one notification/min at 100%, client queue drops "only logged, not counted". Bugsnag/Airbrake: client queue of 100, drops logged. New Relic: silent per-harvest caps (20 traces / 100 events). exception_notification: log2 notification grouping only. solid_errors, exception_hunter: nothing — every occurrence is a DB write. Errbit/GlitchTip/Bugsink/Telebugs: separate apps; nothing documented.
- **Answer to the core question:** RailsNexus is the only other in-app tracker that protects the host database during a storm, crudely; Sentry is the only other tool with an honest ledger of what it dropped, and it protects Sentry. **Avoid the sentence "the only Rails gem with storm protection."**
- **Constraint:** per-process state. See §7 on the unreproducible overhead figure.

### 3.4 Swallowed-exception aggregate — detection SHARED-WITH Datadog; the aggregate is UNIQUE
- **What RED does:** a `TracePoint(:raise)` + `TracePoint(:rescue)` pair records raise and rescue locations per thread, LRU-bounded, flushed to a `swallowed_exceptions` table; an aggregate page shows raise-count vs rescue-count per location with a ratio threshold (default 0.95). **Ruby 3.3+ hard gate** (auto-disables with a warning below). Default off. — `services/swallowed_exception_tracker.rb`; `spec/services/swallowed_exception_tracker_spec.rb`, `spec/requests/swallowed_exceptions_spec.rb`.
- **Who else:** **Datadog dd-trace-rb ≥ 2.16.0** Error Tracking handled errors: `DD_ERROR_TRACKING_HANDLED_ERRORS=user|third_party|all`; source comment "`:rescue` event was added in Ruby 3.3 … event = RubyVersion.is?('>= 3.3') ? :rescue : :raise". Requires an active APM span; each rescued exception becomes an Error Tracking issue; no raise/rescue ratio or pattern page. Faultline, solid_errors, Sentry, Honeybadger: only exceptions explicitly routed through `Rails.error.handle`. No `:rescue` TracePoint in Sentry, Honeybadger, Rollbar, Bugsnag, AppSignal, Airbrake. RubyGems search: no runtime gem besides RED (only static linters: `rubocop-swallow-exception`, `Lint/SuppressedException`).
- **Defensible wording:** "Only Datadog's paid APM detects rescued exceptions (Ruby 3.3+, needs a span); RED does it free, without an APM span, and aggregates raise/rescue ratios by location. No self-hosted or free tracker does this at all." The README's "No tool detects silently rescued exceptions" is **false**.

### 3.5 Cross-error analytics: cascades, occurrence patterns, platform comparison — UNIQUE (qualified)
- **What RED does:** `CascadeDetector` + `cascade_patterns` table (errors that follow other errors), `ErrorCorrelation` with Pearson correlation, `PatternDetector` (time-of-day / day-of-week / business-hours occurrence patterns), `PlatformComparison` (per-platform error rates and baselines). All behind `enable_error_cascades`, `enable_error_correlation`, `enable_occurrence_patterns`, `enable_platform_comparison` (default off). — `services/cascade_detector.rb`, `queries/error_correlation.rb`, `services/pattern_detector.rb`, `queries/platform_comparison.rb`; specs exist for each.
- **Who else:** Not found in any fetched documentation. Sentry has trace-connected issues (not documented on fetched pages) and exposes platform as a tag/filter; Raygun alert filters by platform. RailsNexus's README lists "Correlation Insights — time-based, controller-based, and user-based" and "Platform Health — per-platform error rates" (2026-08-21; see §10).
- **Constraint:** Datadog and New Relic product UIs were not fetchable; RED's platform classifier has a bug that undermines "platform comparison" until fixed (§7, K5).

### 3.6 Local git blame with no repo OAuth — UNIQUE
- **What RED does:** `GitBlameReader` shells out to `git blame` on the dashboard host's checkout at display time; `SourceCodeReader` reads source from `Rails.root` with path validation; `GithubLinkGenerator` builds links for GitHub, GitLab, Bitbucket, Codeberg, Gitea and Forgejo from a configured repo URL. Default off. — `services/git_blame_reader.rb`, `source_code_reader.rb`, `github_link_generator.rb`.
- **Who else:** inline source is table stakes (Sentry `context_lines`, Honeybadger `source_radius`, Bugsnag `send_code`, Airbrake `code_hunks`, Rollbar opt-in, Faultline side-by-side view) — those SDKs snapshot source *at capture*. **Blame is different:** Sentry suspect commits and Rollbar "blame info" require a GitHub/GitLab integration; AppSignal only links out. No self-hosted tool has blame.
- **Constraint:** source and the `git` binary must be present on the dashboard host.

### 3.7 Rack::Attack event ledger with UI — UNIQUE (search-limited)
- **What RED does:** subscribes to `throttle.rack_attack`, `blocklist.rack_attack`, `track.rack_attack`; thread-local LRU counts persisted to a `rack_attack_events` table (at_exit flush, independent of breadcrumbs); a summary page with per-discriminator stats; and an AI-agent user-agent classifier (GPTBot, ClaudeBot, …) for `track` events. Default off; requires the `rack-attack` gem. — `subscribers/rack_attack_subscriber.rb`, `services/rack_attack_tracker.rb`, `services/ai_agent_classifier.rb`.
- **Who else:** rack-attack itself ships no UI ("subscribe to events and log it, graph it"); `rack-attack-admin` does not exist on RubyGems; no `*.rack_attack` subscription in Honeybadger, Sentry, AppSignal, New Relic or Datadog event lists; `yabeda-rack-ratelimit` targets a different gem. Datadog ASM/WAF is a separate product.
- **Constraint:** no discovery search was possible, so a small unknown gem could exist; anyone can wire the notifications to StatsD in ten lines. The AI-agent classifier is not mentioned in the README (undersold).

### 3.8 Codeberg issue tracking — UNIQUE
- **What RED does:** `CodebergIssueClient` alongside GitHub, GitLab and Linear: manual create, link existing, auto-create by severity (storm-capped), lifecycle jobs (close/reopen linked issue, recurrence comment), inbound webhook handler with signature verification, dashboard mirroring of issue state. — `services/codeberg_issue_client.rb`, `app/controllers/rails_error_dashboard/webhooks_controller.rb`.
- **Who else:** Not found in Sentry (20 integrations, no Codeberg), Honeybadger, Rollbar, Raygun, AppSignal, Scout, Better Stack, New Relic, Errbit (GitHub built in; no Codeberg/Forgejo plugin found), Faultline (GitHub only). The rest of the issue-tracker feature (two-way sync, webhooks, Linear, storm-capped auto-create) is Tier 3.

### 3.9 The tracker instruments itself via OpenTelemetry — UNIQUE (qualified)
- **What RED does:** `Tracer.in_span` wraps the capture pipeline in `rails_error_dashboard.*` child spans (`capture`, `breadcrumbs`, `health`, `notifications`, per-kind opt-in) with version/service attributes, so a host running an OTel SDK sees the tracker's own cost in its APM. Needs only `opentelemetry-api`; NoopSpan without it. Default off. — `integrations/tracer.rb`, `o_tel.rb`; `spec/integrations/otel_export_end_to_end_spec.rb`.
- **Who else:** Sentry's `sentry-opentelemetry` is inbound only; Datadog and New Relic have internal supportability telemetry that is not exposed as user-visible spans (their docs hosts were unreachable — treat as "not found", not "no"). No self-hosted peer.
- **Constraint:** only emitted when the host has configured an SDK/exporter.

---

<a id="tier2"></a>
## 4. Tier 2 — Unique among error trackers (a standalone gem does it)

| Feature | RED mechanism & constraints | Standalone gem that does it | Trackers |
|---|---|---|---|
| **Instance variables of `self` at the raise point** | Same `TracePoint(:raise)` as locals; reads `tp.self.instance_variables`; `enable_instance_variables` (off), max 20, filtered. | better_errors, exception_details — **dev-only** (binding_of_caller; "do NOT run in production"). Datadog Dynamic Instrumentation captures `tp.self` on demand, not at raise. | Sentry: locals only. Honeybadger/Rollbar: bindings kept, only locals exported. Faultline: serialises ivars of objects that appear as local *values*, never the receiver. **Wording:** "no tracker captures `self`'s instance variables at the raise point" — not "no tool". |
| **Production code-path coverage in the dashboard** | `Coverage.setup(oneshot_lines: true)` + `Coverage.resume`, `peek_result` per file, toggled from the dashboard, shown inline with source; piggybacks SimpleCov if present. `enable_coverage_tracking` (off). Ruby 3.2+. | **Coverband** — richer: Redis-persisted, per-file %, dead-code review, mountable UI, oneshot mode. deep-cover/simplecov are test-time. | Zero trackers touch Ruby's `Coverage` API (grep of every agent's `lib/`). **Must state:** diagnostic mode, process-global (multi-threaded Puma blends results), in-memory, no persistence. |
| **Deprecation warning tracker with aggregate page** | Breadcrumb subscriber on `deprecation.rails`; aggregate page. | **deprecation_collector** (Vasfed) — production-suitable, Redis, mountable rack app, counts, fingerprinter — and *broader*: not error-gated. deprecation_toolkit/next_rails are test-time. | No tracker subscribes to `deprecation.rails` (Sentry's `active_support_logger` list omits it). **Two caveats:** RED only records deprecations that fired inside requests that later raised; and it only works if the host's deprecation behaviour includes `:notify` — the gem never sets this and the docs don't say so, so a production default yields an empty page. |
| **PgHero-style database health inside the tracker** | Live `DatabaseHealthInspector` (`pg_stat_user_tables`/`pg_stat_user_indexes`/activity: table sizes, unused indexes, dead tuples, vacuum) plus historical pool-at-error-time from snapshots. **PostgreSQL-only** for the live section. | **PgHero** — far deeper (query stats, explain, kill, index suggestions, tuning). yabeda-activerecord pool metrics. | No tracker embeds pg_stat views (Honeybadger only `sql.active_record`; AppSignal none; Sentry DB spans; Scout slow-query insights). Pool-at-error-time is UNIQUE-AT-ERROR-TIME. |
| **Stored, browsable diagnostic dump** | `DiagnosticDumpGenerator`: health snapshot + `Thread.list` (names/status, no backtraces) + `GC.stat` + `ObjectSpace.count_objects` + breadcrumbs + uptime → `diagnostic_dumps` table; triggered from the dashboard or `rake error_dashboard:diagnostic_dump`. No `Signal.trap` (banned by rule #9). `enable_diagnostic_dump` (off). | **sigdump** (SIGCONT → thread backtraces + object counts + GC profile to /tmp), **rbtrace** (attach; backtraces, ObjectSpace), Puma `INFO` signal (thread backtraces). | New Relic thread profiler is UI-started but threads-only. AppSignal `diagnose` is a config check. Faultline's README explicitly excludes "memory profiling or GC introspection". The bundled, stored, browsable snapshot is unique among trackers; "on-demand snapshot" as a category is not. ROADMAP item P's `USR1` wording is stale. |

---

<a id="tier3"></a>
## 5. Tier 3 — Unique among self-hosted Rails tools (a SaaS has it)

| Feature | Who has it in SaaS | Self-hosted peers | RED's qualifiers |
|---|---|---|---|
| **LLM observability inside the error tracker** — call breadcrumbs (provider/model/latency/tokens/cost), tool-call tracking, per-model health page, LLM context in Copy-for-LLM | **New Relic** Ruby agent ≥9.8 auto-instruments `ruby-openai` (chat/embeddings; off by default). **Braintrust** official Ruby SDK 0.4.1 (2026-08-19) auto-instruments `ruby_llm` (messages, tokens incl. cached, tool spans, streaming TTFT — captures prompts by default). Langfuse/LangSmith/Phoenix accept OTLP (no Ruby SDKs); Helicone/Portkey are gateways. Sentry AI Agents Monitoring for Ruby = manual spans only. Datadog LLM Obs: no Ruby SDK (unverified). Honeybadger/AppSignal/Rollbar/Bugsnag/Airbrake/Raygun: none for Ruby. | None (solid_errors, Errbit, Bugsink, GlitchTip, Faultline, RailsNexus, Telebugs) | Three paths, **none automatic**: Faraday middleware the host inserts (recognises `api.openai.com` / `api.anthropic.com`, skips streaming); GenAI-semconv spans via thoughtbot's `opentelemetry-instrumentation-ruby_llm`; manual `AS::Notifications.instrument("red.llm_call")`. Cost table hard-coded. **Privacy is the real differentiator:** `llm_observability_content_capture` is a reserved no-op — prompts and completions are never captured, versus Braintrust/Sentry which capture messages. |
| **Copy for LLM** — one signal-optimised bundle incl. filtered locals/ivars and system health | **Better Stack** "AI prompt tab" (ready-made prompt for Claude Code/Cursor, editable template with variables); Honeybadger Markdown export (partial). | None — the self-hosted field converged on MCP servers instead | RED's bundle is the only one that includes variables and runtime state; Better Stack's template editor is ahead. |
| **BYO-key AI Help streamed in the error page** | **Raygun** AI Error Resolution (your OpenAI/Azure key, conversation history; not Anthropic). Sentry Seer is vendor-hosted, $40/active contributor/month. | None | Q&A drawer, not Seer-style autonomous fix/PR; nothing persisted; context passes through the sensitive-data filter; contributed by @antarr (0.7.0, #123). |
| **Two-way issue lifecycle sync + inbound webhooks + Linear + storm-capped auto-create** | Sentry (GitHub two-way; auto-create is Business-plan gated); Raygun and Rollbar (Jira two-way); Honeybadger Linear one-direction state mapping. | Faultline: GitHub one-way. Errbit: GitHub + plugin gems. | No competitor page mentions a rate cap on auto-created issues. |
| **Scheduled digests** (daily/weekly mail) | Sentry weekly, Honeybadger daily/weekly, Raygun 24 h. | None documented (Faultline, Telebugs, GlitchTip, Bugsink, Errbit) | `enable_scheduled_digests` (off); host must schedule the job. |
| **Baseline anomaly alerts, priority scoring, similar errors, user impact** | Sentry (dynamic thresholds on metric alerts; auto priority on Business; Similar Issues; users-affected); Telebugs has spike rules. | None | Baseline = mean + stddev with outlier removal, throttled; spike detection and priority score are always on. |
| **Swallowed-exception detection at all** | Datadog (paid APM, Ruby 3.3+, needs a span). | None | See §3.4 — RED is free and needs no span. |
| **11-locale UI, localised emails and notification payloads** | Sentry: 14 selectable UI languages (45 locale dirs, Transifex, many partial). Honeybadger/AppSignal/Rollbar/Raygun/Scout/RorVsWild/Better Stack: none found. New Relic/Datadog unverified. | Errbit: en, pt-BR. GlitchTip: fr, nb. Faultline/solid_errors/Telebugs/Bugsink: none. | Most of any self-hosted Rails tool; only one found localising notification payloads. Ten of eleven are machine-translated and unreviewed (already stated in README). |
| **Live dashboard updates** (Turbo Streams) | SaaS UIs are live. | None documented (solid_errors, Faultline, Errbit, GlitchTip, Bugsink, Telebugs) | Requires `turbo-rails` + an ActionCable adapter in the host; **no polling fallback**; Turbo pulled from a CDN. |
| **Multi-app in one database** among in-process engines | SaaS "projects"; Errbit, GlitchTip, Bugsink, Telebugs as separate apps. | solid_errors, exception_hunter, RailsNexus: none | App-name auto-detection not claimed by any peer. |
| **In-process OpenTelemetry consumer** | Sentry's `sentry-opentelemetry` SpanProcessor consumes *all* same-process spans (broader). | None | RED ingests **GenAI-semconv spans only** into `llm`/`llm_tool` breadcrumbs — say "GenAI spans", not "OTel in + out". |

---

<a id="tier4"></a>
## 6. Tier 4 — Shared or table stakes: do not market as unique

| Feature | Verdict | Who has it | Note |
|---|---|---|---|
| Local variables at raise | TABLE-STAKES | Sentry (`include_local_variables`/`data_collection.stack_frame_variables` — same `TracePoint(:raise)` mechanism, free SDK option, opt-in), Honeybadger (binding_of_caller), Rollbar (per-frame locals via call/return TracePoint), Faultline (always on), Bugsink displays sentry-ruby's `vars`. Dev-only: better_errors, exception_details, pretty_backtrace. | RED's edge is packaging only: opt-in, Rails `filter_parameters` reuse, size limits, no Binding retention. Honeybadger and Rollbar also scrub locals; Sentry says "use `before_send`". |
| `at_exit` crash capture | TABLE-STAKES | Honeybadger `notify_at_exit` (default on), Bugsnag automatic, AppSignal `enable_at_exit_reporter` (default on); Datadog native crashtracker covers segfaults, which `at_exit` never sees. | RED's JSON-file-then-import-at-boot design is an implementation detail. |
| Breadcrumbs via ActiveSupport::Notifications | TABLE-STAKES | Honeybadger on by default since 4.6.0; Bugsnag automatic; Sentry one config line; Telebugs/GlitchTip/Bugsink via the Sentry SDK. | **RED's default is off** (`enable_breadcrumbs = false`) — less zero-config than Honeybadger/Bugsnag. RED-only categories: `deprecation`, `llm`, `llm_tool`, rack-attack, active_storage. |
| N+1 detection | SHARED-WITH | Sentry (first-class N+1 performance issues, needs tracing), AppSignal, Scout, Skylight; Bullet/Prosopite dev/staging. | RED flags N+1 only in errored requests (≤40 breadcrumbs), display-time, no tracing needed. |
| Cache health | SHARED-WITH | Sentry Caches module (miss rate, throughput; needs tracing); Honeybadger Insights partial. | RED's aggregate is computed only from cache ops inside errored requests — a biased sample. |
| ActionCable monitoring | SHARED-WITH | AppSignal out-of-the-box (subscriptions, messages, channel errors); Sentry (channel errors + `websocket.server` transactions); New Relic broadcast metrics; Datadog traces; yabeda-actioncable (connection counts, rejections). | RED residual: rejection counts per channel + live connection count on the error. |
| Job health | SHARED-WITH | Honeybadger Insights (Sidekiq/SolidQueue stats + dashboards), AppSignal, Sentry Queues (partial); standalone Sidekiq Web, mission_control-jobs, good_job. | RED stores queue counters *per error* (unique in that respect) but is not a live queue view. |
| YJIT / RubyVM.stat | SHARED-WITH | Datadog (full YJIT gauges + constant/method cache), New Relic (cache invalidations, no YJIT), AppSignal (RubyVM.stat, no YJIT) — as time-series. | Per-error attachment is unique (§3.1). ROADMAP X's "delta between captures" is not shipped. |
| Workflow (statuses, assign, priority, comments, batch, auto-reopen, custom fingerprint) | TABLE-STAKES | Sentry, Honeybadger, New Relic, Raygun, Scout, Telebugs. | Among self-hosted Rails tools, assignment + comments + priority together = only RED and Telebugs. **RED has no merge/split.** |
| Cooldown, threshold milestones, mute, snooze | TABLE-STAKES | Sentry, AppSignal, Raygun, Telebugs, Bugsink; exception_notification log2 grouping; **Faultline's `on_threshold: [10,50,100,500]` + 5-min cooldown is a near clone of RED's**. | — |
| Plugin system / callbacks | TABLE-STAKES | Honeybadger `Plugin.register`, Sentry `before_send`/integrations, Bugsnag `on_error`, exception_notification notifiers, Errbit gem plugins. | RED's eight lifecycle events are richer than in-app peers. |
| Async via the app's job backend with sync fallback | SHARED-WITH | Rollbar (`use_active_job`/`use_sidekiq`/… + failover handlers), exception_hunter. | RED's differentiator is the storm-mode enqueue gating, not async itself. GoodJob is detected for stats but is not an `async_adapter` option. |
| PG/MySQL/Trilogy/SQLite, same or separate DB | SHARED-WITH | solid_errors (same adapters + `connects_to`, incl. primary/replica). | BRIN + functional indexes are RED-only but an implementation detail. |
| No asset-pipeline dependency | SHARED-WITH | solid_errors — and stricter: inline Tailwind, nonce'd inline script, **zero CDN**. | RED loads Bootstrap, Bootstrap Icons, Chart.js, Chartkick, highlight.js and Google Fonts from CDNs. Don't claim a CSP advantage. |
| Unlimited errors/projects/users, MIT | TABLE-STAKES among self-hosted OSS | solid_errors, Errbit, exception_hunter, RailsNexus (MIT); GlitchTip (MIT), Bugsink (free self-host), Telebugs ($299 once). Verified SaaS free tiers: Sentry 5k errors/1 user/30 days; Honeybadger 5,000/1 user/15 days; AppSignal 50K requests/5-day retention; Rollbar 5K + 1K sessions/30 days; Raygun no free plan. | Bugsnag/Airbrake free-tier numbers unverified. |
| Inline source viewer | SHARED-WITH | Every major SaaS SDK (snapshot at capture) + Faultline. | Blame is the unique part (§3.6). |
| Sensitive-data filtering across params, locals, breadcrumbs | SHARED-WITH | Honeybadger and Rollbar scrub locals; Bugsnag scrubs breadcrumbs. | LLM-path filtering not compared against Sentry Seer / Honeybadger AI privacy pages. |
| Dark mode, keyboard shortcuts | TABLE-STAKES | Sentry, Telebugs (whose command palette is ahead of RED's `?`). | — |
| Platform detection | SHARED-WITH | RailsNexus (iOS/Android/Web/API + per-platform health); Bugsnag auto app-type (rails/rake/sidekiq). | See the classifier bug in §7. |

---

<a id="gaps"></a>
## 7. Gaps: where RED is weaker than competitors

| Gap | Who has it | Note |
|---|---|---|
| **No MCP server** (confirmed: zero hits in `lib/`, `app/`, docs) | Sentry (hosted, OAuth), Honeybadger (hosted + Docker, read-only by default), Scout (hosted OAuth, self-hosted option), AppSignal (hosted + Docker proxy), Raygun (hosted PAT), Rollbar (local stdio, MIT), **GlitchTip built-in `/mcp` (17 tools)**, **Telebugs built-in**, dlt/faultline built-in. | Two self-hosted peers ship it in-product, so "self-hosted" is no longer a reason. RED's local DB makes a private MCP server trivial — the largest cheap win in this document. |
| **Mobile: guide only** — no ingest endpoint, no header detection, no client SDK, no symbolication, no offline queue | Sentry, Bugsnag, Raygun, Honeybadger native React Native SDKs; Airbrake iOS. RailsNexus does the same UA tagging as RED. | The gem's contribution is a User-Agent regex (iPhone/iPad/Android/Expo) plus `ManualErrorReporter`. Describe as "mobile-originated errors can be logged through your own API and tagged by platform". README's "React Native, Flutter" over-implies. |
| **Platform classifier bug** | — | Auto classes are iOS / Android / Mobile / API only; "Web" is never auto-assigned; a desktop browser request is labelled **"API"**; job and console are `source` strings, not platforms. Fix before marketing platform comparison. |
| **No merge/split** | Sentry (merge + unmerge), Honeybadger, Raygun, Telebugs. | ROADMAP item 7 still open; `docs/features/ADVANCED_ERROR_GROUPING.md` is about similarity/cascades, not grouping controls. |
| **No Telegram (or Teams)** | dlt/faultline, RailsNexus, Telebugs. | ROADMAP 7a open. |
| **Real-time has no fallback** | — | Requires `turbo-rails` + ActionCable pubsub; otherwise nothing refreshes (gemspec's "falls back to page refresh" means a manual refresh). |
| **Not air-gap clean** | solid_errors (zero CDN). | Third-party CSS/JS/fonts from jsdelivr and Google; the gem's own CSS/JS is inline. |
| **Deprecation tracking silently empty in production** | deprecation_collector works regardless. | Needs host `:notify` deprecation behaviour; undocumented. |
| **Overhead figure not reproducible** | — | README's 2.4 µs / 2.95 µs / 0.2 µs exists nowhere in `lib/`, `spec/`, `bin/` or CHANGELOG; only a "Benchmarked." comment in `gate.rb:21`. Add a benchmark script or label it as a single-machine maintainer measurement. |
| **No health-check endpoint, no JSON API** | GlitchTip/Bugsink/Telebugs have APIs; ROADMAP 14 open, JSON API iceboxed. | Both come up in procurement questionnaires. |
| **No lazy backtrace via `Thread.each_caller_location`** | Sentry ships it; Rails core uses it. | ROADMAP Y is not implemented (0 hits). Don't market. |
| **Runtime snapshot was first-occurrence only — FIXED on `fix/refresh-context-on-recurrence` (ROADMAP C2)** | Datadog runtime metrics are continuous. | Until that lands, `FindOrIncrementError#increment_existing` refreshed count/last_seen/user/request only; now `system_health`, variables, breadcrumbs and HTTP context are overwritten on every captured occurrence (storm-shed captures leave the previous payload). Per-occurrence history is still not stored — say "refreshed on every captured occurrence", not "history of every occurrence". |

---

<a id="corrections"></a>
## 8. Claims in RED's own docs that must be corrected

| # | Where | Current text | Finding | Suggested replacement |
|---|---|---|---|---|
| 1 | `README.md` L69; L663–664 (FAQ) | "Pay extra for local variable capture (Sentry)" / "a capability Sentry charges extra for" | **False.** `include_local_variables` is a free, opt-in SDK boolean; sentry.io/pricing gates volume only; Bugsink renders the same payload free. | "Local variables are opt-in in Sentry's SDK; RED enables local **and instance** variables with Rails `filter_parameters` scrubbing out of the box." |
| 2 | `README.md` L70 | "No tool detects silently rescued exceptions" | **False.** Datadog dd-trace-rb ≥ 2.16 handled-errors uses the same Ruby 3.3 `:rescue` TracePoint. | "Only Datadog's paid APM detects rescued exceptions (Ruby 3.3+, needs a span); RED does it free, without APM, and aggregates raise/rescue ratios by location." |
| 3 | `README.md` L440 | "No other error tracker does this" | Over-broad; true only per the tiers above. | Qualify per feature. |
| 4 | `README.md` L697 | "Seven shipped locales" | Eleven everywhere else. | "Eleven". |
| 5 | `docs/FEATURES.md` L433 | "Unlike Sentry or Honeybadger (which require SDK configuration)" | **False.** Honeybadger breadcrumbs on by default since 4.6.0; Bugsnag automatic; Sentry one array. RED's own default is off. | Drop the comparison; list RED-only categories instead. |
| 6 | `docs/FEATURES.md` L958 | "No error tracker (Sentry, Honeybadger, Faultline) surfaces ActionCable health alongside HTTP errors" | **False.** AppSignal out-of-the-box; Sentry channel errors + transactions. | "RED stores per-channel rejection counts and live connection count on the error record." |
| 7 | `ROADMAP.md` item B | "no error tracker does this" (N+1) | **False.** Sentry N+1 issues; AppSignal, Scout, Skylight. | "Without tracing, on the errored request, self-hosted." |
| 8 | `ROADMAP.md` item E | "No competitor does this" (Copy as curl/RSpec) | Sentry has had a curl view for years; RSpec half stands. | "No competitor generates a runnable test; Sentry offers curl only." |
| 9 | `ROADMAP.md` item P | `Signal.trap("USR1")` | Not shipped; rule #9 bans `Signal.trap`. | Dashboard button + rake task. |
| 10 | `ROADMAP.md` item V | "unique, no competitor has this" (coverage) | True among trackers only; Coverband. | "No error tracker integrates it; Coverband does it standalone." |
| 11 | `ROADMAP.md` item X | "Track delta between captures to detect rapid invalidation" | Not shipped; only raw counters. | Mark open or remove. |
| 12 | `ROADMAP.md` L32 | "OpenTelemetry: In + out" | Inbound is GenAI-semconv spans only. | "Exports its own spans; consumes GenAI spans for LLM observability." |
| 13 | `ROADMAP.md` L36 | "Dependencies: 2 required" | Three: pagy, groupdate, concurrent-ruby (+ rails). | "3 runtime deps". |
| 14 | `README.md` L706; `docs/guides/MOBILE_APP_INTEGRATION.md` | "React Native, Flutter, etc." | Host-written endpoint; no SDK. | See §7. |
| 15 | `CHANGELOG.md` L1059; README | "fully self-contained / zero asset pipeline dependency" | True for the gem's own CSS/JS only. | "No asset-pipeline dependency; third-party JS/CSS loaded from CDN." |
| 16 | `README.md` L101 | 2.4 µs / 2.95 µs / 0.2 µs | Unreproducible. | Add `bin/benchmark-storm` or label as "maintainer measurement, single machine". |
| 17 | `docs/FEATURES.md` L681–729 | Job Health / Database Health | Error-row aggregation, not live; live DB stats PostgreSQL-only. | State both. |
| 18 | `docs/guides/REAL_TIME_UPDATES.md`; gemspec L91 | "falls back to page refresh" | No auto fallback. | State the requirement. |
| 19 | `docs/FEATURES.md` L457–478 | Deprecation warnings | Requires host `:notify`; only errored requests. | Document both. |
| 20 | `docs/FEATURES.md` L22; LLM sections | "24+ features"; LLM captured "automatically" | ~35 `enable_*` switches; nothing auto-instruments any LLM SDK. | Count switches; say "via Faraday middleware, OTel GenAI spans, or manual instrumentation". |

---

<a id="value"></a>
## 9. What this means for Rails maintainers — the value statement

Put the ledger in the words of the person who runs a Rails app and gets paged:

1. **You see what the process looked like when it broke, not just the stack.** Heap and GC state, RSS, thread count, file descriptors, load, the AR pool's busy/waiting counts, Puma's backlog, how deep the job queues were, YJIT stats — captured at the raise and kept with the error. Every APM shows you a graph you then have to line up by timestamp; RED puts the numbers on the error. That is the single capability nobody else has, and it is the one that answers "why did this only happen at 3 a.m. under load?"

2. **It watches things you never asked an error tracker to watch.** Exceptions that were rescued and swallowed (with the ratio per location), deprecations that fired in production, what Rack::Attack throttled and which AI crawlers it was, which lines of code actually ran in production. Each of these exists as a separate gem you would have to install, mount and remember to look at; RED puts them beside the errors.

3. **An error becomes something you can run.** Copy as RSpec gives you a failing test from the captured request; Copy as curl reproduces it; Copy for LLM hands an assistant the filtered variables and runtime state; the issue lands in GitHub, GitLab, Codeberg or Linear and closes itself when you resolve it.

4. **All of it inside your app, in your database, with no data leaving.** Same as solid_errors and RailsNexus — but with the depth above, and with storm accounting that will not let a bad deploy amplify itself into your database (RailsNexus's breaker is random sampling with no ledger; solid_errors has nothing).

5. **Free, MIT, no caps** — table stakes among self-hosted tools, a real difference against the 5,000-errors-a-month SaaS free tiers.

**How much value is that?** Enough to be the default for a Rails team that cannot or will not send error data to a SaaS and wants more than solid_errors; not enough on its own to displace Sentry or Honeybadger for a team that already pays them — RED lacks their mobile SDKs, merge/split, MCP servers and hosted operations. The honest positioning is "the forensic, self-hosted one": the tool that records the most about the moment of failure, and keeps it on your side of the firewall. The 2026 gaps that most weaken that story (no MCP, platform classifier bug, unreproducible benchmark, deprecations silently empty) are all small.

---

<a id="nexus"></a>
## 10. Competitive watch: RailsNexus

Verified directly against GitHub and RubyGems on 2026-08-27:

- `tamiru/rails_nexus` — created **2026-08-21**, MIT, 0 stars, last push 2026-08-27; published as `faultline-rails` 1.0.0 then renamed `rails_nexus` (2.1.4 on 2026-08-24). RubyGems downloads: 5,660 + 4,866 in six days (likely CI).
- Its README feature list mirrors RED's almost item for item: Storm Protection (circuit breaker), User Impact Ranking, Platform Detection (iOS/Android/Web/API), Platform Health, Correlation Insights (time/controller/user), Baseline Monitoring, Occurrence Patterns (cyclical and burst), N+1 Query Detection, Server Statistics (RAM/swap, load, Puma workers, Sidekiq stats), Database Health (pool, table stats, index usage, missing indexes, slow queries), Snooze (1h/4h/1d/1w), Mute, Comments, Inline Source + Git Blame, Keyboard Shortcuts, Dark/Light. It also has things RED does not: **Telegram notifier, cron job monitoring, RSS feed, Ransack search**.
- GitHub code search for `RailsErrorDashboard` / `PlatformDetector` inside it returned zero hits — **no direct code reuse found**; a manual diff of the storm-protection and baseline code is warranted.
- It is a different project from `dlt/faultline` (Jan 2026, 87 stars, MCP + local variables, quiet since May) and from the 2017 `faultline` gem.

Implication: several Tier-1/Tier-3 rows above ("cascades/correlation", "platform comparison", "occurrence patterns", "storm protection") now have a six-day-old MIT competitor claiming the same headings. RED's verified edge is depth (per-error snapshots, exact storm accounting, aggregate swallowed-exception analysis, the RSpec generator) and eight months of releases; the headings themselves are no longer unique. Re-run this ledger against RailsNexus's code, not just its README, before quoting any Tier-1 claim it touches.

---

<a id="evidence"></a>
## 11. Evidence index

Per-pass notes with every URL and file:line are in `.shipkit/research/evidence-uniqueness/` (00 code audit, 01 deep introspection, 02 runtime health, 03 workflow/output, 04 storm/architecture, 05 LLM/OTel/mobile). Key primary sources by area:

- **RED code:** `lib/rails_error_dashboard/services/{local_variable_capturer,swallowed_exception_tracker,crash_capture,diagnostic_dump_generator,coverage_tracker,system_health_snapshot,rspec_generator,curl_generator,markdown_error_formatter,git_blame_reader,cascade_detector,pattern_detector,ai_agent_classifier,llm_client}.rb`, `services/storm_protection/`, `integrations/{tracer,o_tel,llm_middleware,llm_span_processor}.rb`, `subscribers/{rack_attack,breadcrumb,action_cable,llm_call}_subscriber.rb`, `configuration.rb`, `config/routes.rb`.
- **Sentry:** docs.sentry.io/platforms/ruby/configuration/options/ · sentry-ruby `lib/sentry-ruby.rb#L67-L81`, `lib/sentry/backtrace.rb#L31-L47` · sentry-rails `lib/sentry/rails/{action_cable,railtie}.rb` · sentry `static/app/components/events/interfaces/request/index.tsx` · `static/app/data/languages.tsx` · docs.sentry.io/pricing/quotas/spike-protection/ · develop.sentry.dev/sdk/telemetry/client-reports/ · docs.sentry.io/product/issues/issue-details/performance-issues/n-one-queries/ · docs.sentry.io/product/insights/caches/ · docs.sentry.io/organization/integrations/issue-tracking/ · docs.sentry.io/product/issues/suspect-commits/ · docs.sentry.io/platforms/ruby/tracing/instrumentation/opentelemetry/ · docs.sentry.io/pricing/ (Seer).
- **Honeybadger:** docs.honeybadger.io/lib/ruby/gem-reference/configuration/ · honeybadger-ruby `lib/honeybadger/{plugins/local_variables,singleton,worker,notice}.rb`, `lib/puma/plugin/honeybadger.rb`, `breadcrumbs/active_support.rb`, `plugins/{sidekiq,solid_queue}.rb` · docs.honeybadger.io/guides/errors/ · docs.honeybadger.io/resources/mcp/ · docs.honeybadger.io/resources/quotas/.
- **Datadog:** dd-trace-rb `docs/GettingStarted.md#error-tracking`, `lib/datadog/error_tracking/component.rb`, `lib/datadog/core/runtime/{metrics,ext}.rb`, `docs/DynamicInstrumentation.md`, `lib/datadog/core/crashtracking/component.rb`.
- **New Relic:** newrelic-ruby-agent `lib/new_relic/agent/vm/{snapshot,c_ruby_vm}.rb`, `error_collector.rb`, CHANGELOG (v9.8.0 ruby-openai, v9.3.0 ActionCable) · docs-website thread-profiler-tool.mdx, errors-inbox.mdx.
- **AppSignal:** docs.appsignal.com/metrics/magic-dashboards.html · /ruby/integrations/{ruby-vm,puma,action-cable}.html · /ruby/integrations.html · /alerting.md · appsignal-ruby `lib/appsignal/hooks/at_exit.rb` · github.com/appsignal/appsignal-mcp.
- **Rollbar / Bugsnag / Airbrake / Raygun:** rollbar-gem `lib/rollbar/{notifier/trace_with_bindings,item/locals,configuration}.rb` · bugsnag-ruby `lib/bugsnag.rb#L151-L169`, `integrations/rails/rails_breadcrumbs.rb`, `delivery/thread_queue.rb` · airbrake-ruby `lib/airbrake-ruby/config.rb`, README · raygun.com/ai-error-resolution · raygun.com/documentation (alerts, error statuses, React Native) · github.com/MindscapeHQ/mcp-server-raygun · github.com/rollbar/rollbar-mcp-server.
- **Scout / Skylight / RorVsWild / Better Stack:** scoutapm.com/docs/features/{insights,error-monitoring} · scoutapm.com/docs/ai/mcp/ · skylight.io/support/performance-tips · rorvswild.com/docs/monitoring/requests · betterstack.com/docs/errors/using-the-product/fix-with-ai/.
- **Self-hosted peers:** github.com/fractaledmind/solid_errors · github.com/dlt/faultline · github.com/tamiru/rails_nexus (+ `lib/rails_nexus/storm_protection.rb`, CHANGELOG 1.1.0) · github.com/errbit/errbit · github.com/kmcphillips/exception_notification · github.com/rootstrap/exception_hunter · telebugs.com (mcp-error-tracking, notifications-and-rules, error-grouping, changelog) · glitchtip.com/documentation/mcp · bugsink.com/docs/{api,alerts} · github.com/bugsink/bugsink `issues/templates/issues/_stacktrace_frames.html`.
- **Standalone gems / LLM tools:** github.com/danmayer/coverband · github.com/frsyuki/sigdump · github.com/tmm1/rbtrace · github.com/ko1/pretty_backtrace · github.com/Vasfed/deprecation_collector · github.com/ankane/pghero · github.com/monorkin/yabeda-actioncable · github.com/rack/rack-attack · braintrust.dev/docs/integrations/sdk-integrations/ruby-llm · github.com/thoughtbot/opentelemetry-instrumentation-ruby_llm · github.com/traceloop/openllmetry-ruby · langfuse.com/docs/sdk/overview · arize.com/docs/phoenix/tracing/llm-traces.
