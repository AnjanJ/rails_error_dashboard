# Design: Evidence integrity sprint

Decision records for the sprint specified in `spec.md`. Each records the context, the real
alternatives, the case for and **against** the choice, and a falsifiability clause.

Read `verification.md` first for the evidence behind each finding.

---

## D1. Storm reopen: lock the row, do not `update_all`

**Context.** `Commands::FlushStormCounts#reconcile_entry` has two branches. The
unresolved/`wont_fix` branch (`flush_storm_counts.rb:177-188`) uses an atomic
`ErrorLog.where(id:).update_all("occurrence_count = occurrence_count + ?")` — safe under
concurrency, which is why the reviewer's P2 control passed. The **resolved** branch
(`:199-212`) reads `resolved.occurrence_count` into Ruby, adds in memory, and writes an
**absolute** value via `update!`. Two concurrent batches both read 1, both write 6; five events
vanish while both report `success: true`. Reproduced on real PostgreSQL: 6 instead of 11.

**Alternatives.**
1. `resolved_scope.order(last_seen_at: :desc).lock.first` — a `SELECT … FOR UPDATE` held to
   commit (the call is already inside `ErrorLog.transaction`).
2. Switch the resolved branch to `update_all` with an atomic SQL increment, mirroring the
   branch above it.
3. Optimistic locking with a retry loop on `lock_version`.

**Case for (1).** It is one word. It restores parity with `Commands::FindOrIncrementError`,
which already uses `.lock` unconditionally for exactly this reason — so adapter portability is
already proven in this codebase (SQLite ignores `FOR UPDATE`; PG/MySQL honour it). It keeps
`update!`, so model callbacks still run. It matches the file's own idiom.

**Case against (1).** `FOR UPDATE` serializes concurrent storm flushes against the same resolved
group, which is a real throughput cost on the exact path that exists because the system is
already overloaded. It also gives no protection on SQLite, where the lock is a no-op — though
SQLite's writer serialization covers that in practice.

**Why not (2).** This is the trap the adversarial verifier caught, and it is the most important
decision in this record. `ErrorLog` has
`after_update_commit -> { Services::ErrorBroadcaster.broadcast_update(self) }`
(`app/models/rails_error_dashboard/error_log.rb:87`). `update_all` **bypasses callbacks**, so a
storm reopen would silently stop broadcasting live dashboard updates. The unresolved branch can
use `update_all` because it never changes displayed state beyond the count; the resolved branch
performs a *state transition* (resolved → new) that the dashboard must see. Choosing the
"more consistent" option here would trade a counting bug for a silent live-update bug.

**Why not (3).** `ErrorLog` has no `lock_version` column; adding one is a migration on the
hottest table in the gem, to solve a problem `.lock` already solves.

**Decision.** Option 1: add `.lock` to the resolved-row read. Keep `update!`.
**I would reverse this if** storm-flush p99 latency on a reopened group exceeds 50ms under
concurrent flushes, or if a profile shows lock contention on this branch is a measurable share
of flush time — in which case option 2 plus an explicit `broadcast_update` call is next.

---

## D2. Partial storm batch: distinguish transient from permanent failure

**Context.** The per-entry `rescue => e` at `flush_storm_counts.rb:57-66` treats every failure
identically. The rollback at `:70` fires only `if failed.positive? && counted.zero?`. So 1 of 2
entries failing → `counted=5`, batch finalized, digest recorded, and a replay returns
`already_applied: true`. Five events are lost permanently. The existing comment defends this
("replaying the batch would double them") and is **correct for permanent failures** — retrying a
corrupt payload loops forever.

**Alternatives.**
1. Re-raise transient errors out of the entry rescue so the whole transaction rolls back and the
   ledger claim is never committed; keep skip-and-continue for malformed entries.
2. Per-entry idempotency: record which entries within a batch were applied, and replay only the
   remainder.
3. Always roll back on any failure.

**Case for (1).** The gem already owns the exact taxonomy needed:
`LogError::RETRYABLE_STORE_ERRORS` (`log_error.rb:15`), already used at `:602` to decide
re-raise-for-retry. Reusing it keeps one definition of "transient". Rolling back an uncommitted
claim is safe by construction: nothing was written, so nothing can double. ActiveJob then
retries the whole batch. Small, local, and no new state.

