# PROJECT_MAP — rails_error_dashboard

> Map generated at commit `b2357ef` on `main`. Refresh with `/shipkit:map`.
> This is a navigational index. Claims here are verified at write time but source is truth —
> always re-check the specific file before acting on a pointer.

## What this project is
`rails_error_dashboard` (RED) is a self-hosted error-tracking and exception-monitoring
Rails Engine — a free, open-source Sentry alternative that runs **inside the host app's
process**, with no external services. It captures exceptions via `Rails.error`, the Rack
middleware, and manual/client reporting, then serves a self-contained dashboard UI for triage,
analytics, notifications, and issue-tracker sync. Aimed at solo founders, indie hackers, and
small teams. Currently BETA (`v0.16.1`, `lib/rails_error_dashboard/version.rb`); API may change before v1.0.0.

## Stack
- **Language/framework:** Ruby >= 3.2 (`.ruby-version` 3.4.5), Rails Engine (`>= 7.0.0`; CI covers Rails 7.0-8.1)
- **Architecture:** CQRS — Commands (writes), Queries (reads), Services (algorithms)
- **Datastore:** host app's DB (PostgreSQL / MySQL / SQLite); optional **separate DB** via `connects_to`
- **Queue/cache:** host's ActiveJob backend (Sidekiq / Solid Queue / inline); Rails cache for analytics
- **Runtime deps (gemspec):** `rails >= 7.0.0`, `pagy ~> 43.0`, `groupdate ~> 6.0`, `concurrent-ruby ~> 1.3` (no upper ceiling). Optional, degrade gracefully: `browser`, `chartkick`, `httparty`, `turbo-rails`, `rack-attack`, `solid_queue`
- **No asset pipeline** — all CSS/JS inline in the layout; external libs (Bootstrap JS, Chart.js, Highlight.js) via CDN only
- **i18n:** 11 locales in `config/locales/` (en, de, es, fr, it, ja, pl, pt-BR, ru, uk, zh-CN); check with `bin/i18n-check`
- **Test:** RSpec, 5,966 examples in 381 spec files (CLAUDE.md's "~5,300" is stale) + chaos integration tests. `bundle exec rspec` or `bin/pre-release-test all`

## Layout (where things live)
| Path | Purpose |
|------|---------|
| `lib/rails_error_dashboard/` | Core gem code, CQRS dirs, engine |
| `lib/rails_error_dashboard/engine.rb` | Engine setup — DB wiring, middleware insertion, subscriber registration |
| `lib/rails_error_dashboard/configuration.rb` | 100+ config options, boot-time validation/warnings |
| `lib/rails_error_dashboard/error_reporter.rb` | `Rails.error` subscriber entry point |
| `lib/rails_error_dashboard/manual_error_reporter.rb` | Manual / client-sent reports |
| `lib/rails_error_dashboard/commands/` | CQRS writes (`LogError`, workflow ops, batch ops, flushers, baselines) |
| `lib/rails_error_dashboard/queries/` | CQRS reads (dashboard stats, analytics, per-subsystem health) |
| `lib/rails_error_dashboard/services/` | Algorithms (detectors, classifiers, payload builders, issue clients, webhook signing) |
| `lib/rails_error_dashboard/services/storm_protection/` | Circuit breaker + adaptive sampling internals |
| `lib/rails_error_dashboard/value_objects/` | `ErrorContext`, `OccurrenceSnapshot`, `LlmCallEvent` |
| `lib/rails_error_dashboard/integrations/` | Outbound OpenTelemetry + LLM tracing |
| `lib/rails_error_dashboard/subscribers/` | AS::Notifications subscribers (breadcrumbs, rack-attack, cable, storage, LLM, issue-tracker) |
| `lib/rails_error_dashboard/middleware/` | `ErrorCatcher`, `RateLimiter` Rack middleware |
| `lib/rails_error_dashboard/plugins/` | Built-in plugin examples (audit log, Jira, metrics) |
| `lib/generators/rails_error_dashboard/` | `install`, `uninstall`, `solid_queue` generators |
| `app/models/rails_error_dashboard/` | 16 ActiveRecord models (see Data model) |
| `app/controllers/rails_error_dashboard/` | `application`, `errors`, `health`, `locales`, `webhooks` |
| `app/jobs/rails_error_dashboard/` | Async logging, per-channel notification, issue, baseline, storm, flush, retention, digest jobs |
| `app/mailers/rails_error_dashboard/` | Error notification + digest mailers |
| `app/views/rails_error_dashboard/` | Dashboard ERB views + mailer views |
| `app/helpers/rails_error_dashboard/` | `application`, `backtrace`, `i18n`, `mailer_i18n`, `overview`, `user_agent` helpers |
| `config/routes.rb` | Engine routes (mounted by host) |
| `db/migrate/` | 52 migrations; canonical schema snapshot in `spec/dummy/db/schema.rb` |
| `spec/` | RSpec. **Two parallel layouts:** `spec/{commands,queries,services}/` and `spec/lib/rails_error_dashboard/{commands,queries,services}/` |
| `test/pre_release/` | Chaos test scripts + Rails-app templates |
| `bin/` | `pre-release-test` (chaos orchestrator), `i18n-check`, `check-schema-parity`, `smoke-test`, `setup` |
| `docs/` | Canonical guides (`docs/guides/`, `docs/features/`, QUICKSTART, API_REFERENCE, UPGRADING, ...) |
| `_guides/ _features/ _reference/ _getting_started/` | Jekyll docs-site copies of `docs/` (see Gotchas) |
| `.github/workflows/` | `ci.yml`, `test.yml`, `release.yml`, `pages.yml`, `smoke-test-demo.yml` |

## Core modules / domains
- **Capture** (`error_reporter.rb`, `middleware/error_catcher.rb`, `manual_error_reporter.rb`) — three ingest paths: `Rails.error` subscriber, Rack middleware, manual API. Turns a raw exception into a normalized record; persistence goes via `Commands::LogError`. Safety: never raises, never blocks, always re-raises the original. `ManualErrorReporter` tags client reports with capture source `client` (0.16.0) so source viewer/blame/LLM snippets are skipped for client backtraces.
- **Commands (writes)** (`commands/`) — `LogError`, `FindOrIncrementError` (dedup + reopen), workflow ops (resolve/mute/snooze/assign/priority/status), batch ops, baselines, cascade upserts, issue create/link, `RecordOccurrenceContext`, buffered flushers (`FlushStormCounts`, `FlushRackAttackEvents`, `FlushSwallowedExceptions`, `FlushMissingTranslations`).
- **Queries (reads)** (`queries/`) — `DashboardStats`, `AnalyticsStats`, `ErrorsList`, `HealthStatus` (feeds `/health`), `PlatformComparison`, `StormHistory`, `UserImpactSummary`, `ReleaseTimeline`, and per-subsystem summaries (DB, cache, jobs, N+1, ActionCable, ActiveStorage, LLM, rack-attack, swallowed exceptions, missing translations).
- **Services (algorithms)** (`services/`) — `ErrorNormalizer`, `ErrorHashGenerator` (fingerprinting), `BacktraceParser`, `CascadeDetector`, `SeverityClassifier`, `PlatformDetector`, `BaselineCalculator`, `SensitiveDataFilter`, `SourceCodeReader`, `CrashCapture` (boot errors), payload builders, issue clients, LLM helpers.
- **Storm protection** (`services/storm_protection/`: `circuit_breaker`, `count_buffer`, `fingerprint_buckets`, `gate`) — circuit breaking + adaptive sampling for error floods (shipped 0.8.2). Flushed by `StormFlushJob`; recorded in `storm_events` / `storm_flush_batches`.
- **Notifications** (`app/jobs/*_notification_job.rb`, `services/*payload_builder.rb`, `notification_throttler.rb`) — Slack, Email, Discord, PagerDuty, Telegram (0.15.0), signed outbound webhooks (`webhook_delivery.rb`, `webhook_signer.rb`); throttled, dispatched async, plus digests.
- **Issue tracking** (`services/*_issue_client.rb`, `subscribers/issue_tracker_subscriber.rb`, `webhooks_controller.rb`) — GitHub/GitLab/Codeberg/Linear create/link/close with two-way webhook sync.
- **LLM observability** (`integrations/llm_*`, `subscribers/llm_call_subscriber.rb`, `queries/llm_health_summary.rb`) — LLM call capture, costs, per-model health, AI Help drawer (`errors#ai_help`).
- **Plugin system** (`plugin.rb`, `plugin_registry.rb`, `plugins/`) — registration hooks; see `docs/PLUGIN_SYSTEM.md`.

## Data model
15 tables namespaced `rails_error_dashboard_*` (`spec/dummy/db/schema.rb`). Base class `ErrorLogsRecord` enables the optional separate-DB connection.

- `Application` ──< `ErrorLog` — multi-app: every error belongs to an application (`optional: false`).
- `ErrorLog` ──< `ErrorOccurrence` ──< `ErrorOccurrenceContext` — the deduplicated head, each hit, and per-hit context history (0.16.0; context rows also FK to `ErrorLog`).
- `ErrorLog` ──< `ErrorComment` (workflow audit trail) and ──< `EventCount` (per-bucket event counts, 15-min storm buckets since 0.14.0).
- `ErrorLog` ──< `CascadePattern` (as `parent_error` and `child_error`) — exposed via `cascade_parents` / `cascade_children`.
- `ErrorBaseline` (anomaly baselines), `EventTimingGap`, `StormEvent`, `StormFlushBatch` (flood accounting).
- Application-scoped side tables: `SwallowedException`, `DiagnosticDump`, `RackAttackEvent`, `MissingTranslation` (0.15.0).
- `ErrorLog` / `ErrorOccurrence` `belongs_to :user` (optional) — only wired if host defines `::User`; UUID user IDs supported since 0.15.0.

## Primary flows
1. **Subscriber capture** — `Rails.error.report` → `ErrorReporter#report` (`error_reporter.rb`) builds an `ErrorContext`, guards re-entrancy, calls `Commands::LogError` (sync, or `AsyncErrorLoggingJob`). `FindOrIncrementError` dedups by fingerprint, reopens resolved errors, refreshes the snapshot on recurrence, and `RecordOccurrenceContext` stores per-hit context.
2. **HTTP middleware capture** — `Middleware::ErrorCatcher` (inserted at stack position 0 via `insert_before 0` in `engine.rb`) reports unhandled exceptions and **always re-raises**. On Rails 7.0 it omits the `source:` keyword (7.0's `report` lacks it).
3. **Dashboard read** — host mounts the engine; `ErrorsController` (`overview`, `index`, `show`, ~20 analytics/health collection actions) calls Query objects and renders self-contained ERB. `HealthController#show` serves JSON `/health` (200, or 503 if the error DB is unreachable). `LocalesController#create` sets the per-session language (POST only).

## Evolution  ← highest-value section; source can't tell you this
Git history in this checkout is shallow (50 commits, from 2026-09-20); earlier history below comes from `CHANGELOG.md`.
- **Origin:** v0.1.0 (CHANGELOG dates it 2024-12-24, likely a typo for 2025-12-24) — basic capture, dashboard, Slack/Email. A squashed `complete_schema` migration came first; later migrations are incremental.
- **0.2-0.8 (Dec 2025 - Jun 2026):** multi-app support, deep introspection (breadcrumbs, local variables, swallowed exceptions, diagnostic dumps), issue-tracker sync (GitHub/GitLab/Codeberg, then Linear), 0.6.0 design-token rewrite (Bootstrap CSS dropped), LLM observability, 0.8.0 outbound OpenTelemetry, **0.8.2 storm protection** (2026-06-22).
- **0.9-0.11 (Aug 2026):** 0.9.0 i18n (11 locales); 0.9.1 refuse default credentials outside dev/test (GHSA-qhgm-3pxf-mvc6); 0.10.0 Rack::Attack track fixes; 0.11.0 environment awareness; 0.11.1 snapshot refresh on recurrence.
- **0.12-0.14 (Sep 2026), correctness and hardening:** 0.12.0 nine review findings + fingerprint regrouping; 0.13.0 deep-QA hardening (GHSA-xmv7-mg68-3v2f); 0.14.0 evidence integrity (events counted in the reporting window, 15-min storm buckets); 0.14.2 credential guard bypass fix; 0.14.3 setup hardening, Solid Queue hands-off (decision 0001).
- **0.15-0.16 (Oct 2026):** 0.15.0 health endpoint, signed webhooks, missing-translation tracking, Telegram, boot-crash capture, Ruby 4.0 in CI, source viewer limited to source files (GHSA-q7r3-w7p3-95h5); 0.16.0 occurrence context history (ROADMAP C3) + capture source; 0.16.1 platform health score rework + boot warning on Rails < 7.0.10.
- **Heading toward:** v1.0.0 stabilization. Recent work is audit-driven fixes and evidence accuracy rather than new surface area. `.shipkit/specs/` holds in-flight specs; released ones move to `.shipkit/specs/_shipped/` (e.g. `occurrence-context-history`, `audit-fixes-0-16-1`, `capture-source`).
- **Decisions of record:** `.shipkit/decisions/0001-red-never-writes-other-gems-files.md`; no `docs/adr/`. Other rationale: `CLAUDE.md`, commit bodies, `CHANGELOG.md` highlights, `docs/MIGRATION_STRATEGY.md`.

## Gotchas
- **Host-app safety is law** — capture path must never raise, never block, budget every op, clean up `Thread.current`, always re-raise the original. See `CLAUDE.md` and `.claude/skills/host-app-safety/`.
- **CQRS dirs live under `lib/`**, not `app/` — `lib/rails_error_dashboard/{commands,queries,services}/`.
- **No asset pipeline** — no Sprockets/Propshaft/`app/assets` serving; inline CSS/JS, CDN-only libs.
- **Docs twins drift** — `_guides/ _features/ _reference/ _getting_started/` are hand-copied twins of `docs/`; `_config.yml` excludes `docs/` from the Jekyll build and there is no sync script. Edit both or the site goes stale.
- **Two spec trees** — look in both `spec/commands/` and `spec/lib/rails_error_dashboard/commands/` (same for queries, services) before concluding a spec is missing.
- **Separate DB** — the installer copies migrations to `db/error_dashboard_migrate/` itself (since #83) and skips ones the app already has (since #93); an app moving off the main DB must move its own. See `docs/guides/DATABASE_OPTIONS.md`. `connects_to` only fires if the `database.yml` entry exists (guarded in `engine.rb`).
- **Build-environment skip** — with `SECRET_KEY_BASE_DUMMY` set (Docker precompile) the engine skips all runtime features (`engine.rb`).
- **Rails < 7.0.10** — unhandled request errors are not recorded; `configuration.rb` warns at boot.
- **`belongs_to :user` is conditional** — only when the host defines `::User`.
- **Optional deps degrade silently** — test with and without `browser`/`chartkick`/`httparty`/`turbo-rails`/`rack-attack`.
- **Pre-commit runs chaos tests** — Lefthook stage 2 runs `bin/pre-release-test all`; skip with `LEFTHOOK_EXCLUDE=chaos-tests`.
- **Memory files and `tasks/`** — CLAUDE.md cites memory files that live on the maintainer's machine, not in the repo; `tasks/` is gitignored.
- **`ROADMAP.md` is stale** — header says v0.14.0; do not use it for current status.

## External touchpoints
- **Notifications:** Slack, Email, Discord, PagerDuty, Telegram, generic signed webhook — `app/jobs/*_notification_job.rb` + `services/*payload_builder.rb`.
- **Issue trackers:** GitHub / GitLab / Codeberg / Linear — `services/*_issue_client.rb`; inbound sync via `POST webhooks/:provider` (`webhooks_controller.rb`).
- **OpenTelemetry:** outbound span export — `integrations/o_tel.rb`, `integrations/tracer.rb`, `integrations/llm_span_processor.rb`.
- **LLM providers:** `services/llm_client.rb`, `services/llm_cost_estimator.rb`, `subscribers/llm_call_subscriber.rb`.
- **Health probe:** `GET health` (`health_controller.rb`) for uptime monitors.
- **Deploy/CI:** distributed as a RubyGem. `.github/workflows/test.yml` runs Ruby 3.2/3.3/3.4/4.0 x Rails 7.0/7.1/7.2/8.0/8.1 plus PostgreSQL and MySQL rows; `ci.yml` has lint, integration, upgrade; `release.yml` is release-please; `pages.yml` builds the docs site; `smoke-test-demo.yml` checks the live demo.

## Pointers to deeper docs
- `CLAUDE.md` — architecture rules, testing, gotchas. `CHANGELOG.md` — release highlights and upgrade notes.
- `docs/` — `QUICKSTART.md`, `FEATURES.md`, `API_REFERENCE.md`, `UPGRADING.md`, `PRODUCTION.md`, `PLUGIN_SYSTEM.md`, `LLM_OBSERVABILITY.md`, `TROUBLESHOOTING.md`, `docs/guides/` (`CONFIGURATION.md`, `DATABASE_OPTIONS.md`, `NOTIFICATIONS.md`, `SOLID_QUEUE_SETUP.md`, `TRANSLATIONS.md`), `docs/development/TESTING.md`.
- Specs & decisions: `.shipkit/specs/<feature>/` (in flight), `.shipkit/specs/_shipped/<feature>/` (released), `.shipkit/decisions/` (why).
- Project skills: `.claude/skills/` (cqrs-patterns, host-app-safety, release-rules, chaos, ...).

## Unverified / open questions
- RSpec example count (5,966) was supplied by the caller, not re-run here `(unverified)`; the 381 spec-file count was re-counted via `find`.
- Release dates and contents for 0.9-0.14 come from `CHANGELOG.md` headings and highlights, not from git (shallow clone).
- Memory files referenced by CLAUDE.md are not in the repo; their content was not opened `(unverified)`.
