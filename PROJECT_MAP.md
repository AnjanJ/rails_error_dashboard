# PROJECT_MAP — rails_error_dashboard

> Map generated at commit `3d791f0` on `feat/storm-protection`. Refresh with `/shipkit:map`.
> This is a navigational index. Claims here are verified at write time but source is truth —
> always re-check the specific file before acting on a pointer.

## What this project is
`rails_error_dashboard` (RED) is a self-hosted error-tracking and exception-monitoring
Rails Engine — a free, open-source Sentry alternative that runs **inside the host app's
process**, with no external services. It captures exceptions via `Rails.error`, the Rack
middleware, and manual reporting, then serves a self-contained dashboard UI for triage,
analytics, notifications, and issue-tracker sync. Aimed at solo founders, indie hackers, and
small teams. Currently BETA (`v0.8.1`); API may change before v1.0.0.

## Stack
- **Language/framework:** Ruby >= 3.2, Rails Engine (`>= 7.0.0`, tested through Rails 8.1)
- **Architecture:** CQRS — Commands (writes), Queries (reads), Services (algorithms)
- **Datastore:** host app's DB (PostgreSQL / MySQL / SQLite); supports a **separate DB** via `connects_to`
- **Cache/queue:** host's ActiveJob backend (Sidekiq/SolidQueue/inline); Rails cache for analytics
- **Runtime deps:** `pagy ~> 43`, `groupdate ~> 6`, `concurrent-ruby ~> 1.3 (< 1.3.7)`. Optional, degrade gracefully: `browser`, `chartkick`, `httparty`, `turbo-rails`
- **No asset pipeline** — all CSS/JS inline in the layout; external libs (Bootstrap JS, Chart.js, Highlight.js) via CDN only
- **Test:** RSpec (`spec/`, ~195 spec files) + chaos integration tests. Run `bundle exec rspec` or `bin/pre-release-test all`

## Layout (where things live)
| Path | Purpose |
|------|---------|
| `lib/rails_error_dashboard/` | Core gem code, CQRS dirs, engine |
| `lib/rails_error_dashboard/engine.rb` | Engine setup — DB wiring, middleware insertion, subscriber registration |
| `lib/rails_error_dashboard/configuration.rb` | 100+ config options |
| `lib/rails_error_dashboard/error_reporter.rb` | `Rails.error` subscriber entry point |
| `lib/rails_error_dashboard/commands/` | CQRS writes (`LogError`, `ResolveError`, batch ops, baselines) |
| `lib/rails_error_dashboard/queries/` | CQRS reads (dashboard stats, analytics, health summaries) |
| `lib/rails_error_dashboard/services/` | Algorithms (detectors, classifiers, payload builders, issue clients) |
| `lib/rails_error_dashboard/services/storm_protection/` | Circuit breaker + adaptive sampling internals |
| `lib/rails_error_dashboard/integrations/` | Outbound OpenTelemetry + LLM tracing |
| `lib/rails_error_dashboard/subscribers/` | AS::Notifications subscribers (breadcrumbs, rack-attack, cable, storage, LLM, issue-tracker) |
| `lib/rails_error_dashboard/middleware/` | `ErrorCatcher`, `RateLimiter` Rack middleware |
| `lib/rails_error_dashboard/plugins/` | Built-in plugin examples (audit log, Jira, metrics) |
| `lib/generators/rails_error_dashboard/` | `install`, `uninstall`, `solid_queue` generators |
| `app/models/rails_error_dashboard/` | ActiveRecord models (see Data model) |
| `app/controllers/rails_error_dashboard/` | `errors`, `webhooks`, `application` controllers |
| `app/jobs/rails_error_dashboard/` | Async logging + notification + issue + retention jobs |
| `app/views/rails_error_dashboard/` | Dashboard ERB views + mailer views |
| `app/helpers/rails_error_dashboard/` | View helpers (backtrace, overview, user-agent) |
| `config/routes.rb` | Engine routes (mounted by host) |
| `db/migrate/` | 35 migrations |
| `spec/` | RSpec unit/integration/system specs |
| `test/pre_release/` | Chaos test scripts + Rails-app templates |
| `bin/pre-release-test` | Chaos test orchestrator |
| `docs/` | Extensive guides (QUICKSTART, FEATURES, API_REFERENCE, LLM_OBSERVABILITY, etc.) |

