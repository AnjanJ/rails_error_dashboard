# Verification evidence — follow-up

How each finding was confirmed before any code was written.

## Method

The follow-up review (`review-evidence/2026-09-19-followup/REVIEW.md`) was treated as a set of
**claims**. Each was checked twice, independently of the reviewer's own run:

1. **Probe reproduction.** The reviewer's `boundary_spec.rb` was copied into `spec/` and run
   against `ae9b074` on SQLite. All 10 probes failed, matching the reviewer's SQLite and
   PostgreSQL 16.15 runs.
2. **Source confirmation.** Each finding was then confirmed by reading the cited code and
   re-deriving the mechanism, so that no finding rests on the probe alone. Where the review cited
   a line, the line was opened and checked.

No finding was accepted on the reviewer's word, and none was rejected without evidence.

## Result

**9 of 9 confirmed real. 0 refuted.** (10 probes; R5 has two — R5a deletion, R5b retention.)

| # | Finding | Probe | Source confirmation | Observed |
|---|---|---|---|---|
| R6 | Array locals bypass dotted filters | fail | `variable_serializer.rb:266-274` — Hash branch wraps under `var_name`, Array branch calls `filter_array_recursive` directly | `params` `[FILTERED]`, `locals` `SYNTHETIC_ARRAY_SECRET` |
| R1 | Analytics counts lifetime volume | fail | `analytics_stats.rb:64` `base_query` filters by first-seen; **0** `EventVolume` refs, **12** `sum(:occurrence_count)` | `overview_today: 1`, `analytics_total: 0`, user table shows the event |
| R2 | Day grouping ignores the app time zone | fail | `event_volume.rb:182` `DATE(col)` over UTC; lookups use `Date.current` in `Time.zone` | 00:15 IST → `today: 0`, event on the 19th |
| R3 | Storm batch across midnight | fail | `count_buffer.rb:32` stores one `count` + first/last only; `flush_storm_counts.rb:191` buckets at `last_seen_at` | `{"2026-09-19": 2}`, none on the 18th |
| R4 | Transient bucket failure loses evidence | fail | `event_count.rb:72` rescues `StandardError` → `false`; caller ignores the return | lifetime 10, `today: 0`, replay `already_applied` |
| R5a | Buckets survive group deletion | fail | `event_count.rb:23` `optional: true`, no `dependent:`, no FK | `groups: 0`, `orphan_buckets: 1` |
| R5b | Buckets survive retention | fail | `grep EventCount retention_cleanup_job.rb` → **no match** | `removed: 1`, `orphan_buckets: 1` |
| R7 | Mixed snapshot still labelled `full` | fail | `find_or_increment_error.rb:169` checks `REFRESHED_REQUEST_IDENTITY` only | `fidelity: "full"` with capture 1's locals |
| R8 | Struct allowlist bypasses the bound | fail | `variable_serializer.rb:187-198` — `inspect` runs, *then* elapsed is measured | `elapsed_ms: 35.2` vs `budget_ms: 5`, `nested_inspect_called: true` |
| R9 | ISO string drops async captures | fail | `log_error.rb:159` `.iso8601(6)` on raw input, before `error_context.rb:74` parses Strings | sync stores; async `null`, **0 enqueued** |

## Corrections and judgements

- **R6 was already rated High by the review** (`REVIEW.md:37`, "High — array-valued locals still
  bypass dotted sensitive-data filters"). An earlier draft of this file claimed a Medium→High
  correction; there was nothing to correct, and the claim is withdrawn. R6 is High, and the review
  said so first.
- **R2/R3/R4/R5 are regressions, not pre-existing defects.** `EventVolume`, `EventCount` and
  `create_event_counts` do not exist in `0.13.0` (verified: `git show 9664789:…/event_volume.rb`
  fails). They would be introduced *by* 0.14.0. This is what makes the release hold (`design.md`
  §F10) a correctness decision rather than a cautious one.
- **The review's three "interpreted" old assertions are correctly interpreted.** T4 (absent user →
  nil) is a policy the reviewer explicitly accepts; T11 is the disclosed shallow-capture
  limitation; T12 asserts the old `inspect` behaviour that REQ-27 deliberately changed. None is a
  defect, and the reviewer does not count them as such. R7 is a **different, narrower** claim than
  T4 and is real.
