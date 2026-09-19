# Tasks: Evidence integrity — follow-up

Test first for every task: write the failing test, watch it fail **for the right reason**, then
fix. **NFR-F8 binds every task below: the test covers the dimension, not the reported instance.**
A task is not done because the reviewer's probe went green.

**Environment.** Prefix everything:

```sh
cd /Users/anjan/code/RED/rails_error_dashboard
env -u RAILS_VERSION mise exec ruby@3.4.5 -- bundle exec rspec <path>
```

`spec/dummy/db/test.sqlite3` must exist (gitignored). Chaos tests run via `bin/with-ruby`.
`bin/check-schema-parity` also needs `bin/with-ruby`. Commit with `env -u RAILS_VERSION` or
bundle-audit blocks the hook. `LEFTHOOK_EXCLUDE=chaos-tests` skips the slow stage locally.

**The broad-pattern trap.** The spec helper loads the whole suite from a single file path, so
`rspec one_spec.rb` runs everything and `--bisect` reports meaningless example IDs. Filter with a
`:tag` or `-e`. This has now cost time twice — see [[red-notification-burst-seed-flake]].

**Never** write `Fixes/Closes/Resolves #223`. Use `Refs #223`. Do not close any issue.

**Baseline before starting:**

```sh
env -u RAILS_VERSION mise exec ruby@3.4.5 -- bundle exec rspec --exclude-pattern 'spec/system/**/*'
# expect 5064 examples, 0 failures, 1 pending
cp ../review-evidence/2026-09-19-followup/boundary_spec.rb spec/followup_probe_spec.rb
# expect 10 failures (R1, R2, R3, R4, R5a, R5b, R6, R7, R8, R9); remove the file afterwards
```

---

## P-F1 — One redaction policy, every container shape (`fix:`) — **security, ship first**

Branch `fix/redaction-container-parity`. Files: `services/variable_serializer.rb`.

- [ ] **T-F1.1** Failing spec matrix asserting **Rails parity**, not broader matching. With
  `filter_parameters = ["profile.private_note"]`, the expected result per shape is what
  `ActiveSupport::ParameterFilter` itself produces — **verified by running it** (see
  `verification.md` "Amendment evidence"):

  | Variable `profile` | Rails filters it? | Assert |
  |---|---|---|
  | `{private_note: "S"}` | yes | `[FILTERED]` |
  | `[{private_note: "S"}]` | yes | `[FILTERED]` ← **the R6 bug** |
  | `[[{private_note: "S"}]]` | yes | `[FILTERED]` |
  | `{list: [{private_note: "S"}]}` | **no** — path is `profile.list.private_note` | secret **survives** |
  | `"S"` (scalar) | **no** — path is `profile` | secret **survives** |

  The last two rows are the point: the contract is *parity with Rails*, not maximal redaction.
  Asserting redaction there would demand more than Rails does and drive an over-redacting fix.
  Add a second matrix with `filter_parameters = ["profile.list.private_note"]` to show the
  nested case redacts when the pattern actually names its path. → REQ-F1, REQ-F2
  Put it in `spec/services/variable_serializer_spec.rb` beside the existing filtering examples.
- [ ] **T-F1.2** Establish the pipeline explicitly as **bounded serialization → path-aware
  filtering → display metadata**. Today `filter_serialized` receives values that *already* carry
  `type`/`truncated`, which is why T-F1.3 could not be satisfied by editing it in place. Filter
  the raw serialized value under its own name — `filter.filter(var_name => value)[var_name]` —
  in ONE call for all container types, then attach metadata. Delete the separate Hash and Array
  branches (`variable_serializer.rb:~266`). → REQ-F1, REQ-F4 (`design.md` §F2)
  **Do not** hand-roll dotted matching. Proc filters receive `(key, value)` and optionally
  `(key, value, original_params)` — **not** a constructed dotted path (verified). Wrapping under
  `var_name` preserves those semantics precisely because `ParameterFilter` does the walking.
- [ ] **T-F1.3** Assert the ordering directly: no code path may observe a value carrying display
  metadata that has not yet been filtered. This is a structural requirement on the pipeline in
  T-F1.2, not an extra check bolted onto the old order. → REQ-F4
