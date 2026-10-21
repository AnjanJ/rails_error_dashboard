# PROJECT_MAP — rails_error_dashboard

> Map generated at commit `b2357ef` on `main` (v0.16.1). Refresh with `/shipkit:map`.
> This is a navigational index. Claims here are verified at write time but source is truth —
> always re-check the specific file before acting on a pointer.

## What this project is
`rails_error_dashboard` (RED) is a self-hosted error-tracking and exception-monitoring
Rails Engine — a free, open-source Sentry alternative that runs **inside the host app's
process**, with no external services. It captures exceptions via `Rails.error`, the Rack
middleware, boot-crash capture, and manual reporting, then serves a self-contained dashboard UI
for triage, analytics, notifications, and issue-tracker sync. Aimed at solo founders, indie
hackers, and small teams. Currently BETA (`VERSION = "0.16.1"` in `lib/rails_error_dashboard/version.rb`);
API may change before v1.0.0.

## Stack
- **Language/framework:** Ruby >= 3.2 (CI covers 3.2–4.0), Rails Engine (`rails >= 7.0.0`, tested through 8.1)
- **Architecture:** CQRS — Commands (writes), Queries (reads), Services (algorithms)
- **Datastore:** host app's DB (PostgreSQL / MySQL / SQLite); supports a **separate DB** via `connects_to` (`ErrorLogsRecord`)
- **Cache/queue:** host's ActiveJob backend (Sidekiq / Solid Queue / inline); Rails cache for analytics
- **Runtime deps (gemspec):** `rails >= 7.0`, `pagy ~> 43.0`, `groupdate ~> 6.0`, `concurrent-ruby ~> 1.3` (storm-protection primitives). Optional, degrade gracefully: `browser`, `chartkick`, `httparty`, `turbo-rails`
- **No asset pipeline** — all CSS/JS inline in the layout; external libs (Bootstrap JS, Chart.js, Highlight.js) via CDN only
- **Test:** RSpec (381 `*_spec.rb` files under `spec/`, 5,966 examples at 0.16.1) + chaos integration tests. Run `bundle exec rspec` or `bin/pre-release-test all`; `bin/with-ruby` runs a command under the Ruby in `.ruby-version` (the git hooks use it). CI's matrix is Ruby 3.2–4.0 × Rails 7.0–8.1 (`.github/workflows/test.yml`). Specs need the gitignored `spec/dummy/db/test.sqlite3` to exist.

## Frontend interaction model
- **Model:** server-rendered ERB, engine-served; progressive enhancement with inline JS. No SPA, no Stimulus/importmap.
- **Where UI state lives:** server-side (DB + Rails cache); per-user dashboard language in the session (`locales_controller.rb`).
- **How updates reach the browser:** full page loads, plus live updates via Turbo Streams over ActionCable when the host has `turbo-rails` + ActionCable (`services/error_broadcaster.rb`; it renders `_stats.html.erb` by full string path — grep the path fragment, not the filename). See `docs/guides/REAL_TIME_UPDATES.md`.
- **Entry points:** `app/controllers/rails_error_dashboard/errors_controller.rb`, `app/views/rails_error_dashboard/`, `app/helpers/rails_error_dashboard/`. Dashboard auth is `authenticate_dashboard_user!` in `application_controller.rb`.
- **i18n:** eleven locales in `config/locales/` (de en es fr it ja pl pt-BR ru uk zh-CN) served through a private backend (`i18n_store.rb`, `private_backend.rb`, `translation.rb`; view helper `red_t`). Guide: `docs/guides/TRANSLATIONS.md`.