## Core modules / domains
- **Capture** (`error_reporter.rb`, `middleware/error_catcher.rb`, `manual_error_reporter.rb`) — three ingest paths: `Rails.error.subscribe`, Rack middleware, manual API. Owns turning a raw exception into a normalized record; delegates persistence to `Commands::LogError`. Host-app safety: never raises, never blocks, always re-raises the original.
- **Commands (writes)** (`commands/`) — `LogError`, `FindOrIncrementError` (dedup + reopen), workflow ops (resolve/mute/snooze/assign/priority/status), batch ops, baselines, cascade upserts, issue creation/linking.
- **Queries (reads)** (`queries/`) — all dashboard data: `DashboardStats`, `AnalyticsStats`, `ErrorsList`, and per-subsystem health summaries (DB, cache, jobs, N+1, ActionCable, ActiveStorage, LLM, rack-attack).
- **Services (algorithms)** (`services/`) — `ErrorNormalizer`, `ErrorHashGenerator` (fingerprinting), `BacktraceParser`, `CascadeDetector`, `SeverityClassifier`, `PlatformDetector`, `BaselineCalculator`, `SensitiveDataFilter`, payload builders (Slack/Discord/PagerDuty/webhook), issue clients (GitHub/GitLab/Codeberg/Linear), and LLM helpers (`llm_client`, `llm_summary`, `llm_cost_estimator`).
- **Storm protection** (`services/storm_protection/`) — `circuit_breaker`, `count_buffer`, `fingerprint_buckets`, `gate`. Guards against error floods via circuit breaking + adaptive sampling (the feature on this branch). Flushed by `StormFlushJob`.
- **Notifications** (`app/jobs/`, `services/*payload_builder.rb`, `notification_throttler.rb`) — Slack, Email, Discord, PagerDuty, generic webhook; throttled and dispatched async.
- **Issue tracking** (`services/*issue_client.rb`, `subscribers/issue_tracker_subscriber.rb`, `webhooks_controller.rb`) — create/link/close issues with two-way webhook sync.
- **LLM observability** (`integrations/llm_*`, `subscribers/llm_call_subscriber.rb`, `queries/llm_health_summary.rb`) — captures LLM calls, costs, health per model.
- **Plugin system** (`plugin.rb`, `plugin_registry.rb`, `plugins/`) — registration hooks; see `docs/PLUGIN_SYSTEM.md`.

## Data model
Tables are namespaced `rails_error_dashboard_*`. Base class `ErrorLogsRecord` enables the
optional separate-DB connection.

- `Application` ──< `ErrorLog` — every error belongs to an application (multi-app support; FK `optional: false`).
- `ErrorLog` ──< `ErrorOccurrence` — the deduplicated error head; occurrences are individual hits (count incremented by `FindOrIncrementError`).
- `ErrorLog` ──< `ErrorComment` — internal audit trail for workflow actions (manual comments removed in v0.6).
- `ErrorLog` ──< `CascadePattern` (as both `parent_error` and `child_error`) — directional "error A causes error B" links; exposed via `cascade_parents` / `cascade_children`.
- `ErrorBaseline` — per-error statistical baseline for anomaly/spike alerting.
- `StormEvent` — recorded error-flood events from storm protection.
- `SwallowedException` — exceptions caught-and-ignored by host code, surfaced for visibility.
- `DiagnosticDump` — on-demand captured system/environment snapshots.
- `ErrorLog belongs_to :user` (optional) — only wired if host defines `::User`.

## Primary flows
1. **Error capture (subscriber path)** — exception → `Rails.error.report` → `ErrorReporter#report`
   (`error_reporter.rb`) builds an `ErrorContext`, guards against re-entrancy, then calls
   `Commands::LogError`. Sync, or enqueues `AsyncErrorLoggingJob` when async logging is on.
   `FindOrIncrementError` dedups by fingerprint and reopens resolved errors on recurrence.
2. **HTTP middleware capture** — `Middleware::ErrorCatcher` (inserted at stack position 0)
   wraps the request, captures unhandled exceptions, and **always re-raises** so host
   behavior is unchanged.
3. **Dashboard read** — host mounts the engine; `ErrorsController` (`overview`, `index`,
   `show`, plus ~20 analytics/health collection actions) calls Query objects and renders
   self-contained ERB. Notifications and issue creation run async via jobs.

## Evolution  ← highest-value section; source can't tell you this
- **Origin:** v0.1.0 on 2025-12-24 — basic Rails error capture + dashboard + Slack/Email notifications. A `complete_schema` migration was squashed early, after which migrations are incremental (and must guard against re-running on the squash — see `0c7edf3`).
- **Major shifts:**
  - **Multi-app support (Jan 2026):** introduced `Application` and a backfilled FK on every error — turned a single-app tool into a multi-tenant one.
  - **Deep introspection (Feb–Mar 2026):** enriched context, breadcrumbs, system-health snapshots, local/instance variable capture, swallowed-exception tracking, diagnostic dumps.
  - **Issue-tracker sync (Mar 2026):** GitHub/GitLab/Codeberg clients with two-way webhook sync; Linear added Jun 2026 as a fourth provider.
  - **Design system rewrite (v0.6.0):** dropped Bootstrap CSS for a custom inline design-token system; kept Bootstrap JS via CDN only.
  - **LLM observability (May–Jun 2026):** AI Help drawer, per-model LLM health page, three capture paths, plus outbound OpenTelemetry span export.
  - **Storm protection (current branch):** circuit breaker + adaptive sampling for error floods.