- **The meta-critique is accurate and is the organising principle of this spec.** "Hash but not
  Array, Overview but not Analytics, identity but not context payloads" describes three real
  half-migrations, each verified above at source.

## Self-inflicted causes worth recording

1. **T3.6 was ticked and not done.** It listed `analytics_stats.rb` call sites explicitly. Those
   call sites are untouched. The tick was a claim, not a verification — and nothing in the process
   checked it. T-F5.7 re-audits the previous sprint's boxes for the same reason.
2. **A migration comment shipped describing code that was never written**
   (`20260919000001_create_event_counts.rb:28`). NFR-F10 and REQ-F26 exist because of this.
3. **A rescue comment rationalised a gap** (`event_count.rb:72`). It is true of the lifetime count
   and false of the temporal evidence the same release promises, which made the swallow look
   considered.
4. **T6.2 — promoting the reviewer's probes into `spec/` — was left undone** at the end of the
   previous sprint, and it is still worth doing (now T-F5.3). But it would **not** have caught R1:
   the original `boundary_spec.rb` has no cross-page invariant — it calls `DashboardStats` in one
   example (`:51`) and `AnalyticsStats` in another (`:75`), never comparing them. An earlier draft
   of this file claimed otherwise; that claim is withdrawn. The test that catches R1 is new work
   (T-F2.1), which is precisely why REQ-F8 exists as a requirement rather than as a promotion
   task.

## Amendment evidence (second review round)

The follow-up review's seven amendments to this spec were each verified before being applied.
**7/7 confirmed, 0 rejected**, plus 2/2 evidence-record corrections. Four of them corrected
statements in this spec that were wrong on verifiable facts:

| # | Amendment | How verified | Result |
|---|---|---|---|
| 1 | `belongs_to` rejects `dependent: :delete_all` | built the association in a live class | `ArgumentError: The :dependent option must be one of [:destroy, :delete, :destroy_async], but is :delete_all` — **the original T-F2.10 could not have run** |
| 2 | Redaction tests must assert Rails parity | ran each shape through `ActiveSupport::ParameterFilter` | `profile.private_note` filters hash / array-of-hash / nested-array; does **not** filter `profile.list.private_note` or a scalar. The original matrix demanded **more** than Rails does |
| 2b | Proc filter arity | Proc recording its arguments | receives `(String, String, Hash)` = `(key, value, original_params)` — **not** a dotted path |
| 3 | Inventory is wider than Analytics | `grep -c 'sum(:occurrence_count)'` across `lib/` and `app/` | **21 sites / 5 files**, not 12 / 1. `dashboard_stats.rb` `top_errors` (`:172`) and `errors_by_severity_7d` (`:198-205`) still use first-seen + lifetime sum |
| 5 | ActiveModel `attributes` runs `cast` | custom type whose `cast` sleeps 20ms | `cast_called=true`, `elapsed_ms=24.3` — member-wise serialization **would still run application code** |
| 6 | `table_exists?` is an escape path | read `event_count.rb:82` and its callers | rescues `StandardError` → `false`; `accumulate` returns early at `:50` before any write, and `event_volume.rb:211` silently drops the bucket term from **reads** |
| 7 | Release fallback named no real tree | `git show main:…/event_volume.rb` | already on `main`; #237 builds from `main`, so the original fallback would have published the defects it claimed to avoid |

