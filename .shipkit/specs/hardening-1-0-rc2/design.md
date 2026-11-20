# Design: 1.0 hardening (1.0.0-rc.2)

## Approach
Ten small workstreams, each its own pull request, in the order of `tasks.md`. The two that change what 1.x
freezes (grouping v2, the grouping window) go first. Two spikes come before the code they decide: S1 (host
conditions) by 2026-12-04, and S2 (silent failures). Neither spike changes product code; each writes its
evidence to `.shipkit/research/` and amends this spec.

Constraints that hold for every decision (`.shipkit/product.md`, `.claude/skills/host-app-safety/`):
- Never raise into the host, never block a request, always re-raise the original exception.
- Budgets: capture < 5 ms before the response, storm check < 15 µs. Every capture-path pull request runs
  `bin/benchmark`, and its numbers go in the pull request body.
- Anything new on the request path can be switched off by config.
- Migrations are replay-safe and additive.

Facts this design rests on, all checked on 2026-11-20 at `4afd12db`:
- The fingerprint is computed in three places, each through `ErrorHashGenerator.opaque_identity`:
  - sync capture: `ErrorHashGenerator.call`, via `log_error.rb:545`
  - async capture: `LogError.capture_identity_parts`, `log_error.rb:318-337`
  - the storm gate: `storm_protection/gate.rb:235-240`
  `FlushStormCounts#canonical_hash` (`flush_storm_counts.rb:480-497`) recomputes from the buffered parts
  only when no digest was buffered.
- Open groups are matched on `occurred_at >= 24.hours.ago` in three places:
  - `find_or_increment_error.rb:87` (the lookup)
  - `find_or_increment_error.rb:361` (the duplicate-create retry)
  - `flush_storm_counts.rb:462` (the storm flush)
- One cooldown claim (`last_notified_at`, `notification_throttler.rb:56-68`, `:215-225`) is taken per
  notification. `ErrorNotificationDispatcher` then enqueues one job per channel
  (`error_notification_dispatcher.rb:48-73`). Every channel job catches every error itself, so the
  `retry_on StandardError, attempts: 3` in `application_job.rb:20` never runs for them.
- Rails' controller-level `content_security_policy` edits a per-request copy of the host's policy
  (actionpack 8.0.4: `metal/content_security_policy.rb:40-52`, `:82-84`; `http/content_security_policy.rb:187-189`).
- Trusted-publishing pushes are not held to `rubygems_mfa_required`. In rubygems.org (`master`), the check
  passes whenever the key isn't a user's (`app/models/pusher.rb:60`: `!api_key.user? || owner.mfa_enabled?`),
  and a trusted publisher's key isn't (`app/models/api_key.rb:79-85`, `:91-102`). The release runs on
  trusted publishing (`.github/workflows/release.yml:131-154`). A manual `gem push` with a user key will
  need MFA.

## Decision: The v2 fingerprint recipe   (→ REQ-1, REQ-2, REQ-3, REQ-4)

**Context.** v1 hashes the absolute path of the first frame without `/gems/` in it
(`error_hash_generator.rb:146-151`). Reproduced on 2026-11-20:
- one file under two release directories gave two hashes (`ebbad6e0…`, `85137a4c…`);
- `u.nme` and `u.emial` gave one hash, because the message normaliser turns both quoted names into `''`
  (`:135`);
- `Integer("abc")` was hashed on `<internal:kernel>`.

**Alternatives.**
1. The path relative to `Rails.root`, plus the line number.
2. The path relative to `Rails.root`, plus the frame's method name (`base_label`), plus `NameError#name`
   when the exception is a `NameError`.
3. Keep v1 and document `custom_fingerprint` as the fix.

**Case for 2.**
- A method name survives edits above it, which a line number doesn't, so a group doesn't split on every
  unrelated change to the file.
- `NameError#name` is exactly the part the normaliser threw away. Adding it back splits typos without
  touching the normaliser, which every path shares.
- The maintainer chose it on 2026-11-20.

**Case against 2.**
- Two bugs in one method that raise the same class with the same normalised message still merge.
  Line numbers would split them.
- Renaming a method starts a new group.
- `base_label` drops the block depth, so `block in foo` and `foo` share a group, on purpose.

**Decision.** Option 2. The digest input becomes:
`error_class | normalised_message | "<relative_path>#<base_label>" | name:<NameError#name> | controller | action`.

The `name:` part appears only for a `NameError`, and has its digits replaced with `N` like the message.

The frame is the first location that passes all of these:
- its path is not under `/gems/`;
- it doesn't start with `<internal:`;
- it isn't under `RbConfig::CONFIG["rubylibdir"]`.