**Case against (1).** A batch where entry 1 succeeds and entry 2 hits a transient error discards
entry 1's *work* (not its data) and redoes it on retry — wasted effort during a storm, the worst
time for wasted effort. It also assumes `RETRYABLE_STORE_ERRORS` is complete; an
adapter-specific transient error outside that list still silently strands entries.

**Why not (2).** It is the correct long-term answer and the review says so. It needs a per-entry
ledger — a new table or a JSON column of applied entry digests — which is a schema change plus
a new idempotency surface, to fix a failure mode that (1) already converts from *silent data
loss* into *retried work*. Loss is the bug; inefficiency is not.

**Why not (3).** It would make a single permanently-corrupt entry poison its whole batch forever
through every retry, converting a 1-event loss into an N-event loss. Strictly worse.

**Decision.** Option 1, and report the two classes distinguishably (REQ-6) so a future move to
(2) has the call sites already separated.
**I would reverse this if** production logs show transient aborts retrying the same batch more
than 3 times, or if storms routinely mix malformed and transient failures in one batch — either
means per-entry idempotency has become worth its schema cost.

---

## D3. Variable filtering: filter under the variable's own name

**Context.** `VariableSerializer.filter_serialized` passes `info[:value]` — the *inner* hash —
to `filter_hash_recursive`, which calls `filter.filter(hash)`. The variable's own name never
enters the key path, so a dotted pattern like `profile.private_note` can never match. Proven
standalone with the same `ActiveSupport::ParameterFilter`: the identical secret is `[FILTERED]`
when the full tree is passed and readable when only the inner hash is.

**Alternatives.**
1. Wrap before filtering: `filter.filter(var_name => info[:value])[var_name]`, and thread
   `parent_keys` through the recursive helpers.
2. Pre-scan patterns for dots and hand-roll the path matching.
3. Document that dotted filters do not apply to captured variables.

**Case for (1).** It reproduces Rails' semantics by *using* Rails' semantics rather than
reimplementing them, so it inherits correct handling of String, Symbol, Regexp and Proc patterns
for free — including Proc filters, which receive the key path and cannot be emulated by (2).
The unwrap is a single `[var_name]`.

**Case against (1).** Every captured variable's value now allocates a one-key wrapper hash
before filtering. On the capture path that is a real (if small) cost against NFR-2, paid per
variable per capture — mitigated by variable capture being opt-in.

**Why not (2).** Hand-rolling `ParameterFilter`'s matching is how filters drift apart. The whole
defect is that RED's filtering diverged from Rails'; the fix must not add a second divergent
implementation.

**Why not (3).** The gem's security posture explicitly claims Rails filters protect captured
variables. Documenting the gap is a retreat from a promise users rely on, for a leak that is one
wrapper hash away from being fixed.

**Decision.** Option 1.
**I would reverse this if** profiling shows the wrapper allocation costs more than 0.1ms per
capture at the p99 variable count — then pre-compute whether any configured pattern contains a
dot and take the cheap path when none does.

---

## D4. Window volume: new bucketed rollup table, not `COUNT(*)` over occurrences