**Corrections to this document, withdrawn claims:**
- The "R6 Medium→High correction" was withdrawn: the review rated it High at `REVIEW.md:37`.
- The claim that T6.2 would have caught R1 was withdrawn: the original `boundary_spec.rb` calls
  `DashboardStats` (`:51`) and `AnalyticsStats` (`:75`) in separate examples and never compares
  them. There was no cross-page invariant to promote.

**Amendment 4 (bucket boundary) was accepted as a design gap rather than a factual error:**
"document the policy" deferred the central accuracy question. §F4 now *decides* — 15-minute
boundary-compatible buckets, so +05:30 and +05:45 local midnights fall on a bucket edge — with a
concrete acceptance case and an explicit approximate-labelling fallback.

**Amendment on §F1 framing accepted:** the claim that four findings prove a canonical capture
envelope became necessary was an overclaim. Analytics aggregation, producer bucketing and
snapshot provenance are separate responsibilities; only R9 concerns the envelope proper. §F1 now
presents three bounded seams as the chosen remedy, not as proof of necessity.

## Why the existing suite still missed all nine

Same structural pattern as last time — each gap is a test that asserts the implementation rather
than the contract:

| Finding | Why the suite was blind |
|---|---|
| R6 | Filtering specs cover hashes; no array-valued variable case |
| R1 | Each page is tested alone; **no test compares the two pages** |
| R2 | Every time-window spec runs in UTC |
| R3 | Storm specs flush a buffer built inside one hour |
| R4 | Bucket-failure specs assert the lifetime count, which is preserved |
| R5 | Deletion/retention specs predate the table and were not extended |
| R7 | Provenance specs vary request identity, never the context payloads |
| R8 | The Struct example holds a String, never a slow nested object |
| R9 | Async specs pass `Time` objects; the String form is sync-only |

REQ-F8's cross-page invariant and NFR-F8's dimension rule are the direct answer to this table.

## Sources

- Follow-up review, probes, logs, screenshots: `review-evidence/2026-09-19-followup/`
- Reviewed commit: `ae9b074b1ddbec7de6f774aa274918e67607c2da`
- Reviewer's environment: fresh archive, Ruby 4.0.6, Rails 8.1.3.1, PostgreSQL 16.15
- In-session reproduction: SQLite, Ruby 3.4.5, same commit, working tree clean

---

## Round 3 verification (2026-09-20, PR #247)

Four contract failures found by independent review of `e92c04a`, all reproduced at source before
any change was made. Two (F11, F13) were introduced by this sprint's own fixes.

| # | Finding | Red before | Green after | Where |
|---|---------|-----------|-------------|-------|
| F11 | Quarter-hour buckets stored as hourly | ✅ 7 examples | ✅ | `event_count_bucket_parity_spec.rb` |
| F12 | Overview breakdowns not migrated | ✅ 3 examples | ✅ | `dashboard_breakdowns_event_volume_spec.rb` |
| F13 | Permanent unavailability lost counts | ✅ 4 examples | ✅ | `storm_permanent_bucket_degradation_spec.rb` |
| F14 | Hourly map sized by events | ✅ 3 examples | ✅ | `event_volume_hourly_memory_spec.rb` |
| F15 | Green test asserting nothing | n/a (never asserted) | ✅ | `overview_analytics_agreement_spec.rb` |
| T-F5.3 | Probes promoted to regressions | n/a | ✅ 7 examples | `event_volume_invariants_spec.rb` |

### Results

- **Unit suite (SQLite):** 5280 examples, 0 failures, 1 pending
- **PostgreSQL:** 5270 / 0; the 24 new examples green in one combined run
- **CI:** 22 / 22, **including the MySQL row** — the `CONVERT_TZ` named-zone path is now verified
  by execution, closing the gap this spec previously listed as read-only
- **Chaos:** 1483 assertions across 5 apps, all passing
- **Seeds:** 22222 and 33333 clean on a rebuilt test DB
- **RuboCop:** 630 files, no offenses. **i18n-check:** no failures. **Schema parity:** 12 tables agree
- **Legacy data:** a bucket written on an hour boundary by a previous version still reads correctly
  (total 7, bucketed 7) — verified directly, since it is the backward-compatibility claim