The path is made relative by removing whichever of `Rails.root.to_s` and `Rails.root.realpath.to_s` it
starts with, so a symlinked `current` and a real `releases/<ts>` both work. A path outside `Rails.root`
stays as it is.

When there are no `backtrace_locations` (a backtrace set from strings), the same rule parses
`path:line:in 'label'`.

**Falsifiability.** We would reverse this if, within 60 days of 1.0.0, two or more issues report distinct
bugs merging in one method that line numbers would have separated.
**Fired-if.** manual

## Decision: Rows grouped under v1 keep their occurrences   (→ REQ-5, REQ-6)

**Context.** Every open group a host has today carries a v1 hash. A recipe change that ignores them
starts a fresh group, and sends a fresh "new error" alert, for every live error on the first capture
after the upgrade. The raw data needed to recompute v2 for old rows (the full message, the backtrace
locations) isn't stored, so old rows can't be rehashed.

**Alternatives.**
1. Dual lookup. Each capture carries both identities. The lookups match `error_hash IN (v2, v1)`,
   preferring v2. A row found by its v1 hash gets the v2 hash in the same locked update.
2. A migration that rehashes every row from what is stored (the truncated backtrace, the redacted
   message).
3. A `fingerprint_version` column, and two parallel lookups keyed by version.

**Case for 1.**
- No migration and no new column.
- A live group moves to v2 on its next occurrence and is never split.
- Groups that never recur keep v1 and age out under retention.
- The fallback is one `IN` clause, removed in 2.0.

**Case against 1.**
- Every capture computes two digests. That costs microseconds, and the benchmark will show it.
- Two v1 groups that differed only by release directory stay two rows: only the current directory's one
  is matched again, and the other ages out.
- 1.x carries the fallback code until 2.0.

**Decision.** Option 1.
- Each capture carries `_identity` (v2), `_identity_v1` (v1) and `_identity_version: 2`.
- A job with no `_identity_version` was enqueued by rc.1 or earlier, so its `_identity` is v1 and it is
  completed as v1 (REQ-6).
- `custom_fingerprint` gets no v1 (REQ-7).
- If storing the v2 hash raises `RecordNotUnique`, the row keeps v1 and the capture is still counted.
- `docs/PUBLIC_API.md` names the recipe as stable for 1.x (REQ-8). `.shipkit/decisions/0010` records it
  project-wide.

**Falsifiability.** We would reverse this if `bin/benchmark`'s capture median rises by more than 0.2 ms
against rc.1 on the same runner.
**Fired-if.** manual

## Decision: One identity function, and the storm gate's hot path   (→ REQ-1 to REQ-6)

**Context.** The three call sites build the identity separately today. The storm gate runs per capture
during a storm, inside a 15 µs budget.

**Alternatives.**
1. One `ErrorHashGenerator.identities(exception, context)` returning
   `{ v2:, v1:, custom: }` for all three call sites. The storm gate computes v2 per capture, and v1 only
   when it creates a new buffer entry. The entry stores v1 beside v2.
2. Each call site computes both identities inline.

**Case for 1.**
- One place to get the recipe right, and one place for 2.0 to delete v1.
- The storm gate's per-capture cost stays one digest. A storm is many hits on few fingerprints, so v1
  is computed a handful of times.

**Case against 1.** A buffer entry gains a field, so `CountBuffer` and `FlushStormCounts` change. Buffers
written by rc.1 hold no v1. They flush through `opaque_identity` as v1, the same rule as REQ-6.

**Decision.** Option 1.
**Falsifiability.** We would reverse this if `bin/benchmark`'s storm-check median exceeds 15 µs with it.
**Fired-if.** manual

## Decision: Match an open group by its last occurrence   (→ REQ-9, REQ-10, REQ-11)

**Context.** An open error that keeps happening starts a new row once it is 24 hours past its first
occurrence (reproduced: two rows after 25 h). The new row takes the "new error" path: a first-occurrence
notification, `on_error_logged`, and triage reset to "new". `group_window` (a UTC day bucket) lets the
unique index tell a deliberate new group from a racing duplicate
(`20260915000001_add_group_identity_unique_index_to_error_logs.rb`).

**Alternatives.**
1. Match on `last_seen_at >= 24.hours.ago`, falling back to `occurred_at` for legacy rows with a NULL
   `last_seen_at`.
2. Keep `occurred_at`, and document the daily rollover as frozen behaviour.
3. No window: one open group per fingerprint until it is resolved.

**Case for 1.**
- A chronic error stays one row with one triage state for as long as it keeps happening.
- A new group starts only after 24 quiet hours, which is a real "it came back".
- The index still holds: a new group needs 24 quiet hours, so it is created at least a day after the
  old group's creation day, in a different `group_window`.