**Context.** Every window figure filters the **group** table by `occurred_at` (first-seen, never
rewritten — confirmed at `find_or_increment_error.rb:197-212` and by the model's own comment)
and then sums the group's **lifetime** `occurrence_count`. A 23:59 error recurring at 00:01
reports `total_today = 0` and puts 2 on yesterday. This feeds ~15 methods across
`dashboard_stats.rb` and `analytics_stats.rb`.

The obvious fix — count `ErrorOccurrence` rows in the window — is **wrong**, and the adversarial
verifier found the proof: `spec/queries/analytics_event_counting_spec.rb:137-151` creates a
group with `occurrence_count: 250` and **zero** occurrence rows and asserts `total_today == 250`.
Storm-shed events deliberately write no occurrence row (that is the point of shedding). A pure
`COUNT(*)` silently erases storm volume — replacing a wrong-day bug with a missing-data bug.

**Alternatives.**
1. Add `rails_error_dashboard_event_counts(error_log_id, bucket_at, count)`, hour-bucketed, with
   the storm flush upserting into it; compute window volume as
   `occurrence rows in window + shed buckets in window`.
2. Interim: widen the group filter to `last_seen_at >= from OR occurred_at >= from`.
3. Count occurrences only, and accept that storm volume disappears from time windows.

**Case for (1).** It is the only option that makes the number *correct* for both ordinary and
shed events. It gives storm-shed volume a timestamp, which is the missing fact — a lifetime
counter genuinely cannot be bucketed after the fact. It also creates the aggregate-bucket
concept the architecture needs anyway (§D8), so the refactor gets cheaper rather than harder.

**Case against (1).** It is the largest change in the sprint: a migration, a `CountBuffer`
change to key tallies by hour bucket as well as identity, an adapter-portable upsert
(PG/SQLite `ON CONFLICT`, MySQL `ON DUPLICATE KEY UPDATE`), a new table to retain and prune, and
~15 call sites to route through one primitive. It is the one item that could slip.

**Why not (2).** The interim was proposed by the first verifier and **rejected by the
adversarial check**, which is exactly what adversarial review is for. It still sums the group's
*whole lifetime* count into the window: in the reproduction it reports `total_today = 2` when
one event happened today. Wrong in the opposite direction, and badly wrong for a long-lived
reopened group whose lifetime count is large. Shipping it would be a visible regression.

**Why not (3).** It breaks a documented, tested guarantee (the 250 spec) and makes the dashboard
lie hardest precisely during a storm.

**Decision.** Option 1, sequenced so the rollup table and `CountBuffer` bucketing land **first**
(T3.1–T3.3) and the query cutover second (T3.4–T3.6). Group-scoped metrics stay group-scoped
(REQ-15).
**I would reverse this if** the rollup table's write cost measurably slows storm flush (the path
that exists because the system is overloaded) — then fold the bucket into the existing
`StormFlushBatch` row instead of a new table.

---

## D5. User attribution: scope the fallback, do not take the max

**Context.** `AnalyticsStats#user_event_counts` merges occurrence-derived counts with
`group_user_counts` taking `max` per user. `group_user_counts` sums the group's lifetime
`occurrence_count` against whichever user touched it **last** (the group's `user_id` is
overwritten on every occurrence). For occurrences `{A:2, B:1}`, B's group figure is 3, `max`
keeps 3, and the result `{A:2, B:3}` is reported with `affected_users_incomplete: false` — a
total of 5 events for a 3-event group.

**Alternatives.**
1. Apply the fallback only to groups with **no** occurrence coverage in the window; for covered
   groups use occurrence counts alone.
2. Attribute only the uncovered remainder (`occurrence_count - occurrence rows`) to the group's
   last user.
3. Drop the fallback; count occurrences only.

**Case for (1).** It preserves the fallback's legitimate purpose (pre-tracking rows, fully-shed
groups) while removing the case where it corrupts good data. It is a scoping change to one
method. It also makes the `incomplete` flag honest, since a group is now either covered or not.

**Case against (1).** A *partially* shed group — some events with occurrence rows, some shed —
counts only its covered events, so the per-user number becomes a genuine undercount. That is a
real loss of information, traded for never overstating.

**Why not (2).** More accurate in the partial case, but it attributes shed events to the group's
*last* user, which is a guess. The review's sharpest line applies: a number that overstates a
user's events cannot be presented as an "at least" bound. Undercounting with an
`incomplete: true` flag is honest; guessing an identity is not.

**Why not (3).** Loses pre-tracking history entirely, for no gain over (1).

**Decision.** Option 1, with REQ-17's invariant (per-user sum ≤ window total) as an executable
assertion, and `incomplete` set for partially-covered groups.
**I would reverse this if** users report that storm-heavy workloads make per-user counts useless
— then (2) plus explicit "estimated" labelling in the UI.

---

## D6. Manual reporter `occurred_at`: honor it, but clamp it into the grouping window

**Context.** `ManualErrorReporter` documents `occurred_at:`, `app_version:`, `metadata:` and
`severity:`; storage silently uses `Time.current`, the server's version, `{}` params. The
adversarial verifier caught a hazard the first pass missed: `FindOrIncrementError#find_unresolved`
matches on `where("occurred_at >= ?", 24.hours.ago)` and `new_record_attributes` writes the
incoming `occurred_at` onto the new row. So naively honoring a backdated `occurred_at` creates a
group **permanently unmatchable** by future occurrences — every recurrence makes a new group.

Note also that `severity` is not a column: `ErrorLog#severity` is computed by
`Services::SeverityClassifier` from `error_type`. So "retain severity" cannot mean "store the
field"; it means either classify from the supplied value or reject the parameter.