### Three things that went wrong in MY work, recorded because they were nearly missed

1. **An order-dependent assertion I wrote.** `storm_permanent_bucket_degradation_spec.rb` asserted
   `ErrorLog.sum(:occurrence_count)` across the whole table; it passed alone and failed on
   PostgreSQL in a combined run (expected 15, got 10). A probe established that the PRODUCTION path
   was correct before anything was changed, which located the fault in the assertion. **A count is
   only meaningful against the group it belongs to.** Same class as last sprint's config leak.

2. **A corrupted test database that impersonated a catastrophic regression.** Running a scratch
   spec from inside `spec/` triggered a real-HTTP `LlmClient` example and a browser cascade that
   left the schema half-dropped. The suite then reported 2407, then 624, then 2190 failures on the
   same tree. The tell was that **CI was green on the same SHA** — trust that disagreement. Later
   repeated by running a PostgreSQL suite concurrently with a SQLite one against the same file.

3. **A stale probe that had never tested its contract.** `precedence_probe_spec.rb` called
   `ManualErrorReporter.report` with a positional exception where it takes `error_type:`/`message:`
   keywords. Confirmed stale by reproducing the identical failure on clean `main` in a worktree —
   not assumed. Fixed; it now genuinely asserts manual-value precedence.

### Still open