## Layout (where things live)
| Path | Purpose |
|------|---------|
| `lib/rails_error_dashboard.rb` | Gem entry, requires |
| `lib/rails_error_dashboard/engine.rb` | Engine setup — DB wiring, middleware insertion, crash-capture and subscriber initializers |
| `lib/rails_error_dashboard/configuration.rb` | 100+ config options, validation, boot warnings (e.g. Rails < 7.0.10) |
| `lib/rails_error_dashboard/error_reporter.rb` | `Rails.error` subscriber entry point |
| `lib/rails_error_dashboard/manual_error_reporter.rb` | Manual-report API |
| `lib/rails_error_dashboard/commands/` | CQRS writes (`log_error`, `find_or_increment_error`, workflow/batch ops, flush_* commands, backfills, `record_occurrence_context`) |
| `lib/rails_error_dashboard/queries/` | CQRS reads (dashboard/analytics stats, `errors_list`, per-subsystem health summaries, `health_status`, `storm_history`, `uninstall_plan`) |
| `lib/rails_error_dashboard/services/` | Algorithms (normalizer, hashing, detectors, classifiers, payload builders, issue clients, webhook signing/delivery) |
| `lib/rails_error_dashboard/services/storm_protection/` | Circuit breaker, count buffer, fingerprint buckets, gate |
| `lib/rails_error_dashboard/value_objects/` | `error_context`, `llm_call_event`, `occurrence_snapshot` |
| `lib/rails_error_dashboard/integrations/` | Outbound OpenTelemetry + LLM tracing |
| `lib/rails_error_dashboard/subscribers/` | AS::Notifications subscribers (breadcrumbs, rack-attack, ActionCable, ActiveStorage, LLM, issue-tracker) |
| `lib/rails_error_dashboard/middleware/` | `error_catcher.rb`, `rate_limiter.rb` Rack middleware |
| `lib/rails_error_dashboard/plugins/` | Built-in plugin examples (audit log, Jira, metrics) |
| `lib/generators/rails_error_dashboard/` | `install`, `uninstall`, `solid_queue` generators |
| `lib/tasks/` | Rake tasks |
| `app/models/rails_error_dashboard/` | ActiveRecord models (see Data model) |
| `app/controllers/rails_error_dashboard/` | `errors`, `health`, `locales`, `webhooks`, `application` controllers |
| `app/jobs/rails_error_dashboard/` | Async logging, notification (Slack/Discord/PagerDuty/Telegram/webhook/email), issue, baseline, retention, flush, digest jobs |
| `app/mailers/rails_error_dashboard/` | Error notification + digest mailers |
| `app/views/rails_error_dashboard/` | Dashboard ERB views + mailer views |
| `config/routes.rb`, `config/locales/` | Engine routes (mounted by host); 11 locale files |
| `db/migrate/` | 52 migrations (latest 20261015000002, capture_source) |
| `spec/` | RSpec unit/integration/system specs (`spec/dummy/` host app) |
| `test/pre_release/` | Chaos test scripts + Rails-app templates; orchestrated by `bin/pre-release-test` |
| `bin/` | Dev scripts: `pre-release-test`, `check-schema-parity`, `i18n-check`, `i18n-merge`, `with-ruby`, `smoke-test`, `full-integration-test` |
| `docs/` | Guides (QUICKSTART, FEATURES, API_REFERENCE, PRODUCTION, UPGRADING, UNINSTALL, PLUGIN_SYSTEM, LLM_OBSERVABILITY, ...) and `docs/guides/` |
| `_guides/`, `_reference/` | Hand-maintained Jekyll copies of `docs/guides/` and top-level docs (lowercase, hyphenated filenames; they drift) |
| `.shipkit/` | `decisions/`, `specs/`, `research/` |
| `tasks/` | Gitignored (`.gitignore`): local handoffs, audit notes, release-note drafts. Not in the repo |