**Case against 1.**
- "New errors today" counts fewer rows than before.
- Per-occurrence context refresh (`REFRESHED_CONTEXT`) now covers a group's whole life, not just its
  first day.
- An error that recurs every 23 hours for a year is one row. That is the point, but it's a visible
  change.

**Decision.** Option 1, applied at all three lookups:
`last_seen_at >= :cutoff OR (last_seen_at IS NULL AND occurred_at >= :cutoff)`.

`clamped_group_time` stays: it still keeps a backdated `occurred_at` inside the window for legacy rows.
Option 3 was rejected because it changes reopen semantics and the unique index.

**Falsifiability.** We would reverse this if `EXPLAIN` of the lookup on PostgreSQL stops using an index
that leads with `error_hash` (`index_rails_error_dashboard_error_logs_on_error_hash` or
`index_error_logs_on_hash_resolved_occurred`, `spec/dummy/db/schema.rb:232-234`) because of the OR.
**Fired-if.** manual

## Decision: Host conditions are decided by spike S1   (→ REQ-17 to REQ-22)

**Context.** Three failures were reproduced on SQLite, Rails 8.0.4:
- a capture inside a host transaction that rolled back was lost;
- a capture inside `while_preventing_writes` was lost;
- a starved pool (`checkout_timeout` 2 s) blocked the reporting thread for 4.01 s and stored nothing.

The two waits are `find_or_create_application` and its fallback (`log_error.rb:899-904`).

**Alternatives** (the spike tries each on SQLite, PostgreSQL 16 and MySQL 8, under Rails 7.2, 8.0 and
8.1, in sync mode and in async mode with Solid Queue on the same database):
1. RED writes through its own small connection pool: an abstract class with `connects_to` the host's
   database configuration, a pool of 1-2 and a short `checkout_timeout`.
2. Transaction-aware writes on the shared connection. Inside an open host transaction, the write waits
   for the transaction to end, through Rails 7.2's transaction callbacks, and is written after a rollback
   too. A prevented write runs under `connected_to(role: :writing)`.
3. Hand the write to a bounded background thread with its own connection checkout.

**Case for running the spike first.**
- Option 1 would fix all three findings with one mechanism, but it adds 1-2 database connections per
  process. That matters on PostgreSQL plans with tight connection limits.
- Whether `while_preventing_writes` reaches a separately connected class is unverified.
- Async mode adds a fourth case: a job enqueued inside a transaction that rolls back is dropped when
  the queue shares the database.

**Case against.** The spike costs about two days before any fix. If it overruns 2026-12-04, these fixes
miss rc.2 and ship in rc.3, as the intake decided.

**Decision.**
- Spike S1 first. It writes `.shipkit/research/host-conditions-spike.md`: a table of mechanism by
  database by Rails version by mode, the extra connections, the capture-time change, and the config
  switch.
- This spec is then amended with the chosen option as its own decision record.
- Until the amendment, the switch, the timeout and the held-pool setup are the provisional terms in
  `spec.md` (Host conditions): `isolate_capture_writes` (default true) and `capture_connection_timeout`
  (0.1 s). Both are config names frozen at 1.0, so the amendment confirms them or renames them before
  rc.2.
- REQ-21 doesn't wait for the spike. On `ActiveRecord::ConnectionTimeoutError` (or any
  `ActiveRecord::ConnectionNotEstablished`), `find_or_create_application` re-raises instead of trying
  `Application.first`, so the capture gives up after one wait.

**Falsifiability.** We would skip the spike if one option passes all four cases on all three databases in
the first day.
**Fired-if.** manual

**Outcome (2026-11-20).** The spike ran and finished on its first day, so the condition above is moot. Option 2
passed every case; the next record holds the decision. This record stays as the plan the spike followed.

## Decision: Captures wait for the host's transaction, on the shared connection (from spike S1)   (→ REQ-17 to REQ-20, REQ-22, REQ-51 to REQ-53)

**Context.** Spike S1 (`.shipkit/research/host-conditions-spike.md`) ran each option on SQLite, PostgreSQL 16,
MySQL 8.4 and MySQL 26.10, under Rails 7.2.4, 8.0.5.2 and 8.1.4.1, in sync mode, async mode with Solid Queue on the
same database, and async mode inside a request. All of it was reproduced. What rc.1 does:
- **Lost, with no log line:** a capture in a rolled-back transaction or savepoint, in every cell, sync and async
  outside a request. On Rails 7.2 the async job is dropped after Rails has already marked it enqueued.
