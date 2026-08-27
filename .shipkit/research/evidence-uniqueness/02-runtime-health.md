# G — Runtime-health verification (direct fetch of vendor source/docs; NR/Datadog/Bugsnag docs via GitHub source)

Falsified RED claims: FEATURES.md:433 ("Unlike Sentry or Honeybadger (which require SDK configuration)") — Honeybadger breadcrumbs on by default since 4.6.0, Bugsnag automatic, Sentry one array; FEATURES.md:958 ("No error tracker surfaces ActionCable health") — Sentry + AppSignal do; ROADMAP.md B ("no error tracker does this" for N+1) — Sentry creates first-class N+1 issues; AppSignal/Scout/Skylight detect too.

## G1 System health snapshot at error time — UNIQUE-AT-ERROR-TIME
- Nobody stores a process/VM/pool/Puma/job-queue snapshot on the error record. Nearest: Datadog runtime metrics tagged runtime-id (GC.stat, RubyVM.stat, threads, YJIT gauges) correlate to traces — still a graph next to the trace. Honeybadger Insights Puma plugin (pool_capacity/max_threads/backlog/running) + /proc/meminfo + loadavg as interval events (opt-in). AppSignal Ruby VM/Process Memory/Puma magic dashboards (time-series). New Relic VM snapshot (gc, heap, method/constant cache invalidations, threads) harvested as metrics. Scout memory bloat per request; Skylight allocation hogs; RorVsWild host metrics; rack-mini-profiler per-request GC/memory. None per error. Sentry/Rollbar/Bugsnag/Airbrake/Raygun/solid_errors/Faultline/Errbit/GlitchTip/Bugsink: no.
- Constraints: opt-in; procfs fields Linux-only; Puma/job/YJIT conditional. FDs/TCP storage not seen anywhere.

## G2 Job Health page — SHARED-WITH Honeybadger Insights (stats.sidekiq processed/failed/scheduled/retry/dead/latency/depth; stats.solid_queue), AppSignal (Sidekiq/ActiveJob dashboards; GoodJob/SolidQueue integrations); Sentry Queues partial (tracing); standalone Sidekiq Web, mission_control-jobs, good_job dashboard, yabeda.
- RED's twist: queue counters stored per error, errors sortable by failed-job count; NOT a live queue view. Only Sidekiq/SolidQueue/GoodJob, only at error time, needs enable_system_health.

## G3 Database Health — UNIQUE-AMONG-TRACKERS (Section A live pg_stat; PgHero standalone is far deeper: queries, explain, kill, index suggestions) + UNIQUE-AT-ERROR-TIME (pool stats per error). PostgreSQL-only for live stats. No tracker embeds pg_stat views (Honeybadger only sql.active_record; AppSignal none; Sentry DB spans; Scout slow-query insights). NR/Datadog DBM are separate agents.

## G4 Cache health — SHARED-WITH Sentry Caches module (miss rate/throughput/value size; sentry-rails ActiveSupportSubscriber cache.get/put with cache.hit; requires tracing), Honeybadger Insights partial (13 cache events, BadgerQL). Bugsnag/HB breadcrumbs per error. RED's aggregate = only cache ops inside errored requests (≤40 breadcrumbs) → biased sample, not app-wide. Requires breadcrumbs.

## G5 ActionCable — SHARED-WITH AppSignal (out-of-the-box: subscription events, messages, error tracking in channels), Sentry (exceptions in connect/subscribe/actions + websocket.server transactions + breadcrumbs), New Relic (broadcast metrics 9.3.0), Datadog (broadcast/channel action traces); yabeda-actioncable standalone (connection_count, confirmed/rejected subscriptions, durations). RED residual: rejection counts per channel + live connection count stored on the error. Events only appear when an error occurs in same request/action.

## G6 Rack::Attack tracking — UNIQUE (search-limited). rack-attack ships no UI ("subscribe to events and log it, graph it"); rack-attack-admin does not exist; no *.rack_attack subscription in HB/Sentry/AppSignal/NR/Datadog; yabeda-rack-ratelimit targets a different gem. Anyone can wire to StatsD in ten lines. Requires rack-attack, opt-in. Plus AI-agent UA classifier (code audit).

## G7 Deprecation tracker — UNIQUE-AMONG-TRACKERS. deprecation_collector (Vasfed) standalone: production-suitable, Redis, mountable rack app, counts, fingerprinter — and broader than RED (not error-gated). deprecation_toolkit/next_rails test-time. No tracker subscribes deprecation.rails (Sentry's active_support_logger list omits it). RED caveat: only deprecations fired inside requests that later raised; plus code-audit caveat: needs host `:notify` behavior.

## G8 N+1 — SHARED-WITH Sentry (server-side N+1 performance issue, >50ms, ~5 spans, cites Rails, issue-level aggregation; needs tracing), AppSignal ("find requests with the N+1 antipattern"), Scout (N+1 insight), Skylight ("heads up" repeated SQL). Bullet/Prosopite dev/staging, no UI. Faultline explicitly lacks it. RED position: flagged only on errored requests, ≤40 breadcrumbs, display-time, no tracing needed, self-hosted.

## G9 Breadcrumbs — TABLE-STAKES. Honeybadger on by default since 4.6.0 (sql, action_cable, active_job, cache, mailer + logger); Bugsnag automatic DEFAULT_RAILS_BREADCRUMBS; Sentry `breadcrumbs_logger: [:active_support_logger]` (sql, cache, mailer, active_job, action_cable, active_storage); AppSignal/Raygun manual; Telebugs/GlitchTip/Bugsink via Sentry SDK. RED's default is OFF (enable_breadcrumbs=false) — less zero-config than HB/Bugsnag. RED-only categories: deprecation, llm, llm_tool, rack-attack, active_storage(?).

## G10 YJIT/RubyVM.stat — SHARED-WITH Datadog (full YJIT gauge set + global_constant_state/method_state/constant cache), New Relic (method/constant cache invalidations, no YJIT), AppSignal (RubyVM.stat class_serial/constant cache, no YJIT) — as time-series. UNIQUE-AT-ERROR-TIME for per-error attachment. ROADMAP X "delta between captures" not documented as shipped — don't claim.

## AppSignal coverage: G1 partial(time-series) · G2 yes · G3 no · G4 not found · G5 partial · G6 no · G7 no · G8 yes · G9 partial(manual) · G10 partial(no YJIT).

## Defensible umbrella: "the only error tracker that stores runtime state (GC, memory, pool, Puma, queue, VM/YJIT) on the error record and correlates it across errors" — not per-feature uniqueness for G2/G4/G5/G8/G9.
