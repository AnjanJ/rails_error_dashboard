# Design: Per-occurrence context history

## Approach
- **New table:** `rails_error_dashboard_error_occurrence_contexts`, one row per occurrence that had
  context.
- **The write:** `LogError` writes the row right after `ErrorOccurrence.create`
  (`log_error.rb:279`). It copies the same four JSON strings it just gave the error row, then trims
  the error's contexts to the newest `occurrence_context_limit`.
- **Viewing:** `?occurrence=ID` on the error page wraps `@error` in a decorator. The decorator
  returns that occurrence's four values and everything else from the error, so the existing card
  partials render it unchanged.
- **Finding them:** a new "Captured occurrences" card in the History tab lists the occurrences
  that have context. Today there is no occurrence list at all; the "timeline" partial lists
  related errors.

## Decision: a side table with the error row's four columns   (→ REQ-1, REQ-6, REQ-11)

**Context.**
- Today the context lives only on the error row, as four JSON text columns, and each recurrence
  overwrites it (`find_or_increment_error.rb:30-33, 254-270`).
- The occurrence row carries no context (`log_error.rb:279`).
- `CoOccurringErrors` loads occurrence rows with `SELECT *` (`co_occurring_errors.rb:42-62`).

**Alternatives.**
1. A 1:1 side table with four text columns named like the error row's.
2. A side table with one JSON `payload` column.
3. Four new columns on `error_occurrences`.

**Case for 1.**
- Each column holds exactly the string `LogError` writes to the row, so REQ-11 (the same values,
  same filtering) holds by construction.
- The decorator can return the columns directly, and the four card partials, which
  `JSON.parse(error.<column>)`, need no change.
- Occurrence queries never pay for the payload.

**Case against 1.**
- A fifth snapshot piece would need a migration here as well as on the error row.
- `error_log_id` is denormalized onto the context row to trim and delete by error without a join.
  That is a second source of truth for which error an occurrence belongs to.

**Decision.** Option 1, with `error_occurrence_id` (unique) and `error_log_id` (indexed).
**Falsifiability.** We would move to a single JSON payload column if a fifth context piece joins
the error row's refreshed context (`REFRESHED_CONTEXT` gains a fifth snapshot column).
**Fired-if.** manual

## Decision: write in LogError, beside the occurrence insert   (→ REQ-1, REQ-2, REQ-10, REQ-11)

**Context.**
- `ErrorOccurrence.create` has one application call site, `log_error.rb:279`. The four values are
  still in `attributes` there.
- They are nil for a storm `:lite` capture. A `:count_only` capture never reaches that line.
- On the async path the worker runs that same line with the pre-serialized values.

**Alternatives.**
1. Insert in `LogError` right after the occurrence, in its own rescue.
2. An `after_create` callback on `ErrorOccurrence`.
3. Inside `FindOrIncrementError`.

**Case for 1.**
- The values are in hand.
- REQ-2 is one presence check on the four values.
- A failure is logged and swallowed exactly like the occurrence insert's own rescue (REQ-10).
- Sync and async paths are covered by the same line.

**Case against 1.** `LogError#call` is already long. It also couples history to `LogError`, so a
future second writer of occurrences would bypass it.

**Decision.** Option 1, extracted to a small `Commands::RecordOccurrenceContext` that `LogError`
calls.
**Falsifiability.** We would move the write into a model method if a second code path starts
creating occurrence rows with full context (today `FlushStormCounts` writes only minimal
exemplars).
**Fired-if.** `test "$(grep -rln 'ErrorOccurrence.create' lib app | wc -l)" -gt 1`

## Decision: trim inline after each insert   (→ REQ-3, REQ-4)

**Context.** The limit is per error (default 25). Full-context captures are already bounded by
the storm ladder, which sheds context under load.

**Alternatives.**
1. After each insert, delete that error's context rows beyond the newest N, in the same rescue.
2. Trim in `RetentionCleanupJob`, periodically.
3. Trim only on every K-th insert.

**Case for 1.** The table never exceeds N rows per error, and the cost is one indexed DELETE per
full-context capture.

**Case against 1.** It adds an extra write to every full-context capture. That cost lands in the
worker on async installs, but on the request thread for sync installs.