- **Lost, with a log line:** a capture under `while_preventing_writes` or a reading role, in every cell, on
  "Lock query".
- **Blocked on a held pool:** 4 s sync, 6 s async outside a request, 6 s after the response in a request, and
  10 s with a separate error database, at a `checkout_timeout` of 2 s.

**Alternatives.**
1. RED's own pool through `ErrorLogsRecord.connects_to` (pool 2, timeout 0.1 s), with or without wrapping each
   capture in `ErrorLogsRecord.connected_to(role: :writing, prevent_writes: false)`.
2. The shared connection, in three parts:
   - Inside an open host transaction, the capture waits for that transaction's `after_commit` or
     `after_rollback` (public API in Rails 7.2+). It checks again after each one, so a savepoint waits for its
     parent.
   - The sync write runs under `ActiveRecord::Base.connected_to(role: :writing, prevent_writes: false)`, and
     leases RED's pool and the host's with a wait of at most `capture_connection_timeout`.
   - The async enqueue gets the same, leasing only the host's pool.
3. A bounded in-process worker thread that writes or enqueues the async payload.

**Case for 2.**
- **It is the only option that kept every case.** That's 7 transaction and write-prevention cases in all 36 runs
  (12 cells × 3 modes), with a separate error database too.
- **The held-pool wait becomes one bounded wait:** 0.10 to 0.11 s sync, and after the response in a request.
- **It adds no database connection**, against +2 per process for option 1 (5 → 7, counted by the server), and
  about 2 µs per capture.
- **Async capture is fixed too.** The enqueue waits for the transaction, which neither option 1 nor rc.1 does.
- **It keeps sync capture synchronous.** The write still happens before the request returns.

**Case against 2.**
- **The write moves to the transaction's end.** A capture inside a long transaction is stored late, and lost if
  the process dies first. rc.1 would lose that one too: its INSERT was inside the same uncommitted transaction.
- **It holds a closure per capture until the transaction ends.** A storm inside one transaction would grow that
  list without the cap in REQ-52.
- **The bounded lease relies on a private pool method** (`connection_lease`; Rails has no public
  "lease with a timeout").
- **In a reading role the write goes to the writing database.** In a multi-region setup with a far writer, that
  is a round trip on the request (sync capture). Not measured: there was no remote database. rc.1 drops the
  capture instead.

**Why not 1 or 3.**
- **Option 1 on SQLite** loses every capture inside a host write transaction, including one that commits, and
  on Rails 8.0 and 8.1 the caller waits 5 s first. It doesn't help async capture at all.
- **Option 3:**
  - On SQLite under Rails 7.2 it lost captures, and in async mode stalled the host's own transaction for 5.44 s.
  - With pool size equal to thread count, Rails' default, it dropped 2 of 5 captures.
  - A first version looped through `executor.wrap` and `Rails.error`.
  - Its queue is lost on exit.

**Decision.** Option 2, accepted by the maintainer on 2026-11-20 with both names, the reading-role write and the
private-lease fallback.
- **The deferral sits after the ignore filter and the storm gate,** at the branch between sync and async in
  `LogError.call`, so count-only storm events never wait.
- **At most 100 captures wait per transaction** (REQ-52). Further ones are dropped.
- **A deferred capture is stamped with the time it was reported** (REQ-51), through the same `_captured_at` the
  async path uses (`log_error.rb:170`).
- **The guard lives in a new service,** `Services::CaptureWriteGuard`: `defer(&blk)`, `allow_writes(pools, &blk)`
  and `lease(pool, timeout, &blk)`. `LogError` calls it at the entry, around `#call`, and around `enqueue_async`.
- **The lease falls back when the private method is missing.** It uses `ConnectionPool#checkout(timeout)` and
  sets the private `connection_lease` only if `respond_to?(:connection_lease, true)`. Otherwise it falls back to
  the pool's own wait (rc.1's behaviour) and logs once at debug. `host_conditions_spec.rb` pins it on 7.2, 8.0
  and 8.1.
- **Names, both kept:**
  - `isolate_capture_writes` (default `true`): with `false`, there's no deferral, no write-allowance and no
    lease, so rc.1's behaviour (REQ-22);
  - `capture_connection_timeout` (default `0.1`): the lease's wait.
- **REQ-21 (T13) still lands separately.** With the lease, the application lookup can't reach a second wait,
  but with `isolate_capture_writes = false` it still can.

**Falsifiability.** We would revisit this if T30's `bin/benchmark` capture median is more than 0.2 ms above rc.1's,
or if, after 1.0.0, two or more issues report a capture stored late or lost because it waited for a long host
transaction.
**Fired-if.** manual