- **Heading toward:** stabilizing toward v1.0.0 (currently BETA). Recent commits trend toward production hardening — performance (single-pass detectors, GROUP BY queries), security (XSS defense), and flood resilience.
- **Decisions of record:** no `docs/adr/` dir. Rationale lives in `CLAUDE.md` (architecture rules), commit bodies, and `docs/` guides (`MIGRATION_STRATEGY.md`, `MULTI_APP_PERFORMANCE.md`, `PLUGIN_SYSTEM.md`). Memory files referenced in CLAUDE.md hold deeper history (not all under repo root — `(unverified)`).

## Gotchas
- **Host-app safety is law** — the capture path must never raise, never block, must budget every op, clean up `Thread.current`, and always re-raise the original exception. See `CLAUDE.md` and the `host-app-safety` skill.
- **CQRS dirs live under `lib/`**, not `app/` — `lib/rails_error_dashboard/{commands,queries,services}/`. (CLAUDE.md's path table lists `app/...` but those dirs are empty; trust `lib/`.)
- **No asset pipeline ever** — no Sprockets/Propshaft, no `app/assets/` serving. All CSS/JS inline; external libs CDN-only. Adding an asset dependency breaks proxy-agnostic self-containment.
- **Separate DB install quirk** — the installer drops migrations in `db/migrate/`; they must be manually moved to `db/error_dashboard_migrate/`. `ErrorLogsRecord.connects_to` only fires if the `database.yml` entry exists (guarded in `engine.rb`).
- **Build-environment skip** — when `SECRET_KEY_BASE_DUMMY` is set (Docker asset precompile), the engine skips ALL runtime features to avoid retry loops (`engine.rb`).
- **Migrations are incremental over a squash** — guard new migrations against the squashed `complete_schema`. The MySQL swallowed-exceptions index needed a separate fix migration.
- **`belongs_to :user` is conditional** — only defined when the host app has `::User`; do not assume the association exists.
- **Optional deps degrade silently** — code paths must work without `browser`/`chartkick`/`httparty`/`turbo-rails`. Test both with and without.
- **Pre-commit runs chaos tests** — Lefthook stage 2 runs `bin/pre-release-test all`. Skip with `LEFTHOOK_EXCLUDE=chaos-tests`.

## External touchpoints
- **Notifications:** Slack, Email (mailer), Discord, PagerDuty, generic webhook — `app/jobs/*_notification_job.rb` + `services/*payload_builder.rb`.
- **Issue trackers:** GitHub / GitLab / Codeberg / Linear — `services/*_issue_client.rb`; inbound sync via `webhooks_controller.rb` (`POST webhooks/:provider`).
- **OpenTelemetry:** outbound span export — `integrations/o_tel.rb`, `integrations/tracer.rb`, `llm_span_processor.rb`.
- **LLM providers:** captured/summarized via `services/llm_client.rb`, `llm_cost_estimator.rb`, `subscribers/llm_call_subscriber.rb`.
- **Deploy:** distributed as a RubyGem (no app deploy). CI in `.github/workflows/` — `ci.yml`, `test.yml`, `release.yml` (release-please), `pages.yml` (docs site), `smoke-test-demo.yml`. Live demo at `rails-error-dashboard.anjan.dev`.

## Pointers to deeper docs
- `CLAUDE.md` — architecture rules, testing, gotchas, workflow orchestration.
- `docs/` — `QUICKSTART.md`, `FEATURES.md`, `API_REFERENCE.md`, `CUSTOMIZATION.md`, `PLUGIN_SYSTEM.md`, `LLM_OBSERVABILITY.md`, `MIGRATION_STRATEGY.md`, `MULTI_APP_PERFORMANCE.md`, `TROUBLESHOOTING.md`, `FAQ.md`, `GLOSSARY.md`, `SOURCE_CODE_INTEGRATION.md`, `UNINSTALL.md`.
- Project skills (CQRS patterns, host-app safety, QA, release rules, code-review standards) — see CLAUDE.md skill list.

## Unverified / open questions
- Spec count is **~195 spec files** (counted via `find`); CLAUDE.md cites ~3307 individual specs — the per-example count was not re-run here `(unverified)`.
- CLAUDE.md references memory files (codebase-history, roadmap, solidqueue-integration, etc.); their on-disk location/content was not opened `(unverified)`.
