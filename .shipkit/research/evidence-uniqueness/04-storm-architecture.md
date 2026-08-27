# J — Storm protection & architecture verification (direct WebFetch of docs/source; bugsnag/airbrake/newrelic/datadog docs unreachable → UNVERIFIED)

**Headline:** faultline-rails 1.0.0 (2026-08-21) was renamed **RailsNexus** (`rails_nexus`, github.com/tamiru/rails_nexus, 2.1.4 on 2026-08-24, MIT, 0 stars). CHANGELOG 1.1.0 (2026-08-22): "Storm protection (circuit breaker) — Per-process threshold (default: 50 errors/sec), auto-opens circuit when exceeded, sheds 90% of errors, auto-resets after cooldown." RED shipped storm protection in 0.8.2 on 2026-06-22 (two months earlier), same 50/s default. Note: dlt/faultline (Jan 2026, 87 stars) and tamiru/rails_nexus may be different lineages — the agent identified faultline-rails→rails_nexus; treat "Faultline" claims with care.

## J1 Storm protection — SHARED-WITH (RailsNexus headline; Sentry drop-ledger); mechanics unique
- RailsNexus storm_protection.rb: single global counter, NO per-fingerprint buckets; when open `rand < 0.1` random pass-through (not count-only); shed counts in-memory only, one Rails.logger.warn, no persistence/history page, no async gating, no overhead figures, off by default.
- Sentry: server-side Spike Protection ("dynamic rate limit… discarding events") protects Sentry's quota not your DB; SDK client reports count discards by reason (queue_overflow, ratelimit_backoff, sample_rate, before_send) and Stats page shows "Client Discard" = a real dropped-events ledger. "No SDK-side mechanism caps events per fingerprint per minute." Ruby `background_worker_max_queue` 30; `enable_backpressure_handling` only halves traces_sample_rate.
- Honeybadger: quota 100% → one notification/min/project; 125% shutoff; client `max_queue_size` 100 dropped; worker.rb "Dropped notices are only logged, not counted."; per-error throttling = DIY Redis before_notify example.
- Bugsnag: MAX_OUTSTANDING_REQUESTS 100 → "Dropping notification" logged. Airbrake queue_size 100. Rollbar: no client rate limiting attributes. New Relic: MAX_ERROR_QUEUE_LENGTH 20 traces / 100 events per harvest, silent. AppSignal/Datadog UNVERIFIED.
- exception_notification: `error_grouping` log2 notification throttling only. solid_errors: none — every occurrence a DB write. exception_hunter: none. Errbit/GlitchTip/Bugsink/Telebugs: separate apps, none documented.
- Unique remainder (defensible): per-fingerprint caps with context-shedding → deterministic sampling (fresh exemplar/minute); count-only mode with exact counts reconciled every 30s ("Counting is exact — no extrapolation", count_buffer.rb:15); async-enqueue gating; single storm notification + auto-issue cap; persisted Storm History page; ON by default. Avoid "the only Rails gem with storm protection".

## J2 In-process engine + dashboard, zero egress — SHARED-WITH solid_errors, exception_hunter, RailsNexus
- exception_notification no dashboard; Errbit separate app (MongoDB ≥7); GlitchTip/Bugsink/Telebugs separate Django/Docker apps; AppSignal daemon. "Zero egress" only with notifications/AI Help/CDN JS off.

## J3 Storage — SHARED-WITH solid_errors
- solid_errors: SQLite/MySQL/PostgreSQL/Trilogy; `connects_to` separate DB incl. primary/replica. RailsNexus: SQLite/PG/MySQL, separate DB not mentioned. exception_hunter PG only. Errbit Mongo. RED's BRIN/functional/partial/GIN indexes unmatched but implementation detail. RED has no special trilogy handling (rides Rails adapter).

## J4 Safety contract + published µs overhead — UNIQUE (qualified)
- No fetched competitor publishes per-error overhead in µs or a written never-raise/never-block/budget contract (Honeybadger, Sentry, AppSignal "lightweight… Rust… no benchmarks", Skylight, Scout, RailsNexus, solid_errors, exception_hunter). NR/Datadog UNVERIFIED. **Code audit: RED's 2.4µs figure has no reproducible benchmark script** — quote only with conditions, or add a benchmark first.

## J5 No asset pipeline — SHARED-WITH solid_errors (which is stricter: inline Tailwind ~25KB, nonce'd inline script, zero CDN)
- RailsNexus needs an asset entry point (app/assets, app/javascript; Importmap/jsbundling). exception_hunter has app/assets. RED loads Bootstrap/Chart.js/Highlight.js from CDN → needs CDN allowlisted under strict CSP. Don't claim CSP advantage over solid_errors.

## J6 Multi-app shared DB — SHARED-WITH Errbit, GlitchTip, Bugsink, Telebugs, all SaaS (projects)
- Unique only among in-process Rails engines (solid_errors, exception_hunter, RailsNexus have no multi-app). App-name auto-detection not claimed by any peer.

## J7 Plugins — TABLE-STAKES (Honeybadger Plugin.register + before_notify; Sentry before_send/integrations; Bugsnag on_error/middleware; exception_notification custom notifiers; Errbit gem plugins; RailsNexus after_create lambdas; solid_errors none). RED's 8 lifecycle events richer than in-app peers.

## J8 Async via app's job backend + sync fallback — SHARED-WITH Rollbar (use_active_job/sidekiq/… + failover_handlers), exception_hunter (async_logging, sync in jobs). Sentry removed config.async in 6.0 (own thread pool); HB/Bugsnag/Airbrake own worker threads; solid_errors/RailsNexus sync only. RED fallback real (log_error.rb:143-153). Differentiator = enqueue-is-a-DB-write gating in storm mode.

## J9 Unlimited/MIT — TABLE-STAKES among self-hosted OSS. Free tiers verified: Sentry 5k errors/1 user/30-day; Honeybadger 5,000/1 user/15-day; AppSignal 50K requests/5-day (next tier $279/mo yearly); Rollbar 5K occ + 1K sessions/30-day; Raygun no free plan ($40/mo per 100k, 180-day); GlitchTip hosted 1,000 events free, self-host MIT unlimited; Bugsink self-host unlimited, hosted €16–158; Telebugs $299 one-time unlimited (proprietary). Bugsnag/Airbrake UNVERIFIED. solid_errors/Errbit/exception_hunter/RailsNexus MIT no caps.

## J10 Filtering incl. local vars — SHARED-WITH Honeybadger (locals through request_sanitizer/params_filters), Rollbar (Scrubbers::Params on locals). Sentry: no automatic scrubbing of locals ("use before_send"). Bugsnag redacted_keys incl. breadcrumbs. RailsNexus params/headers only. solid_errors/exception_hunter not documented. LLM-path filtering: RED builds LLM payload from already-filtered fields and drops [FILTERED] vars (markdown_error_formatter.rb:135-160) — not verified vs Sentry Seer/HB AI privacy; don't claim unique.

## Summary
J1 SHARED (mechanics unique) · J2 SHARED · J3 SHARED · J4 UNIQUE(qualified; benchmark unreproducible) · J5 SHARED (solid_errors stricter) · J6 SHARED (unique among in-process engines) · J7 TABLE-STAKES · J8 SHARED · J9 TABLE-STAKES · J10 SHARED