## Decision: Notifications retry transient failures and release the claim   (→ REQ-29 to REQ-33)

**Context.**
- Every channel job catches every error itself, so a timeout loses the alert.
- The claim is taken once per notification, before the jobs are enqueued, and nothing undoes it.
- The webhook job posts every URL in one job (`webhook_error_notification_job.rb:22-24`).
- Webhook posts carry `X-Error-Dashboard-ID`, the error's id, but no per-delivery id
  (`webhook_delivery.rb:63-68`).

**Alternatives.**
1. Each channel raises a `TransientDeliveryError` on a timeout, a refused or reset connection, a DNS
   failure, HTTP 429, HTTP 5xx, or an SMTP 4xx. Each job declares
   `retry_on TransientDeliveryError, wait: :polynomially_longer, attempts: 3`, and the block that runs
   when retries are used up releases the claim. The webhook dispatch enqueues one job per URL. The
   delivery id is a digest of the job's `job_id` and the URL.
2. The same, but the webhook job keeps all its URLs, so a retry re-posts every URL.
3. A delivery table recording each send's state.

**Case for 1.**
- Rails keeps `job_id` across `retry_on` retries, so the delivery id is stable with no new job argument.
  `retry_job` enqueues `dup` (activejob `exceptions.rb:151-156`), and `@job_id` is set only in
  `initialize` (`core.rb:95`).
- One job per URL means a retry only re-posts the URL that failed.
- The subclass's `retry_on` is registered after the base class's, so Rails checks it first (lesson
  2026-09-15: rescue handlers resolve in reverse order).
- Option 3 adds a table and a write per send.

**Case against 1.**
- Releasing the claim lets the next occurrence notify every channel again, including the ones that
  succeeded, so receivers see duplicates. That is at-least-once by definition.
- A job enqueued before the upgrade has no claim time, so its failure releases nothing.
- One job per URL multiplies jobs by the number of URLs.

**Decision.** Option 1.
- The claim is released only if `last_notified_at` still equals the claim time the job was given (a new
  optional job argument), so a newer claim is never undone.
- The in-process claim (no column, `notification_throttler.rb:227-238`) is not released. It lives in
  another process.
- `X-Error-Dashboard-Delivery` is added to the contract's headers. Decision 0005 allows new headers in
  1.x.
- `docs/WEBHOOKS.md` says delivery is at-least-once.

**Falsifiability.** We would reverse the claim release if, after 1.0.0, two or more issues report
duplicate alerts on channels that had succeeded.
**Fired-if.** manual

## Decision: CreateIssueJob decides on retries from a result code   (→ REQ-34, REQ-35)

**Context.**
- A failed result is counted at `create_issue_job.rb:35`, raised, and counted again by the `rescue` at
  `:43`.
- The no-retry check at `:38` matches English text against a translated message, so in German it retries
  "already linked".

**Alternatives.**
1. `CreateIssue` returns `code: :already_linked | :not_configured | :failed`, and the job branches on
   `code`. A raised error is counted only in the `rescue`.
2. Compare against the translated strings.

**Case for 1.** It works in any locale, and the code can't drift from the copy.

**Case against 1.** `CreateIssue`'s return value gains a key, and any caller reading only `:error` still
works.

**Decision.** Option 1.
**Falsifiability.** No clear reversal condition identified: option 2 is wrong in any non-English locale.
**Fired-if.** manual

## Decision: The audit actor setting and how "unverified" is stored   (→ REQ-36 to REQ-39)

**Context.**
- `resolved_by_name`, `assigned_to` and `muted_by` come from free-text form fields
  (`_modals.html.erb:15`, `:54`, `:167`).
- There is no history table. Workflow comments credit the assignee, not the actor
  (`snooze_error.rb:36`, `update_error_status.rb:38`).
- Basic auth knows one shared username. `authenticate_with` returns true or false, not a user.
- The setting's name is frozen at 1.0 (decision 0008).

**Alternatives for the setting.**
1. `config.dashboard_actor`, a lambda run with `instance_exec` in the dashboard controller, like
   `authenticate_with`: `-> { current_user&.email }`.
2. `config.dashboard_actor`, given the request: `->(request) { … }`.
3. Make `authenticate_with` return the user.

**Alternatives for storage.**
1. Three nullable boolean columns: `resolved_by_verified`, `assigned_to_verified`, `muted_by_verified`.
2. A new `error_events` audit table: action, actor, verified, time.

**Case for setting 1 with storage 1.**
- `instance_exec` matches `authenticate_with`, which hosts already write, and reaches `current_user`
  directly.
