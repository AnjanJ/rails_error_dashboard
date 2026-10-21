# Intake: Per-occurrence context history (ROADMAP C3)

> Intake taken on 2026-10-15.

## Request
0.16.0: keep the moment-of-failure context (system health, breadcrumbs, local and instance
variables) for the last N occurrences of an error, browsable per occurrence. Needs a migration;
ships in one minor release with capture-source.

## Serves goal
None. There is no `.shipkit/product.md`; suggest `/shipkit:product` afterwards.

## Conflicts found
- **Deferred event envelope.** `.shipkit/specs/_shipped/evidence-integrity/design.md` §D8 deferred a
  canonical immutable event envelope to `.shipkit/specs/event-envelope/`, which was never
  written. Per-occurrence context is one piece of such an envelope. The user decided to build C3
  **standalone**; the envelope stays deferred and can absorb it later.
- **Stale status lines, housekeeping only.** All six earlier specs lack a `> Status:` line, so
  they read as open, but they have shipped (0.11.0 to 0.14.3). This is not a conflict with C3.
- No decision record contradicts C3. The only record is
  `.shipkit/decisions/0001-red-never-writes-other-gems-files.md`.

## Answers
1. Standalone or the envelope's first slice? **Standalone.** Build it as ROADMAP C3 designs it.
2. On by default or opt-in? **On, with the last 25 per error**, set by
   `config.occurrence_context_limit` (0 turns it off).
3. Which goal? **None** (no product.md).

## Assumptions made
- **Where context lives today** (per the grandfather):
  - One snapshot per error group, as JSON text columns on `rails_error_dashboard_error_logs`:
    `breadcrumbs`, `system_health`, `local_variables`, `instance_variables`, plus request
    scalars and provenance (`context_captured_at`, `context_fidelity`).
  - Refreshed on recurrence by `FindOrIncrementError#latest_context`
    (`find_or_increment_error.rb:30-33, 118-122, 254-293`).
- **The C3 payload** carries the same four snapshot pieces. The ROADMAP C3 text names
  system-health, breadcrumbs and variables. `request_params` is NOT included: it refreshes through
  a different path and is the one piece the sensitive-data filter redacts.
- **Storm protection:**
  - A `:lite` capture writes an occurrence row but no snapshot, so it gets no context row.
  - A `:count_only` capture writes no occurrence row at all (`log_error.rb:56`).
  - So storage stays bounded by the storm ladder, as ROADMAP C3 says.
- **Side table, not a column:** `rails_error_dashboard_error_occurrence_contexts`, 1:1 with an
  occurrence. `CoOccurringErrors` loads occurrence rows with `SELECT *`
  (`co_occurring_errors.rb:42-62`), so a column would make it pay for multi-KB payloads.
  - `CascadeDetector` already plucks, so the ROADMAP note about cascades is stale there.
- **Retention:** occurrences are deleted from `RetentionCleanupJob#delete_with_dependents` by
  `error_log_id` (`retention_cleanup_job.rb:46-62`) and through
  `has_many :error_occurrences, dependent: :destroy` (`error_log.rb:38`). Context rows must be
  deleted on both paths.
- **The error row keeps its latest snapshot (C2)** exactly as today. C3 adds history and changes
  nothing about the row.
- **Upgrades:** an incremental migration, so this is a minor release. The installer and upgrade
  path test, and the demo's two schema dumps, change with it.

## Out of scope
- The canonical event-envelope refactor (evidence-integrity §D8).
- Per-occurrence `request_params`, user, URL or user agent history.
- Changing how the error row's latest snapshot (C2) is refreshed.
- Backfilling history for occurrences recorded before the upgrade.