- [ ] **T-F1.4** Extend the matrix to instance variables under their `@`-stripped name, and to
  String/Symbol/Regexp/Proc patterns. → REQ-F3, REQ-F5
- [ ] **T-F1.5** Confirm unchanged: the existing **31** filtering examples in
  `variable_serializer_spec.rb` — 17 in `"sensitive variable filtering"` (`:155`) and 14 in
  `"filtering deep dive"` (`:297`), including the Regexp-pattern and dotted-path ones. They are
  what prove Rails' semantics survive replacing the per-shape branches with one wrap.
- [ ] **T-F1.6** Full suite + RuboCop. PR: "fix: apply dotted redaction to every captured value
  shape (Refs #223)".

---

## P-F2 — One event-volume model + a real cleanup path (`fix:`) — **largest; sequence carefully**

Branch `fix/event-volume-parity`. Files: `queries/analytics_stats.rb`, `queries/event_volume.rb`,
`app/models/rails_error_dashboard/event_count.rb`,
`app/jobs/rails_error_dashboard/retention_cleanup_job.rb`, migration comment.

### The invariant first (this is the point)

- [ ] **T-F2.1** **Write this before any cutover and watch it fail.** Cross-page invariant spec:
  for the same window and filter set, `DashboardStats` and `AnalyticsStats` report the same event
  total. → REQ-F8
  This is the test that would have caught R1 — each page was internally consistent and they
  disagreed with each other. Reproduce the reviewer's case: a group first seen in August,
  recurring in September, 30-day window → both pages agree, and neither says 0 while the user
  table shows an event.
- [ ] **T-F2.2** Internal-consistency spec for Analytics. For an **exhaustive** breakdown
  (by_type, by_day — every event falls in exactly one bucket) assert **equality** with the
  headline total, not `≤`. `≤` would let an empty or broken breakdown pass, which is the failure
  mode being guarded against. Use `≤` only where a breakdown is genuinely partial (e.g. a
  top-N list, or a dimension that can be NULL), and say which it is in the spec. Also: a window
  whose user table is non-empty never totals zero. → REQ-F9

### The cutover

- [ ] **T-F2.3** **Inventory every volume reader first, then classify each as EVENT or GROUP.**
  "Analytics is wrong, Overview is right" was false — Overview is only *partly* cut over. The
  real inventory is **21 `sum(:occurrence_count)` sites across 5 files** (verified):

  | File | Sites | Notes |
  |---|---|---|
  | `queries/analytics_stats.rb` | 12 | zero `EventVolume` refs |
  | `queries/dashboard_stats.rb` | 5 | **`top_errors` (`:172`) and `errors_by_severity_7d` (`:198-205`) still use first-seen + lifetime sum** |
  | `queries/platform_comparison.rb` | 2 | `:165`, `:175` |
  | `queries/user_impact_summary.rb` | 1 | `:49` |
  | `services/digest_builder.rb` | 1 | `:69` |

  Record the classification in the spec folder as the durable answer to "which unit is this
  figure?", so a future reader cannot re-derive it wrongly. Route every EVENT figure through
  `Queries::EventVolume`; leave GROUP figures alone and say so. → REQ-F6
- [ ] **T-F2.4** Leave `total_groups`, `unresolved`, `resolved` on `base_query` filtering by
  first-seen `occurred_at` — correct for group metrics. Extend the existing comment at `:67-73`
  to say which unit each figure uses and why. Apply the same treatment to any GROUP figure the
  T-F2.3 inventory identifies in the other four files. → REQ-F7
- [ ] **T-F2.5** Confirm unchanged: `spec/queries/analytics_event_counting_spec.rb:137-151` (the
  250-count storm-shed group with zero occurrence rows), `:86-95` (`error_rate == 400.0`) and
  `:123-135` (`affected_users_incomplete`). These constrain the fix exactly as they did last time.

### Time zone

- [ ] **T-F2.6** Failing spec: at `00:15` on 2026-09-20 in `Asia/Kolkata`, a fresh capture reports
  `today == 1`. → REQ-F10 (reviewer's R2; note +05:30 is deliberately non-whole-hour)
- [ ] **T-F2.7** Convert to the application zone in SQL before `DATE(...)` in
  `event_volume.rb#day_expression` (`:182`), per adapter: PostgreSQL `AT TIME ZONE`, MySQL
  `CONVERT_TZ` (**requires host tz tables** — document it), SQLite by offset (`'localtime'` is
  **not** equivalent). Derive window boundaries from the same zone. → REQ-F10 (`design.md` §F4)
- [ ] **T-F2.8** Cover positive, negative and non-whole-hour offsets, plus a DST transition, and
  and implement the **15-minute** bucket granularity §F4 decides, so +05:30/+05:45 local
  midnights fall on a bucket edge. Acceptance: a shed event at 23:59 local and one at 00:01 local
  report 1/1 — not 2/0 — at offsets +05:30, +05:45, −03:00 and UTC. The SQLite offset mechanism
  must use the offset **in force at each row's timestamp**, proven by a DST-spanning test.
  → REQ-F11

### Cleanup path

- [ ] **T-F2.9** Failing specs: deleting an `ErrorLog` removes its `EventCount` rows; retention
  removes them for expired groups. → REQ-F23, REQ-F24 (reviewer's R5a / R5b, both currently
  leaving `orphan_buckets: 1`)
- [ ] **T-F2.10** Add **`has_many :event_counts, dependent: :delete_all` to `ErrorLog`** — not
  `dependent:` on `EventCount`'s `belongs_to`. Rails rejects that option on a `belongs_to`:
  verified, it raises `ArgumentError: The :dependent option must be one of [:destroy, :delete,
  :destroy_async], but is :delete_all`. The earlier instruction could not have run.
  Then add the batched
  `EventCount.where(error_log_id: expired_ids_scope).in_batches(of: 1000).delete_all` in
  `RetentionCleanupJob` (`:60`), beside the occurrences/comments/cascade deletes it already does.
  Both are needed: the association covers `destroy`, the explicit delete covers the job's
  `delete_all` path, which does not fire callbacks. → REQ-F23, REQ-F24
- [ ] **T-F2.11** **Correct the false comment** at `db/migrate/20260919000001_create_event_counts.rb:28`
  ("RetentionCleanupJob prunes it") in the same commit as the code that makes it true, and add the
  test that asserts it. → REQ-F26, NFR-F10
- [ ] **T-F2.12** Document the still-active-group bucket policy and its interaction with
  `EventVolume`'s lifetime-count fallback term — pruning buckets while that term exists
  redistributes old events onto the group's first-seen day (`design.md` §F8). Decide and write it
  down; implementation of time-based pruning is deliberately follow-up. → REQ-F25
- [ ] **T-F2.13** PostgreSQL pass + MySQL pass (tz tables!) + `bin/check-schema-parity` + full
  suite + RuboCop. PR: "fix: count analytics events in their own window and prune count buckets
  (Refs #223)".

---

## P-F3 — Storm timing evidence + one provenance policy (`fix:`) — follows P-F2

Branch `fix/storm-buckets-and-provenance`. Files:
`services/storm_protection/count_buffer.rb`, `commands/flush_storm_counts.rb`,
`app/models/rails_error_dashboard/event_count.rb`, `commands/find_or_increment_error.rb`.

- [ ] **T-F3.1** Failing spec: one counted event at 23:59:59 and one at 00:00:01 through the real
  `CountBuffer`, flushed from its real snapshot → one yesterday, one today. → REQ-F12
  (reviewer's R3; currently two today, none yesterday)
- [ ] **T-F3.2** Key `CountBuffer` tallies by `(fingerprint, bucket)` at the **15-minute**
  granularity §F4 fixes (so +05:30 and +05:45 local midnights land on a bucket edge). Respect the existing
  read/write lock on handoff — **do not widen the write lock's scope** — and keep the memory cap
  and overflow accounting binding, degrading into the overflow counter rather than around it.
  → REQ-F12, REQ-F14 (`design.md` §F5)
- [ ] **T-F3.3** Carry per-bucket tallies through `snapshot!`, enqueue, JSON serialization, restore
  and retry; reconcile each bucket separately in `FlushStormCounts` (`:187`) instead of assigning
  the total to `last_seen_at`'s hour. → REQ-F13
  The snapshot is what travels to the worker — a bucket lost in serialization is a bucket lost.
- [ ] **T-F3.4** Failing specs for **every** transient escape path, not just the write:
  1. transient error at the bucket `create!` / `update_all` → batch not finalized, replay
     reconciles, today's count is right (reviewer's R4: currently lifetime 10 / today 0 /
     replay `already_applied`);
  2. transient error inside **`EventCount.table_exists?`** (`event_count.rb:82`) — it rescues
     `StandardError` and returns `false`, so `accumulate` returns early at `:50` **before any
     write is attempted** and the caller sees a clean miss. The same swallow at
     `event_volume.rb:211` silently drops the bucket term from *reads*, so a window can under-
     report with no error anywhere;
  3. replay after a transient abort;
  4. retries exhausted. → REQ-F15
- [ ] **T-F3.5** Let transient failures participate in the rollback-and-retry path, reusing
  `LogError::RETRYABLE_STORE_ERRORS`; keep degrade-and-continue for permanent failures. Have
  `FlushStormCounts` stop ignoring `accumulate`'s return value, and make the availability check
  distinguish "table genuinely absent" (permanent, degrade) from "cannot tell right now"
  (transient, retry). → REQ-F15
- [ ] **T-F3.5b** Permanent degradation must not be presented as exact. When a window is known to
  be missing bucket evidence, it is **incomplete** and must be reported as such rather than
  rendered as a precise number — preserving the lifetime count is not the same as having the
  temporal evidence. Reuse the existing `affected_users_incomplete?` idiom. → REQ-F15
- [ ] **T-F3.6** **Correct the rationalising comment** at `event_count.rb:72` so it names which
  failure class it describes. It currently reads as if all bucket loss is acceptable. → NFR-F10
- [ ] **T-F3.7** Failing spec: capture 1 records locals; capture 2 supplies fresh user/URL/params/
  agent/IP but **no** locals → the row is not labelled `full`. → REQ-F16
  (reviewer's R7; currently `fidelity: "full"` with capture 1's locals retained)
- [ ] **T-F3.8** Extend `retains_older_value?` (`find_or_increment_error.rb:169`) beyond
  `REFRESHED_REQUEST_IDENTITY` to every displayed payload — locals, instance variables,
  breadcrumbs, system health. Define the governing field list in **one** place so a future field
  cannot join the snapshot without joining the policy. → REQ-F16, REQ-F17
  **Trap (carried forward):** use `read_attribute`, never `public_send` — `:instance_variables`
  collides with `Object#instance_variables`.
- [ ] **T-F3.9** Confirm unchanged: `spec/commands/snapshot_provenance_spec.rb` (run scoped with
  `--example`, not by file path). The `partial` label from the previous sprint stays; this widens
  what can produce it.
- [ ] **T-F3.10** PostgreSQL pass + chaos + full suite + RuboCop. PR: "fix: bucket storm counts by
  hour and widen snapshot provenance (Refs #223)".

---

## P-F4 — Bounded execution + one normalization seam (`fix:`) — independent

Branch `fix/bounded-inspect-and-time-normalization`. Files: `services/variable_serializer.rb`,
`commands/log_error.rb`, `value_objects/error_context.rb`, `configuration.rb`, changelog.

### R9 first — it is data loss and can ship alone

- [ ] **T-F4.1** Failing spec: an ISO-8601 `String` `occurred_at` accepted by the sync path is
  accepted identically by the async path. → REQ-F20, REQ-F21
  (reviewer's R9; async currently returns `nil` and enqueues **0** jobs)
  Cover the documented input forms as a matrix: `Time`, `ActiveSupport::TimeWithZone`, ISO
  `String`, `nil` × sync/async (NFR-F8).
- [ ] **T-F4.2** Normalize `occurred_at` **once**, before the sync/async branch, and use the
  normalized value in both. The break is `log_error.rb:159` calling `.iso8601(6)` on the raw
  input before `ErrorContext`'s String parsing (`error_context.rb:74`) ever runs. → REQ-F20
- [ ] **T-F4.3** On normalization failure, degrade to a safe default and still capture — never
  return `nil` and enqueue nothing. Losing the error to save its timestamp is backwards
  (Safety Rule 1). → REQ-F22
- [ ] **T-F4.4** Keep the future-time clamp applied once, at the same seam, so sync and async
  share one policy (previous sprint REQ-23/REQ-24 stay satisfied).

### R8

- [ ] **T-F4.5** Failing spec: a Struct containing an object with a slow `#inspect`, under the
  **default** allowlist → the nested `#inspect` is never called and capture stays within budget.
  → REQ-F18 (reviewer's R8; currently ~35ms against a 5ms budget, `nested_inspect_called: true`)
- [ ] **T-F4.6** Serialize allowlisted structural types **member-wise** through the bounded
  serializer instead of calling the parent's `#inspect` (`variable_serializer.rb:187`). Each
  member then gets the same safe-summary default an unknown object gets. → REQ-F18, REQ-F19
  (`design.md` §F7 — `Timeout` is rejected: injecting an exception into arbitrary application
  code on the capture path violates Safety Rule 1.)
- [ ] **T-F4.7** `variable_serializer_spec.rb:385-390` asserts real Struct `inspect` output
  containing `"Alice"`. Change it **deliberately**, and relabel the post-hoc budget check as the
  output-selection backstop it is rather than leaving it named like an execution budget.
- [ ] **T-F4.8** Changelog: the Struct rendering change, on top of 0.14.0's existing
  `local_variable_inspect_*` note. → `design.md` §F7
- [ ] **T-F4.9** Full suite + RuboCop. PR: "fix: bound nested inspect and normalize capture time
  once (Refs #223)".

---

## Close-out

- [ ] **T-F5.1** Run `review-evidence/2026-09-19-followup/boundary_spec.rb` — all 10 probes pass.
- [ ] **T-F5.2** Run `review-evidence/2026-09-19-followup/prior_contracts_spec.rb` — the 11
  already-passing contracts stay passing, and the 3 interpreted ones (T4, T11, T12) behave as
  documented.
- [ ] **T-F5.3** Promote both probe sets into `spec/` as permanent regression tests, credited to
  the review. **This is the previous sprint's T6.2, which was left undone — which is why the same
  class of defect had to be found by an external reviewer twice.**
- [ ] **T-F5.4** Full matrix: `bin/with-ruby bin/pre-release-test all`, PostgreSQL, MySQL.
- [ ] **T-F5.5** Seed sweep (10 seeds) for order dependence.
- [ ] **T-F5.6** Changelog upgrade notes for 0.14.0 as a whole: the `event_counts` migration, the
  serializer defaults, the Struct rendering change, and the time-zone behaviour change.
- [ ] **T-F5.7** Re-audit the previous sprint's ticked tasks against the code, specifically T3.6.
  A ticked box that was not true is how R1 shipped.
- [ ] **T-F5.8** Comment on **#223**; do **not** close it.
- [ ] **T-F5.9** Write `.shipkit/specs/event-envelope/` (previous sprint T6.5) now that §F1 has
  superseded §D8.
- [ ] **T-F5.10** **Stop. Ask before merging release PR #237.** Still expected: **0.14.0** — these
  are all `fix:` commits and do not bump the minor again.

---

## Traceability

| REQ | Task(s) | PR |
|---|---|---|
| REQ-F1..F5 | T-F1.1–T-F1.5 | P-F1 |
| REQ-F6..F9 | T-F2.1–T-F2.5 | P-F2 |
| REQ-F10, F11 | T-F2.6–T-F2.8 | P-F2 |
| REQ-F23, F24, F26 | T-F2.9–T-F2.11 | P-F2 |
| REQ-F25 | T-F2.12 | P-F2 |
| REQ-F12..F14 | T-F3.1–T-F3.3 | P-F3 |
| REQ-F15 | T-F3.4–T-F3.6 | P-F3 |
| REQ-F16, F17 | T-F3.7–T-F3.9 | P-F3 |
| REQ-F20..F22 | T-F4.1–T-F4.4 | P-F4 |
| REQ-F18, F19 | T-F4.5–T-F4.8 | P-F4 |