- Changing what `authenticate_with` returns would break every host using it.
- Three nullable columns are a cheap additive migration on every database.
- NULL is honest for old rows: they were typed, so they show as unverified.
- A full audit table is a feature, which decision 0002 keeps after 1.0.

**Case against.**
- Three columns where one table would scale to more actions.
- A later audit table will duplicate them.

**Decision.** Setting 1, storage 1.
- `dashboard_actor` returns a string or nil.
- If it raises, the typed name is kept as unverified, and the action still completes (REQ-38).
- The issue-tracker webhook's `"Webhook"` actor counts as verified, because the request is signed.
- On the error page (`_sidebar_metadata.html.erb:167-174`, `:242-243`, `:263-266`), a name whose
  `*_verified` is not true is followed by `<span class="red-actor-unverified">` holding the locale key
  `red.workflow.unverified` ("unverified" in English). The key is added to every locale file, as the
  i18n check requires.

**Falsifiability.** We would replace the columns with an audit table if a 1.x feature needs to record a
fourth action's actor.
**Fired-if.** manual

## Decision: The dashboard's own content security policy   (→ REQ-42, REQ-43)

**Context.**
- The layout's script tags carry the nonce; its one `<style>` block doesn't, and its views carry 513
  inline `style` attributes.
- A host whose `style-src` uses a nonce blocks both: with a nonce present, browsers ignore
  `'unsafe-inline'`.
- No dashboard controller sets a policy today.

**Alternatives.**
1. Put the nonce on `<style>`. Add a controller-level `content_security_policy` to the dashboard's base
   controller that, only when the host has a policy, adds `style-src-attr 'unsafe-inline'` to that
   request's copy.
2. Docs only.
3. Move the 513 attributes into classes.

**Case for 1.**
- Rails clones the host policy per request, so pages outside the dashboard are untouched.
- `style-src-attr` loosens only attributes, not `<style>` elements or scripts.

**Case against 1.** Browsers without `style-src-attr` (older Safari) fall back to `style-src` and still
block the attributes. Option 3 fixes that but is out of scope (intake).

**Decision.** Option 1. With no host policy, nothing is added, so no new header appears. The request spec
checks both the header and the `<style>` nonce.
**Falsifiability.** We would do option 3 if an issue reports the dashboard unstyled under a host policy in
a browser that supports `style-src-attr`.
**Fired-if.** manual

## Decision: Occurrence retention and the overdue banner   (→ REQ-23 to REQ-26)

**Context.**
- The retention job expires whole groups by `last_seen_at` (`retention_cleanup_job.rb:30`), so a live
  group's occurrences are never deleted.
- The gem doesn't schedule the job.
- `ErrorOccurrenceContext` holds a foreign key to the occurrence (`error_occurrence_context.rb:11`).
- The non-goal "no quotas on the user's own data" means it is opt-in.

**Alternatives.**
1. `occurrence_retention_days` (nil by default) handled in `RetentionCleanupJob#perform`. It deletes
   occurrence contexts, then occurrences, with `occurred_at < cutoff`, 1,000 at a time, using the
   existing `(occurred_at, error_log_id)` index.
2. A separate job the host schedules.

**Case for 1.** One job to schedule, already documented. The rake task's preview can count both.

**Case against 1.** Two concerns in one job, and a slow occurrence delete delays group expiry. Batching
bounds each statement, though.

**Decision.** Option 1.
- The banner shows while `retention_days` is set and `expired_scope(now - retention_days - 2.days)`
  has a row. The two days of grace cover a job that runs daily.
- The check is cached for an hour under the analytics cache generation. Expired rows still existing
  *is* the evidence that the job isn't running, so nothing else is stored.

**Falsifiability.** We would split out a separate job if one run deletes occurrences for longer than 10
minutes in the chaos fixture.
**Fired-if.** manual

## Decision: MTTR in SQL   (→ REQ-44)

**Context.** `mttr_stats.rb:42-102` loads every resolved row and subtracts times in Ruby, once per week
of the trend.

**Alternatives.**
1. `AVG` of a per-adapter duration expression:
   - PostgreSQL: `EXTRACT(EPOCH FROM resolved_at - occurred_at)`
   - MySQL: `TIMESTAMPDIFF(SECOND, occurred_at, resolved_at)`
   - SQLite: `(julianday(resolved_at) - julianday(occurred_at)) * 86400`
   It is grouped by platform, by severity and by week.
2. Pluck `(occurred_at, resolved_at)` pairs and average in Ruby.

**Case for 1.** No rows leave the database, and one query per breakdown instead of one per week.

**Case against 1.** Three SQL dialects, so the adapter matrix in CI has to cover it.

