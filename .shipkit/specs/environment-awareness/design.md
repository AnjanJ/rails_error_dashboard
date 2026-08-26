# Design: Environment awareness

## Approach

Mirror the **platform** dimension everywhere it exists — that is the pattern the codebase
already has for a per-error categorical: a column with an `[x, occurred_at]` index, a
`FILTERABLE_PARAMS` entry, `ErrorsList#filter_by_x`, `FilterOptions` distinct pluck, a select +
chip on the index, a conditional column in `_error_row` (also honoured by `ErrorBroadcaster`),
a sidebar badge linking to the filtered index, and an analytics `group(:x).count` chart. The
only places environment goes *beyond* platform are dedup (a match dimension) and notifications
(an allowlist), and both are small.

The column is guarded with `ErrorLog.column_names.include?("environment")` on every write path,
exactly like the enriched-context columns, so a host that upgrades the gem before running the
migration keeps working.

## Decision: environment is a match dimension, not a fingerprint input   (→ REQ-9, REQ-10, REQ-11)

**Context.** `FindOrIncrementError` matches on `(error_hash, application_id)` plus a 24 h
window (`find_or_increment_error.rb:38-54`); `application_id` is *also* baked into the digest
(`error_hash_generator.rb:33-40`). There is no unique index on `error_hash`
(`20251223000000` lines 114-143), so two rows may share a hash.

**Alternatives.**
1. Add environment to the digest (like `application_id`). Every existing row's hash becomes
   stale for new occurrences → duplicates after upgrade unless every row is re-hashed, and the
   storm gate key and `FlushStormCounts#canonical_hash` must change in lockstep.
2. Add environment to the `WHERE` only, with NULL treated as a wildcard that is **adopted** on
   first match.

**Case for the match dimension.** No hash change anywhere — the gate, the flush job, the
similar-errors and cascade queries are untouched. Upgrades need no backfill: the first new
occurrence of a live error claims the legacy row and stamps it. A process has exactly one
environment, so in-process storm bucketing cannot mix environments; only the database can,
and that is where the match lives.

**Case against.** A legacy row that recurs in *two* environments after the upgrade is claimed
by whichever fires first; the other environment then gets a fresh row. That is the correct end
state, reached one occurrence late. Rows that never recur stay NULL and show no badge unless
the opt-in backfill task is run.

**Decision.** `where(environment: [env, nil])` ordered exact-first
(`CASE WHEN environment IS NULL THEN 1 ELSE 0 END`), and `environment: env` written on
increment/reopen when the row's is NULL. `FlushStormCounts` does the same with
`COALESCE(environment, ?)` in its `update_all` (portable across pg / mysql / sqlite).

**Falsifiability.** We would move environment into the digest if a user reports a cross-
environment merge that adoption cannot explain, or if the extra `CASE` ordering is measured to
cost more than 1 ms on the dedup query at 1M rows.

## Decision: one allowlist, checked at the single choke point   (→ REQ-22 – REQ-24)

**Context.** `LogError` reaches `ErrorNotificationDispatcher` through three gates — new
(`severity_meets_minimum?`), reopened (`should_notify?`), threshold (`threshold_reached?`) —
all of which funnel through `maybe_notify` (`log_error.rb:424-431`), which already checks
muted and storm suppression. Storm notifications (`gate.rb:232`) and baseline alerts dispatch
separately.

**Alternatives.**
1. Per-channel allowlists (five options).
2. One `notification_environments` list, checked in `maybe_notify` plus the two separate
   dispatch sites.

**Case for one list.** Three insertion points, one predicate
(`NotificationThrottler.environment_allowed?`), one config option to document. Per-channel
routing is what `notification_callbacks` lambdas are for today.

**Case against.** "Slack for everything, PagerDuty for production only" needs a lambda.
Acceptable for v1; the falsifiability clause covers it.

**Decision.** `notification_environments` (nil = all). Checked in `maybe_notify`, in
`Gate.maybe_storm_notification`, and in the baseline alert dispatch, using the error log's
environment where there is one and the process environment otherwise.

**Falsifiability.** We would add per-channel lists if three or more users ask for channel-
specific routing that a callback lambda cannot express cleanly.

## Decision: email subject gets a second key, not a changed one   (→ REQ-26, REQ-20)

**Context.** `red.mailers.error_alert.subject` is `"🚨 [%{application}] %{error_type}:
%{message}"` in eleven locales, and `bin/i18n-check` fails on interpolation mismatch across
locales.

**Alternatives.**
1. Change the existing key to add `%{environment}` — eleven edits, and a host that pins an
   old locale file (they cannot — the backend is private) is fine, but a nil environment
   renders `[Shop · ]`.
2. Add `subject_with_environment`, used only when the error has an environment.

**Decision.** Option 2. Same shape for Slack/Discord/PagerDuty/webhook: a field is appended
only when present, so legacy rows render exactly as today.

**Falsifiability.** None — this is a compatibility choice with no measurable reversal trigger.

## Data / interface changes

- **Migration** `20260826000001_add_environment_to_error_logs.rb`: `add_column
  :rails_error_dashboard_error_logs, :environment, :string, limit: 64` +
  `add_index [:environment, :occurred_at], name: "index_error_logs_on_environment_and_occurred_at"`,
  guarded with `return if column_exists?`. No default: NULL means "captured before this
  version", which is information, not a bug.
- **`spec/dummy/db/schema.rb`** gains the column and index (rails_helper loads the schema,
  not the migrations); version bumped to `2026_08_26_000001`.
- **Configuration**: `environment` (`ERROR_DASHBOARD_ENVIRONMENT`), `notification_environments`
  (`ERROR_DASHBOARD_NOTIFICATION_ENVIRONMENTS`), and `current_environment` (resolved: option,
  else `Rails.env`, else `"unknown"`). `validate!` per REQ-2/4.
- **`ErrorLog`**: `scope :by_environment`; `environment` also added to
  `FILTERABLE_PARAMS`, `ErrorsList#filter_by_environment`, `FilterOptions[:environments]`,
  `AnalyticsStats[:errors_by_environment]`.
- **`LogError`**: `attributes[:environment] = (context[:environment].presence ||
  config.current_environment)` when the column exists.
- **`FindOrIncrementError` / `FlushStormCounts`**: environment match + adoption.
- **`NotificationThrottler.environment_allowed?(error_log_or_env)`**.
- **Payload builders**: Slack/Discord field, webhook + PagerDuty key `environment`, mailer
  label row + `subject_with_environment`.
- **Formatters**: `MarkdownErrorFormatter` and `IssueBodyFormatter` metadata line.
- **Rake** `rails_error_dashboard:backfill_environments`.
- **i18n keys (all 11 locales)**: `red.errors.index.filters.all_environments`,
  `red.errors.index.filters.chips.environment`, `red.errors.index.environment`,
  `red.errors.sidebar.environment`, `red.errors.sidebar.view_all_environment`,
  `red.analytics.overview.environment_chart.title`, `red.notifications.error_alert.labels.environment`,
  `red.mailers.error_alert.labels.environment`, `red.mailers.error_alert.subject_with_environment`,
  `red.settings.descriptions.environment`, `red.settings.descriptions.notification_environments`.
- **Docs**: `docs/guides/CONFIGURATION.md` + `_guides/configuration.md`, `docs/FEATURES.md`,
  README feature bullet, initializer template, CHANGELOG prose block for 0.11.0.
