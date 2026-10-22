# Design: Functional fixes for 0.17.0

## Approach
Four independent, small changes, each at the one place the bug lives, plus one accepted limitation:
- **Boot-crash import:** register RED's error-database hook before every other RED boot hook, so
  the crash import (and anything else at boot) runs on the error database.
- **Custom fingerprint:** the async worker stops completing a custom key with the application id.
  The request thread marks the identity as custom, and the worker uses it as is.
- **Reopen collision:** the reopen gets its own savepoint. On a unique violation it claims the
  unresolved row that holds the identity, as the create path already does.
- **Linear:** after the signature passes, check the signed body's `webhookTimestamp` against the
  server's clock.
- **Accepted:** the swallowed-exception tracker's at-exit sweep keeps its small window.

No schema, configuration or public API changes.

## Decision: Register the error-database hook first, at class level   (→ REQ-1)

**Context.** `engine.rb` connects `ErrorLogsRecord` to the error database in a
`config.after_initialize` hook. That hook is registered from inside the
`"rails_error_dashboard.database"` initializer, so it exists only once initializers run. The
engine's class-level `config.after_initialize` block, which calls `CrashCapture.import!`, is
registered earlier, when `engine.rb` is loaded. Hooks run in registration order, so the import
runs on the primary database. A runtime trace in a separate-database app showed
`import!` with `connection_db_config.name == "primary"`, then `connects_to(error_dashboard)`.
The import failed (no tables on primary), the crash file was renamed `.failed`, and the boot crash
was never recorded. The hook can't connect any earlier than `after_initialize`: `ErrorLogsRecord`
is an autoloaded model, and naming it during initializers raises `NameError`.

**Alternatives.**
1. Move the connection hook to class level, above the existing class-level block, so it is
   registered (and runs) first.
2. Move the crash import into the database hook, after `connects_to`.
3. Have `CrashCapture.import!` connect the error database itself, through a shared idempotent
   method.

**Case for 1.** It fixes the cause, not the one caller: every RED boot hook, now and later, runs
after the connection exists. It is a move, not new logic. The hook still checks
`use_separate_database` and the `database.yml` entry when it runs, so behaviour is unchanged for
shared-database apps.

**Case against 1.** Correctness rests on registration order inside one file. A later edit that
puts a new class-level `after_initialize` above it would bring the bug back. A comment says so,
and the chaos check below fails if it happens. Option 2 would make the order explicit in one block,
but leaves every other boot-time database use exposed.

**Decision.** Option 1.
**Falsifiability.** We would reverse this if a Rails release stops running `after_initialize`
hooks in registration order (seen as phase O failing in the separate-database chaos app), or if a
RED boot hook ever has to run before the error database is connected.
**Fired-if.** manual

## Decision: Prove the boot-crash import with the separate-database chaos app   (→ REQ-1)

**Context.** The bug only shows in a real boot of an app with two databases. The dummy app has one
database, and `after_initialize` has already run by the time any spec starts.

**Alternatives.**
1. Turn on crash capture in `full_separate_db`'s initializer template, inject the boot crash the
   `full_sync` app already uses (`inject_boot_error_and_crash`), and run phase O there, with an
   added check that the row is in the error database.
2. A spec that inspects ActiveSupport's private `@load_hooks` list for the order of RED's hooks.

**Case for 1.** It tests the behaviour a user sees: a boot crash in a separate-database
production app shows up on the dashboard. It reuses the existing injection and phase. It fails on
main today.

**Case against 1.** `full_separate_db` runs in the pre-commit chaos stage and before every
release, not in CI. Option 2 would run in CI, but it pins a private Rails structure and the order
of two blocks, not the outcome.