**Decision.** Option 1. Severity is derived from `error_type` in Ruby today (`e.severity`), so the
by-severity figure groups by `error_type` in SQL and folds the groups by severity in Ruby.
**Falsifiability.** We would fall back to option 2 if the three dialects disagree by more than 1 second
on the same fixture.
**Fired-if.** manual

## Decision: `user_id` out of range, and bigint for fresh installs   (→ REQ-15, REQ-16)

**Context.** `user_id` is `primary_key_type || :integer` (complete-schema migration `:282-285`), so it's
32-bit on PostgreSQL and MySQL. `storable_user_id` (`error_log.rb:223-227`) has no range check.

**Alternatives.**
1. Range-check against the column's byte size: an id out of range is stored as nil. Fresh installs
   default to `:bigint`. Existing columns stay as they are.
2. A migration that widens existing columns.

**Case for 1.** Widening rewrites the table on PostgreSQL and MySQL under a lock, during the host's
deploy, which is what the migration-lock finding warns about.

**Case against 1.** Upgraded installs keep 32-bit columns, so a host with large user ids stores nil until
it widens the column itself. The upgrading guide says how.

**Decision.** Option 1. The same range check covers `ErrorOccurrence.user_id`, which is written at
`log_error.rb:736`.
**Falsifiability.** We would ship the widening migration if an issue reports a host losing user ids to
the range check.
**Fired-if.** manual

## Decision: The chaos tests on every database and Rails version   (→ REQ-50)

**Context.**
- Every chaos app runs on SQLite except `full_upgrade`, which picks its database from `UPGRADE_DATABASE`
  through `use_database_server` (`bin/pre-release-test:1161-1181`, `:1215-1238`).
- A Phase G already exists (`test/pre_release/chaos/phase_g_quick_wins.rb`).
- CI's PostgreSQL and MySQL adapter jobs run Rails 8.1 only (`test.yml:104`). The SQLite matrix covers
  7.2, 8.0 and 8.1 (`test.yml:28`).
- Transaction and connection-handling behaviour is exactly what changes between Rails versions.
  Revised 2026-11-20, when the maintainer asked how this lands for users on every Rails version: the
  first version of this record checked PostgreSQL and MySQL under 8.1 only.

**Alternatives.**
1. A new target `full_host_conditions` that takes `HOST_DATABASE` (`sqlite`, `postgresql` or `mysql`)
   and `RAILS_VERSION` (`7.2`, `8.0` or `8.1`), reusing `use_database_server`, and runs a new
   `phase_q_host_conditions.rb`. CI runs it as a 9-row matrix job (database by Rails), with the same
   `services:` as `test.yml`'s adapter job.
2. The same target, but with CI on three rows (each database under Rails 8.1), leaving 7.2 and 8.0 on
   PostgreSQL and MySQL to local runs.
3. Add the scenarios to an existing SQLite app only.

**Case for 1.**
- A host on Rails 7.2 with PostgreSQL gets a CI check of the fix it runs, not just an 8.1 proxy for it.
- The rows run in parallel, so the job takes about as long as one row.

**Case against 1.**
- 9 rows of about 2 minutes each: around 18 runner-minutes per push that touches the paths.
- Three times the exposure to a flaky service container.

**Decision.** Option 1. Locally, PostgreSQL 16 and MySQL run as Homebrew services.
**Falsifiability.** We would drop to option 2 if the PostgreSQL or MySQL rows fail on a flaky service
container on more than 2 of 20 runs.
**Fired-if.** manual

## Decision: Repair an invalid group-identity index with a new migration   (→ REQ-48, REQ-49)

**Context.** `20260915000001` returns early if the index name exists (`:70`). On PostgreSQL, a failed
`CREATE INDEX CONCURRENTLY` leaves an invalid index with that name, so a re-run skips it and the race
the index prevents comes back.

**Alternatives.**
1. A new PostgreSQL-only migration. If `pg_index.indisvalid` is false, drop the index concurrently, merge
   duplicates, and build it again concurrently. Otherwise do nothing.
2. Edit the shipped migration.

**Case for 1.** Hosts that already ran the shipped migration never run it again. Only a new migration
reaches them.

**Case against 1.** A migration file that does nothing for almost every host.

**Decision.** Option 1. The duplicate-merge code is copied into the new migration, because a migration
can't rely on another migration's class.

REQ-49 is a spec. For migrations with a timestamp after the last one in rc.1, it scans `db/migrate/` and
requires `algorithm: :concurrently` and `disable_ddl_transaction!` when a migration calls `add_index` on
a table it doesn't create.

**Falsifiability.** No clear reversal condition identified: option 2 cannot reach the hosts that need it.
**Fired-if.** manual