## Core modules / domains
- **Capture** (`error_reporter.rb`, `middleware/error_catcher.rb`, `manual_error_reporter.rb`, `services/crash_capture.rb`) — ingest paths: `Rails.error.subscribe`, Rack middleware, manual API, boot-crash capture. Owns turning a raw exception into a normalized record; persistence is delegated to `Commands::LogError`. Records a `capture_source` (migration 20261015000002). Host-app safety: never raises, never blocks, always re-raises the original.
- **Commands (writes)** (`commands/`) — `LogError`, `FindOrIncrementError` (dedup + reopen), workflow ops (resolve/mute/snooze/assign/priority/status), batch ops, baselines, cascade upserts, issue create/link, `RecordOccurrenceContext`, `Flush*` commands for buffered counters, `DropAllTables` (uninstall).
- **Queries (reads)** (`queries/`) — `DashboardStats`, `AnalyticsStats`, `ErrorsList`, `PlatformComparison`, `HealthStatus` (feeds `health_controller.rb`), plus health summaries for DB, cache, jobs, N+1, ActionCable, ActiveStorage, LLM, rack-attack, swallowed exceptions, missing translations, boot errors.
- **Services (algorithms)** (`services/`) — `ErrorNormalizer`, `ErrorHashGenerator` (fingerprinting; `custom_fingerprint` documented in FEATURES), `BacktraceParser`, `CascadeDetector`, `SeverityClassifier`, `PlatformDetector`, `BaselineCalculator`, `SensitiveDataFilter`, `UrlSafety`, `SourceCodeReader`, payload builders (Slack/Discord/PagerDuty/Telegram/webhook), `WebhookSigner`/`WebhookDelivery` (signed outbound webhooks), issue clients (GitHub/GitLab/Codeberg/Linear), LLM helpers.
- **Storm protection** (`services/storm_protection/`) — `circuit_breaker`, `count_buffer`, `fingerprint_buckets`, `gate`. Flood guard via circuit breaking + adaptive sampling; flushed by `StormFlushJob` / `commands/flush_storm_counts.rb`.
- **Notifications** (`app/jobs/*_notification_job.rb`, `services/*payload_builder.rb`, `notification_throttler.rb`, `notification_burst_summary_job.rb`, `scheduled_digest_job.rb`) — Slack, Email, Discord, PagerDuty, Telegram, generic webhook; throttled, dispatched async.
- **Issue tracking** (`services/*issue_client.rb`, `subscribers/issue_tracker_subscriber.rb`, `webhooks_controller.rb`) — create/link/close issues with two-way webhook sync.
- **LLM observability** (`integrations/llm_*`, `subscribers/llm_call_subscriber.rb`, `queries/llm_health_summary.rb`).
- **Plugin system** (`plugin.rb`, `plugin_registry.rb`, `plugins/`) — see `docs/PLUGIN_SYSTEM.md`.
- **Install/uninstall** (`lib/generators/rails_error_dashboard/`, `queries/uninstall_plan.rb`) — see Gotchas for database mode behaviour.

## Data model
Tables are namespaced `rails_error_dashboard_*`. Base class `ErrorLogsRecord` enables the optional separate-DB connection.

- `Application` ──< `ErrorLog` — every error belongs to an application (multi-app; `optional: false`).
- `ErrorLog` ──< `ErrorOccurrence` — deduplicated head; occurrences are individual hits.
- `ErrorLog` ──< `ErrorOccurrenceContext` (also belongs to an occurrence) — per-occurrence context history (0.16.0).
- `ErrorLog` ──< `ErrorComment` — audit trail for workflow actions.
- `ErrorLog` ──< `CascadePattern` (as `parent_error` and `child_error`) — exposed via `cascade_parents` / `cascade_children`.
- `ErrorLog` ──< `EventCount` (optional FK) and `EventTimingGap` — event-volume / timing bookkeeping.
- `ErrorBaseline` — per-error statistical baseline for anomaly alerts.
- `StormEvent`, `StormFlushBatch` — flood events and buffered-flush bookkeeping.
- `SwallowedException`, `RackAttackEvent`, `MissingTranslation` — optional `application`; surfaced on their own health pages.
- `DiagnosticDump` — on-demand environment snapshots (belongs to `Application`).
- `user` association on `ErrorLog`/`ErrorOccurrence` is `optional: true` and defined only when the host has `::User` (UUID user IDs supported since 0.15.0).

## Primary flows
1. **Error capture (subscriber path)** — `Rails.error.report` → `ErrorReporter#report` (`error_reporter.rb`) builds an `ErrorContext`, guards against re-entrancy, then calls `Commands::LogError`. Sync, or enqueues `AsyncErrorLoggingJob` when async logging is on. `FindOrIncrementError` dedups by fingerprint and reopens resolved errors on recurrence; storm-protection gate sits in front under flood.
2. **HTTP middleware capture** — `Middleware::ErrorCatcher` (`insert_before 0` in `engine.rb`, there since v0.1.0) wraps the request, reports exceptions that propagate out of the stack, and **always re-raises**. An exception Rails renders as an error page never reaches it: on Rails 7.1+ and 7.0.10+ ActionDispatch reports those itself (ShowExceptions flags them, the Executor reports), skipping rescue responses such as 404s. Rails 7.0.0–7.0.8.7 never report them, so nothing records them; `configuration.rb` warns at boot (0.16.1).
3. **Dashboard read** — host mounts the engine; `ErrorsController` (`overview`, `index`, `show`, plus ~20 analytics/health collection actions in `config/routes.rb`) calls Query objects and renders ERB. `GET health` (`health_controller.rb`) returns JSON, 503 when the error DB is unreachable.
4. **Notification / issue sync** — new/recurring error → notification jobs (throttled) and `CreateIssueJob`; inbound `POST webhooks/:provider` closes/reopens.