**Decision.** Option 1. The lab app's before-and-after runtime trace is the second proof.
**Falsifiability.** We would add option 2 as well if `full_separate_db` stops running before a
release (dropped from `bin/pre-release-test all` or from the release skill's checklist).
**Fired-if.** manual

## Decision: The worker uses a custom identity as is   (→ REQ-2)

**Context.** With `custom_fingerprint`, sync capture (`ErrorHashGenerator.call`) and the storm
gate (`Gate#custom_hash_for`, reconciled directly by `FlushStormCounts#canonical_hash`) store
`SHA256(key)[0..15]`. The async path sends the same value as `_identity`, but the worker's
`canonical_hash_from_identity` completes it with the application id:
`SHA256("#{that}|#{app_id}")[0..15]`. `capture_identity_parts` documents that a custom value "is
passed through unchanged", so the worker is the odd one out. Every `error_hash` lookup is also
scoped by `application_id`, so neither form is more correct. The choice only decides which hosts
see their custom groups restart once. The user chose this option on 2026-10-22.

**Alternatives.**
1. Mark custom identities in the async payload (`_identity_custom: true`). The worker uses a marked
   identity as is.
2. Make sync capture and the storm flush complete custom keys with the application id, the form
   the worker uses.

**Case for 1.** It changes one site and matches the design the code already documents. The storm
reconciliation, which depends on the gate computing the final hash with no database access, is
untouched. Sync-only hosts see no change. Async hosts' storm-counted rows, already stored in this
form, start receiving their queued captures too.

**Case against 1.** Hosts with both `async_logging` and `custom_fingerprint` see each custom group
restart once at upgrade: the row made by the worker stops counting, and a new row (or an existing
storm-counted row) takes over. The installer has written `async_logging = true` by default since
v0.6.3, so that may be most custom-fingerprint users. Option 2 would spare them, and move the cost
to sync-only hosts instead.

**Decision.** Option 1. Jobs queued before the upgrade carry no marker and keep today's hash until
they drain. The release notes carry one upgrade line for hosts with both settings.
**Falsifiability.** We would reverse this if, within three months of 0.17.0, two or more issues
report custom-fingerprint groups restarting or splitting after the upgrade.
**Fired-if.** manual

## Decision: A reopen that collides claims the row the index names   (→ REQ-3)

**Context.** `index_error_logs_on_group_identity` is unique over `application_id, error_hash,
COALESCE(environment,''), COALESCE(group_window,'')` for unresolved rows. Resolved rows from before
0.12.0 keep a NULL `group_window`, because the backfill stamped unresolved rows only. So once
unresolved, they all fall into the `''` bucket. A reopen never moves `occurred_at`, so the 24-hour
lookup never matches the reopened row again. With two or more such resolved rows, the next capture
reopens the next one, the `UPDATE` violates the index, and `LogError`'s rescue drops the capture.
That repeats on every capture of the error. Reproduced through `LogError` on SQLite and PostgreSQL.
`create_new_or_retry` already handles the same violation, with a savepoint and
`claim_conflicting_row`. `reopen_existing` has neither.

**Alternatives.**
1. Run the reopen's `update!` in a savepoint (`transaction(requires_new: true)`). On
   `RecordNotUnique`, increment the unresolved row that holds the identity the reopen tried to take:
   same application and hash, the environment after adoption, and the reopened row's
   `group_window`. Generalise `claim_conflicting_row` to take that environment and bucket.
2. A migration that stamps `group_window` on resolved rows too.
3. Stamp a NULL `group_window` from `occurred_at` when a row is reopened.

**Case for 1.** It is the guard the create path already has, applied to the one write that lacks
it. It catches every way a reopen can collide, not just the legacy one we found. It costs nothing on
the normal path. With no migration, hosts don't need to run anything in their deploy.

**Case against 1.** A host stuck in the legacy state pays for it on every capture of that error: one
failed `UPDATE` and a savepoint rollback before the increment, because the lookup keeps choosing the
same resolved row. Option 2 removes the state itself but rewrites history on big tables in the
host's deploy. Option 3 avoids the repeated failure, but reopens every legacy duplicate in turn,
one notification each, and still needs option 1 for duplicates from the same day.

**Decision.** Option 1. If no unresolved row matches, the violation is re-raised, as the create path
does.
**Falsifiability.** We would add option 2 if the overhead benchmark shows this fallback path above
the 5 ms capture budget, or if an issue reports slow captures traced to it.
**Fired-if.** manual

## Decision: Check Linear's signed `webhookTimestamp`, fail closed, fixed 60 seconds   (→ REQ-4, REQ-5, REQ-6)

**Context.** Linear's webhook docs (read 2026-10-22) put `webhookTimestamp`, a UNIX time in
milliseconds, in the JSON body, and recommend rejecting a delivery more than a minute from the
receiver's clock. Their sample answers 401. A `Linear-Timestamp` header carries the same value, but
the signature covers only the body.

**Alternatives.**
1. Read `webhookTimestamp` from the body inside `verify_linear_signature`, after the HMAC matches.
   Reject when it is missing, not a number, or more than 60,000 ms from now in either direction.
2. Read the `Linear-Timestamp` header.
3. Make the tolerance a configuration option.

**Case for 1.** The body is the signed part, so only a timestamp Linear signed is trusted. Failing
closed when it is missing matches the signature check beside it. It reuses the existing 401 path.
A fixed 60 s is Linear's own advice, and adds no setting to freeze for 1.0.

**Case against 1.** A host whose clock drifts more than a minute loses Linear syncs until the clock
is fixed. Linear retries at 1 minute, 1 hour and 6 hours, then gives up. Option 3 would let such a
host loosen the window, at the price of a new public setting.

**Decision.** Option 1. The API reference's 401 list gains the stale-delivery case.
**Falsifiability.** We would reverse the fail-closed rule if Linear documents a delivery without
`webhookTimestamp`, or if an issue reports a genuine Linear delivery rejected by this check.
**Fired-if.** manual

## Decision: Accept the swallowed-exception tracker's at-exit window   (→ none: out of scope)

**Context.** `SwallowedExceptionTracker` keeps per-thread counters. The periodic `flush!` reads only
the current thread's buffer, which only that thread's TracePoint callbacks write, so it cannot race.
A threaded probe lost 0 of 480,000 counts. `flush_all_threads!` runs once, from `at_exit`, and reads
other threads' buffers. Under a deliberately extreme load (the main thread sweeping millions of
times while workers raise), it lost 0.5% to 2% of counts. Detaching each buffer before reading it
(the swap the lead proposed) did not close the window in the same probe.