**Alternatives.**
1. Honor `occurred_at` on the **occurrence** row and for display, but keep the **group's**
   `occurred_at` within the grouping window (clamp for grouping, preserve for the event).
2. Honor it everywhere, and widen/replace the grouping window.
3. Reject `occurred_at` explicitly (document it as unsupported) and delete it from the signature.

**Case for (1).** It gives the caller what they actually want — the event is timestamped when it
happened, which is the whole point for a mobile/frontend report arriving late — without
destabilizing grouping. It composes with D4: once window volume comes from occurrence rows, the
occurrence's true timestamp is what the dashboard reads anyway.

**Case against (1).** Two timestamps with different semantics on related rows is exactly the
event/group conflation §D8 wants to eliminate; this entrenches it slightly before the refactor
removes it. It also needs a clear rule for which one the detail page shows.

**Why not (2).** The 24-hour window is load-bearing for deduplication across the whole gem.
Changing it to accommodate a rarely-used manual parameter is a large blast radius for a small
feature.

**Why not (3).** Defensible and honest, and it is the right answer for `severity` (reject, since
there is no column and the classifier owns it). But for `occurred_at` it discards the genuine
use case that motivates the API.

**Decision.** Option 1 for `occurred_at` (clamped to not-future per REQ-23, and clamped into the
grouping window per REQ-24); honor `app_version` and `metadata`; **reject `severity` explicitly**
with a documented note that severity is classified from the error type.
**I would reverse this if** the dual-timestamp rule causes a second bug — then (3), and manual
reports get their own ingestion path that does not share group identity.

---

## D7. Job breadcrumbs: ownership-flagged buffer, guarding the async double-harvest

**Context.** `BreadcrumbCollector.init_buffer` has exactly one caller: the Rack middleware
(`error_catcher.rb:33`). Every subscriber early-returns `unless current_buffer`, so a background
job collects nothing and `breadcrumbs` is nil. The adversarial verifier found the trap: the async
path (`log_error.rb:460-469`) harvests the **current thread first** and only falls back to
`@context[:_serialized_breadcrumbs]` when that harvest is empty. Opening a buffer around
`perform` would make the *worker's own* crumbs shadow the ones captured at the original request.

**Alternatives.**
1. `init_buffer_unless_present` returning an ownership boolean; `ActiveJob` `around_perform`
   opens only if absent and clears only if it opened. The async job explicitly prefers the
   serialized envelope over a live harvest.
2. Unconditional init/clear in an `around_perform`.
3. Leave it; document that job breadcrumbs are unavailable.

**Case for (1).** Nesting-aware by construction: an inline job inside a request sees
`owned=false`, leaves the request's buffer intact, and its SQL joins the surrounding trail —
which is the behavior we already have and want to keep. The ownership flag is the standard
shape for re-entrant thread-local state, and the `ensure`-based teardown satisfies Safety Rule 4.

**Case against (1).** It adds thread-local lifecycle to a second place, and the async-harvest
precedence change (REQ-35) touches the capture path to fix a problem introduced by this feature
— a fix whose own fix is in another file is a smell, and the interaction must be tested directly.

**Why not (2).** It erases a surrounding request's buffer whenever a job runs inline
(`perform_now`, the test adapter, `:inline` queue) — a regression in a supported configuration.

**Why not (3).** The breadcrumb trail is the gem's headline investigation feature; "not in
background jobs" is a large hole, and jobs are where errors are hardest to reproduce.