## Evolution  ← highest-value section; source can't tell you this
- **Origin:** v0.1.0 on 2025-12-24 — basic capture + dashboard + Slack/Email. A `complete_schema` migration was squashed early; later migrations are incremental and must guard against re-running on the squash (see `0c7edf3`).
- **Major shifts:**
  - Multi-app support (Jan 2026): `Application` and a backfilled FK on every error.
  - Deep introspection (Feb–Mar 2026): breadcrumbs, system-health snapshots, variable capture, swallowed exceptions, diagnostic dumps. Issue-tracker sync (GitHub/GitLab/Codeberg; Linear Jun 2026).
  - Design system rewrite (v0.6.0): Bootstrap CSS dropped for an inline token system.
  - LLM observability + OpenTelemetry (May–Jun 2026), then storm protection (circuit breaker, adaptive sampling).
  - **Eleven-locale i18n (0.9.0, Aug 2026)** with a private I18n backend so host config cannot alter RED's dictionary.
  - **Hardening/audit era (0.9 through 0.16.1, Aug–Oct 2026):** security advisories and the credential guard (0.14.2, `b00c8e5`), setup/uninstall hardening (0.14.3–0.14.4), a migration-replay data-loss fix (`2075c6b`), Solid Queue hands-off decision (0.14.3), then 0.15.0 (health endpoint, signed webhooks, Telegram, boot-crash capture, UUID users) and 0.16.0 (occurrence context history, capture source, Rails 7.0 middleware fix).
  - 0.16.1 (2026-10): boot warning for Rails < 7.0.10 (`c44dc00`) and platform health score rework (`59554ab`).
- **Heading toward:** stabilising toward v1.0.0 via audit-driven correctness fixes, docs accuracy and spec coverage rather than new surfaces (inference from the last ~40 commits). `ROADMAP.md` holds the planned items; statuses there can lag, verify upstream.
- **Decisions of record:** `.shipkit/decisions/0001-red-never-writes-other-gems-files.md`; amendments recorded inside spec `design.md` files (e.g. `audit-fixes-0-16-1` amends `audit-fixes-0-16-0`). Rationale otherwise in `CLAUDE.md`, `CHANGELOG.md` (release-please), commit bodies and `docs/MIGRATION_STRATEGY.md`.

## Specs & decisions
- Decision log: `.shipkit/decisions/`.
- Specs (each has `spec.md`, `design.md`, `tasks.md`): `.shipkit/specs/audit-fixes-0-16-0`, `audit-fixes-0-16-1`, `capture-source`, `credential-guard`, `environment-awareness`, `evidence-integrity`, `evidence-integrity-followup`, `occurrence-context-history`, `rails-70-request-capture`, `setup-hardening-0-14-3`, `solid-queue-hands-off`. These are all shipped through 0.16.1 as far as the commit log shows; no spec for unreleased work was found.
- Research: `.shipkit/research/` (uniqueness evidence, OSS business-case file).