**Alternatives.**
1. Accept it: the at-exit sweep stays best-effort.
2. A Mutex around each buffer, taken on every raise and rescue.
3. The detach-then-read swap.

**Case for 1.** The sweep runs once, at process exit, when server threads are normally stopped or
idle. Counts after the final sweep are lost by design anyway. The tracker's safety contract (no
mutex on the per-raise path, about 500 ns per event) is what keeps it switchable on in production.

**Case against 1.** A thread still raising during the exit sweep can lose a few counts, and the
mechanism isn't fully pinned down. Option 2 closes it at a cost on every raise in the host app.
Option 3 measured no better.

**Decision.** Option 1. No code change.
**Falsifiability.** We would revisit this if an issue reports swallowed-exception counts missing
after a restart or deploy.
**Fired-if.** manual

## Data / interface changes
- The async job's context gains an internal key, `_identity_custom: true`, beside `_identity`
  (→ REQ-2). Keys with a leading underscore are never written as columns
  (`FindOrIncrementError#new_record_attributes`).
- `LogError.capture_identity_parts` (one caller) returns the context fragment to merge instead of a
  bare string (→ REQ-2).
- `claim_conflicting_row` takes the environment and window bucket to match (→ REQ-3).
- The webhook endpoint answers 401 to stale or undated Linear deliveries. `docs/API_REFERENCE.md`
  and `_reference/api-reference.md` say so (→ REQ-4, REQ-5).
- No migrations, no new configuration, no change to sync or storm hashes.

## Release notes (for the 0.17.0 notes, not a requirement)
- Hosts with both `async_logging` and `custom_fingerprint`: each custom group restarts once after
  the upgrade, because async captures now store the same fingerprint as sync and storm captures.