**Decision.** Option 1, gated on `configuration.enable_breadcrumbs` (NFR-4), with an explicit
spec for the inline-nesting case and one for the async precedence.
**I would reverse this if** the ownership flag leaks across Puma thread reuse (Rule 4 / Puma
#823) in any test — then move the flag into the job's own local scope rather than thread-local.

---

## D8. Deliberately deferred: the canonical event envelope

**Context.** The review's central architectural point is correct: `ErrorLog` is simultaneously
identity, mutable request snapshot, lifetime counter, time-series source, release anchor and
workflow record. Findings F5, F6, F7 and F9 are all consequences of those roles colliding. The
recommended fix is to separate **event / error group / diagnostic exemplar / aggregate bucket**
and to build one immutable capture envelope shared by the subscriber, direct, manual, async and
storm paths.

**Alternatives.**
1. Do the refactor now, and fix the findings as part of it.
2. Fix the findings now; do the refactor next, informed by them.
3. Fix only the findings; never refactor.

**Case for (2).** The defects are live and some are security-relevant (D3, and the queue/export
boundaries); the refactor is weeks and touches every capture path in a gem that runs inside
other people's production processes. Shipping the fixes first removes user-visible harm now.
Critically, this sprint **builds toward** the refactor rather than away from it: D4 introduces
the aggregate-bucket concept, REQ-18 introduces a stamped envelope at the queue boundary, and
REQ-20 separates provenance from payload. Those are three of the four target concepts, arrived
at through small, individually-testable steps with tests that will still hold afterwards.

**Case against (2).** Some of this work will be rewritten by the refactor — the stamped-envelope
fields in D-C especially. We are paying twice for part of it, and each fix adds a little more
surface to migrate. There is also a real risk the refactor never happens once the symptoms stop
hurting, leaving the gem permanently at a local maximum with four near-duplicate capture paths.

**Why not (1).** It blocks the security-relevant redaction fixes behind a multi-week
architectural change, and does the refactor without the executable invariants this sprint
produces — which are exactly the tests that would make the refactor safe.

**Why not (3).** The review is right that the overlap is the root cause. Declining it
permanently means re-fixing this class of bug indefinitely.

**Decision.** Option 2. This sprint fixes contracts and leaves the invariants as tests. A
follow-up spec (`.shipkit/specs/event-envelope/`) is written at the end of this sprint, while
the findings are fresh, and references the tests added here as its acceptance harness.
**I would reverse this if** two or more of P1–P4's fixes turn out to need the envelope to be
correct rather than merely cleaner — that is the signal the refactor is a prerequisite, not a
successor.

---

## D9. PR grouping: five PRs by contract, not thirteen by finding

**Context.** 14 findings; the user asked for a PR per concern. Related fixes share files, tests
and reviewer context (F1/F2 are both `flush_storm_counts.rb`; F3/F4a/F4b are all redaction).

**Alternatives.** One PR per finding (14); one PR per contract (5); one PR total.

**Case for 5.** Each PR is one reviewable claim with one invariant ("counts are conserved",
"redaction is uniform"). Per-finding PRs would produce serial conflicts in
`flush_storm_counts.rb` and `log_error.rb`, and split a single test file across two reviews.
One PR total would bury a security fix in a 40-file diff.

**Case against 5.** P3 (event time + attribution) is large — a migration, a buffer change and a
query cutover. If it stalls, three requirements stall with it. Mitigated by sequencing the
migration first and keeping the query cutover behind it.

**Decision.** Five PRs: P1 storm conservation, P2 redaction parity, P3 event time + attribution,
P4 provenance + input honesty, P5 bounded work + job breadcrumbs + mobile. Atomic commits within
each. P1 and P2 are independent and can go in parallel; P3 depends on neither; P4 touches
`find_or_increment_error.rb` so it follows P1; P5 is fully independent.
**I would reverse this if** P3 exceeds ~25 files or two days of work — then split the rollup
table and the query cutover into separate PRs, the table landing first behind no behavior change.

---

## D10. Release shape: `fix:` commits, one minor release, user approval required

**Context.** `release-rules` is explicit: the version bump is derived from commit types, never
hand-edited, and **merging the release PR is the publish action and requires approval**.
The gem is at 0.13.0.

Most of this sprint is `fix:`. But REQ-12's rollup table is a migration, REQ-22's manual-reporter
fields are new retained behavior, and REQ-27 changes a default (unknown objects summarized rather
than `inspect`ed). Those read as `feat:`, which makes the release **0.14.0**.

REQ-27 deserves care: safe-by-default is a behavior change for anyone relying on `inspect`
output for custom types. The allowlist (REQ-29) keeps Struct/ActiveModel working, and the
changelog must call out the new `local_variable_inspect_*` options.

**Decision.** Conventional commits per task; `feat:` only where genuinely new
(rollup table, manual fields, serializer default); everything else `fix:`. Upgrade notes in the
changelog for the migration and the serializer default. **Stop before merging the release PR and
ask.** Use `Refs #NNN`, never `Fixes/Closes/Resolves`, so nothing auto-closes (issue #223 is the
tracking issue and belongs to its reporter).
**I would reverse this if** the serializer default proves disruptive in the dogfooding pass —
then ship REQ-27 opt-**in** (preserving today's behavior by default) and make safe-by-default a
1.0 change.