## Smaller changes (one obvious way each, so no decision record)
- **REQ-21:** described in the host-conditions decision above.
- **REQ-27, REQ-28:** `BatchDeleteErrors` calls `RetentionCleanupJob.delete_with_dependents(ErrorLog.where(id: ids))`,
  then `AnalyticsCacheManager.clear`, then dispatches `on_errors_batch_deleted` with the ids it plucked.
- **REQ-40, REQ-41:** the keydown handler (`layout:2297-2316`) returns early on `e.ctrlKey || e.metaKey || e.altKey`
  and on `SELECT`.
- **REQ-45:** `FilterOptions` follows `dashboard_stats.rb:27`:
  - `Rails.cache.fetch(["filter_options", app_id || "all", AnalyticsCacheManager.generation].join("/"), expires_in: 5.minutes)`;
  - the dashboard's write commands already bump the generation;
  - capture does not (`error_log.rb:106-108`), so a new error type appears in the filter within 5 minutes;
  - a cache error falls back to the query.
- **REQ-46:** `skip_path?` (`local_variable_capturer.rb:151-158`):
  - skips a `tp.path` that doesn't start with `Rails.root` (computed once);
  - skips one under `Rails.root/vendor/`;
  - skips one under RED's own `Engine.root`;
  - skips `<` and `(` paths, as today.
  It runs inside a `:raise` TracePoint, so it stays prefix checks only. The same `/ruby/` heuristic in
  `error_normalizer.rb:120`, `issue_body_formatter.rb:55` and `backtrace_parser.rb:111,147` is out of
  scope; it affects display, not capture.
- **REQ-47:** the three `description`s start with "Example:". `docs/PLUGIN_SYSTEM.md:312-347` stops showing the
  Jira plugin registered in production.
- **REQ-13:** wording in `README.md:128`, `:646`, `:668`, plus sync's figures from
  `.shipkit/research/deploy-shape-benchmark.md:224,242`.
- **REQ-14:** `spec.metadata["rubygems_mfa_required"] = "true"`. `docs/` release notes say a manual
  `gem push` will need MFA.

## Spike S2: silent failures (no decision until the maintainer reads it)
The spike measures these things on the capture path:
1. Every `RailsErrorDashboard::Logger.error` call site, and what each prints. The capture-failure line
   prints the capture's context and a backtrace (seen 2026-11-20: `user_id`, `request_url`, …), so it
   may carry personal data into the host's logs.
2. How often each can fire under a storm with a broken schema.
3. The cost of one `Rails.logger.error` call on the capture path, with a synchronous file logger and with
   STDOUT.

The options it compares:
- `log_level :error` as it is;
- `:error` with the context removed and one line per class per minute;
- a per-process failure count on the health page, with no log I/O;
- no change.

It writes `.shipkit/research/silent-failures-spike.md`. The maintainer then picks, and this spec gains
the requirement.

## Data / interface changes
- **Config, new and frozen at 1.0:**
  - `occurrence_retention_days` (nil) → REQ-23, REQ-24
  - `dashboard_actor` (nil) → REQ-36 to REQ-38
  Decision 0002 gets a dated scope note allowing these two.
- **Config, kept by S1 (2026-11-20):** `isolate_capture_writes` (true) and `capture_connection_timeout` (0.1)
  → REQ-17 to REQ-20, REQ-22, REQ-51 to REQ-53. These are fixes to the capture path rather than features, but
  they are still public names, so decision 0002's note covers them too.
- **New service:** `Services::CaptureWriteGuard` (internal; not in `docs/PUBLIC_API.md`).
- **Migration:** three nullable booleans on `rails_error_dashboard_error_logs`: `resolved_by_verified`,
  `assigned_to_verified`, `muted_by_verified` → REQ-37.
- **Migration:** the PostgreSQL-only repair of `index_error_logs_on_group_identity` → REQ-48.
- **Complete-schema migration:** `user_id` defaults to `:bigint` for fresh installs → REQ-16.
  `spec/dummy/db/schema.rb` follows, checked by `bin/check-schema-parity`.
- **Async job context:** `_identity_v1` and `_identity_version: 2` → REQ-5, REQ-6.
- **Storm buffer entries:** `opaque_identity_v1` → REQ-5.
- **Notification jobs:** an optional `claimed_at` argument → REQ-31. Webhook dispatch: one job per URL
  → REQ-32.
- **Webhook header:** `X-Error-Dashboard-Delivery` → REQ-32.
- **`CreateIssue` result:** gains `code:` → REQ-35.
- **Gemspec metadata:** `rubygems_mfa_required` → REQ-14.