## Gotchas
- **Host-app safety is law** — capture path must never raise, never block, must budget every op, clean up `Thread.current`, and always re-raise the original exception. See `CLAUDE.md` and the `host-app-safety` skill.
- **CQRS dirs live under `lib/`**, not `app/` — `lib/rails_error_dashboard/{commands,queries,services}/`.
- **No asset pipeline ever** — no Sprockets/Propshaft, no `app/assets/` directory at all. CSS/JS inline; external libs CDN-only.
- **Separate DB installs** — corrected: with a separate database selected (`--separate-database`, or `use_separate_database = true` detected in an existing initializer), the installer copies migrations to `db/error_dashboard_migrate/` (`install_generator.rb` ~line 344, since #83); otherwise `db/migrate/`. Since #93 it skips any migration the app already has in **either** folder (~lines 353-368), so an app moving from the main DB must move the files itself (`git mv db/migrate/*.rails_error_dashboard.rb db/error_dashboard_migrate/`; `docs/guides/DATABASE_OPTIONS.md`, "Moving From the Main Database to a Separate One"). `ErrorLogsRecord.connects_to` only fires when the `database.yml` entry exists, otherwise it logs an error and errors are NOT recorded (`engine.rb` lines 9-22). `USE_SEPARATE_ERROR_DB=true` env also sets the flag (`configuration.rb`).
- **Build-environment skip** — when `SECRET_KEY_BASE_DUMMY` is set (Docker asset precompile), the engine skips ALL runtime features (`engine.rb`).
- **Migrations are incremental over a squash** and must be replay-safe: a replay once wiped every error's environment (`2075c6b`). Timestamps are fixed; the installer must not reuse them. Two schema dumps in the demo app are generated, never hand-edited. `bin/check-schema-parity` exists for this.
- **Docs have two copies** — `_guides/` and `_reference/` mirror `docs/`; edit both, and grep content not filenames to find stale text.
- **Private I18n backend** — never write fixture locales into `config/locales/`; they break unrelated model specs. Dashboard strings go through `red_t`.
- **Optional deps degrade silently** — code must work without `browser`/`chartkick`/`httparty`/`turbo-rails`; test both ways.
- **Rails 7.0 before 7.0.10** records no unhandled request errors; `configuration.rb` (~line 741) warns at boot.
- **Spec hazards** — global config leaks between specs (reset in `after`), never run two rspec processes at once on the shared SQLite test DB, and keep `spec/dummy/db/test.sqlite3` in place.
- **Pre-commit runs chaos tests** — Lefthook stage 2 runs `bin/pre-release-test all`. Skip with `LEFTHOOK_EXCLUDE=chaos-tests`.
- **Solid Queue** — RED never writes Solid Queue's files (decision 0001); `solid_queue` generator and `services/solid_queue_config_check.rb` only advise.

## External touchpoints
- **Notifications:** Slack, Email, Discord, PagerDuty, Telegram, signed generic webhooks — `app/jobs/*_notification_job.rb`, `services/*payload_builder.rb`, `services/webhook_delivery.rb`.
- **Issue trackers:** GitHub / GitLab / Codeberg / Linear — `services/*_issue_client.rb`; inbound via `webhooks_controller.rb` (`POST webhooks/:provider`).
- **OpenTelemetry:** `integrations/o_tel.rb`, `integrations/tracer.rb`, `integrations/llm_span_processor.rb`.
- **LLM providers:** `services/llm_client.rb`, `llm_cost_estimator.rb`, `subscribers/llm_call_subscriber.rb`.
- **Deploy/release:** distributed as a RubyGem via release-please. CI in `.github/workflows/` — `ci.yml`, `test.yml`, `release.yml`, `pages.yml` (docs site), `smoke-test-demo.yml`. Live demo at `rails-error-dashboard.anjan.dev`.

## Pointers to deeper docs
- `CLAUDE.md` — architecture rules, testing, gotchas.
- `docs/` — `QUICKSTART.md`, `FEATURES.md`, `API_REFERENCE.md`, `PRODUCTION.md`, `UPGRADING.md`, `UNINSTALL.md`, `PLUGIN_SYSTEM.md`, `LLM_OBSERVABILITY.md`, `MIGRATION_STRATEGY.md`, `TROUBLESHOOTING.md`.
- `docs/guides/` — `DATABASE_OPTIONS.md`, `CONFIGURATION.md`, `NOTIFICATIONS.md`, `TRANSLATIONS.md`, `SOLID_QUEUE_SETUP.md`, `REAL_TIME_UPDATES.md`.
- `ROADMAP.md`, `CHANGELOG.md`; `.shipkit/` specs and decisions.

## Unverified / open questions
- Live-update (Turbo Streams) behaviour was inferred from `error_broadcaster.rb` and docs, not traced end to end `(unverified)`.