- `.shipkit/specs/event-envelope/` (T-F5.9) — tracked follow-up, does not block release
- Demo-app `GET /admin/seed` issue (T6.7) — separate repo
- **0.14.0 remains held** (#237), per design.md F10 and the user's standing instruction

---

## Round 4 verification (2026-09-20, PR #248)

Three implementation findings at `3f05b28`, all reproduced at source before any change, then
verified fixed by MY OWN probes rather than accepted on a subagent's report.

| # | Finding | Before | After |
|---|---------|--------|-------|
| F16a | SQLite hour wrong in New York | `{10=>1}` | `{6=>1}` |
| F16b | Fractional-offset collapse (Kolkata) | `{0=>2}` | `{5=>1, 6=>1}` |
| F16c | Daily path materialized per timestamp | 200 SQL rows | 1 |
| F17 | Flag reached no model, query or view | returned, discarded | persisted → queried → 11-locale banner |
| F18 | False claim about the probes | published in 3 places | corrected, incl. publicly on #223 |

Kathmandu (+05:45) returns `{6=>2}` for the same two instants, which is the CORRECT answer there —
evidence the fix is real zone math rather than a constant that happens to suit Kolkata.

### Results

- **CI: 22 / 22 SUCCESS on head SHA `8612111`**, including the dedicated PostgreSQL and MySQL rows
- **Unit suite: 5305 / 0** on a verified-idle machine
- **PostgreSQL: 69 / 0** across every changed path
- **RuboCop:** 597 files, no offenses. **i18n-check:** no failures. **Schema parity:** 12 tables agree
- **Migration:** verified idempotent on re-run

### The reviewer's fixture found a bug mine missed

F17's window predicate was wrong on the first attempt. I filtered `started_at >= beginning_of_day`;
their fixture (five events yesterday, five today) failed because a storm that began yesterday and is
still shedding today is the ordinary case. My fixture flushed everything today and passed.

**A fixture that is easier than production tests the easy case.** Their fixture is now a permanent
test, including an explicit replay assertion.

### Process failure worth recording: three invalid suite readings

Three times this round I read a mass-failure number that was DB contention, not a regression:
2460, then 1814, then 1558 failures. Causes: my own concurrent PostgreSQL + SQLite runs, and twice a
SUBAGENT's rspec process still live after it had reported.

The tell each time was `SQLite3::BusyException: database is locked` (or a corrupted schema load), and
the disagreement with green CI on the same SHA. **`pgrep -f '[r]spec'` must be empty before any
full-suite number is trusted** — a subagent that has already sent its report may still hold a live
process. Recorded in the project memory notes.

I reported one of these numbers to the user before diagnosing it. That was premature: the correct
order is verify the environment, then report.

---

## Round 5 verification (2026-09-20, PR #249)

Three gaps in the completeness-warning contract plus a test-clock defect, all reproduced at source
before any change. The SQLite time-zone and memory fixes from #248 were confirmed good by the
reviewer and are untouched here.

| # | Finding | Reproduction | After |
|---|---------|--------------|-------|
| F19a | No episode → no warning | `buckets_incomplete: true`, 0 episodes, dashboard complete | warning recorded and shown |
| F19b | Failed save unrecoverable | post-commit + self-rescuing; ledger says applied | in-transaction; batch stays replayable |
| F19c | Warning vanishes early | week 10, month 10, warning `false` | matched to the widest displayed window |
| F21 | Spec green only by daylight | **expected 15, got 3** at 00:30 | clock pinned; 2 sibling specs also pinned |

### Causation, not correlation

Reverting ONLY the implementation (keeping specs, model and schema) turns **6 of 9** recording
examples red; restoring makes all 9 pass. The three that pass either way are the negative cases,
which is what they should do.

### Results

- **Unit suite: 5316 / 0** on a machine verified idle first (`pgrep -f '[r]spec'` empty)
- **PostgreSQL: 5313 / 0**, likewise verified idle before the run
- **RuboCop:** 600 files, no offenses. **Schema parity:** 13 tables agree
- Migration is additive; model, query and job all no-op when the table is absent

### Caught while fixing, not reported

The new table had **no retention path**. A gap has no `error_log_id` to cascade from, so nothing
would ever have deleted it. Pruning added on `covered_until`, above the early return that fires when
no error logs are expired. **A new table is not finished until something deletes from it.**

### Process note: a number from a contended machine, again

I published a suite number (1870 failures) taken while a superseded run was still live. I caught it
myself this time — `live: 2` was printed at the head of the same output — but only because the
`pgrep` check had become part of the command rather than an intention. Every number in this round's
table was taken with that check confirmed empty first.

That is three rounds in which the environment, not the code, produced the alarming number. The
check is now in the project memory notes and in the command itself.

---

## Round 6 verification (2026-09-20, PR #250)

One conditional finding, reproduced exactly, plus a second case it created that I found and fixed
while addressing the first.

| # | Case | Before | After |
|---|------|--------|-------|
| F22 | `retention_days = 7`, active group, 10-day-old gap | `month=10 warning=false gaps=0` | `month=10 warning=true gaps=1` |
| F23 | Gap retained, all its events expired | `month=0 warning=true` | `month=0 warning=false` |

Causation: reverting ONLY the cleanup change turns 2 examples red; restoring makes all pass.

### Results

- **Unit suite: 5320 / 0** (`pgrep -f '[r]spec'` confirmed empty first)
- **PostgreSQL: 5317 / 0** (likewise)
- **RuboCop:** 600 files, no offenses

### Why the round-5 spec did not catch this

It asserted pruning with `retention_days = 90`, the default, where the retention cutoff is already
later than the reporting window — so the two clocks never disagreed. **A spec that exercises only
the default value cannot find a bug that lives in the configurable range.** The new examples cover
both sides of the boundary: retention shorter than the window (keep) and longer (prune).

### The second case, found not reported

Retaining the gap means it can outlive every event it covered, since expiring the group is what
removes those events. My own probe showed a banner qualifying a window with zero events. Guarded at
the read rather than by shortening retention again, which would have reintroduced F22 exactly.

Worth stating because it is easy to get backwards: **a warning that fires on an empty window is not
a harmless false positive — it trains people to ignore the banner**, which costs more than the
missing warning the retention fix was added to prevent.