**Decision.** Option 1. Where the limit is 0, nothing is written (REQ-4).
**Falsifiability.** We would move trimming to the retention job if the chaos storm phase's
capture throughput drops by more than 10% with history on versus off.
**Fired-if.** manual

## Decision: `?occurrence=` on the show page, with a decorator   (→ REQ-6, REQ-7, REQ-9)

**Context.**
- The four card partials read `error.breadcrumbs`, `error.system_health`, `error.local_variables`
  and `error.instance_variables`, and none of them is fragment-cached (checked).
- The sidebar also reads many other error fields.

**Alternatives.**
1. A query parameter on `errors#show`. The context is loaded through
   `@error.occurrence_contexts.find_by(error_occurrence_id:)`, so it is scoped to this error. A
   `SimpleDelegator` overrides the four readers.
2. A new route and page, `/errors/:id/occurrences/:oid`.

**Case for 1.**
- It is ROADMAP C3's design, and it reuses the whole page.
- Scoping through the association makes another error's context unreachable (REQ-9).
- A missing or foreign id falls back to the latest snapshot (REQ-7).

**Case against 1.** Request fields in the sidebar (URL, params, user) still show the error row's
latest values while the cards show the chosen occurrence. The banner has to say so.

**Decision.** Option 1. A banner names the occurrence and its time, says the context cards show
that occurrence, and links back to the latest.
**Falsifiability.** We would split it into its own route if more than the four context cards and
the banner ever need per-occurrence values.
**Fired-if.** manual

## Decision: deletes are explicit, with no foreign-key cascade   (→ REQ-5)

**Context.** Occurrences are deleted in two ways:
- with `delete_all` by `error_log_id` in `RetentionCleanupJob#delete_with_dependents`
  (`retention_cleanup_job.rb:47`), which `cleanup_resolved` also uses
- through `ErrorLog has_many :error_occurrences, dependent: :destroy`, which batch delete and
  destroy use

Uninstall discovers tables by prefix (`uninstall_plan.rb`).

**Alternatives.**
1. Explicit deletes. `delete_with_dependents` deletes contexts by `error_log_id` first;
   `ErrorLog has_many :occurrence_contexts, dependent: :delete_all`; `ErrorOccurrence has_one
   :context, dependent: :delete`. No FK constraint.
2. A FK constraint with `ON DELETE CASCADE`.

**Case for 1.**
- It's portable and testable on SQLite, PostgreSQL and MySQL alike.
- A missed delete path leaves only orphan rows; it never makes cleanup raise.
- It matches how `delete_with_dependents` already clears `event_counts`.

**Case against 1.** An orphan is possible if some future path deletes occurrences without going
through these.

**Decision.** Option 1.
**Falsifiability.** We would add an FK with cascade if an audit or spec ever finds context rows
whose occurrence no longer exists.
**Fired-if.** manual

## Data / interface changes
- **Migration** `create_rails_error_dashboard_error_occurrence_contexts`. Guarded by
  `return if table_exists?`, by convention (#273). Columns:
  - `error_occurrence_id` (bigint, not null, unique index)
  - `error_log_id` (bigint, not null, index)
  - `breadcrumbs`, `system_health`, `local_variables`, `instance_variables` (text)
  - `created_at`
- Also `spec/dummy/db/schema.rb` (`bin/check-schema-parity`). The squashed migration is not
  changed (precedent #273). (→ REQ-12)
- **Model** `ErrorOccurrenceContext < ErrorLogsRecord`, so it lives in the error database.
  Associations as above.
- **Config:** `occurrence_context_limit` (Integer, default 25; `validate!` requires >= 0). It
  also gets a row in the initializer template, a Settings page row with descriptions in all 11
  locales, and a CONFIGURATION.md row. (→ REQ-3, REQ-4, REQ-13)
- **UI:**
  - the "Captured occurrences" card in the History tab (newest first, at most the limit; reads
    `id`, `error_occurrence_id`, `created_at` and the occurrence's `occurred_at` and
    `app_version`, never the payload) (→ REQ-8)
  - the banner, with new locale keys in all 11 locales (→ REQ-6)
- **Release tooling:** the scenario runner's `RED_TABLES` goes from 14 to 15.
