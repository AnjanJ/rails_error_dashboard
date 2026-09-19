# Spec: Evidence integrity — follow-up

> Spec written at commit `ae9b074` on main, gem v0.13.0 published / **0.14.0 pending and held**.
> Source: external follow-up review at `review-evidence/2026-09-19-followup/REVIEW.md`,
> assessed against `ae9b074`. All 10 probes independently reproduced in-session on SQLite;
> the reviewer reproduced the same 10 on PostgreSQL 16.15 with a migration-built schema.
> **9 findings, 9 confirmed real, 0 refuted.** Evidence: `verification.md`.

## Purpose

The previous sprint (`.shipkit/specs/evidence-integrity/`) fixed 14 findings and shipped five
PRs. The follow-up review confirms the sound ones — storm conservation, queue/tracing redaction,
per-user attribution, async time/release, manual fields, job breadcrumbs, mobile layout — and
then names the pattern in what remains:

> The weaker fixes patch one shape or one reader: Hash but not Array, Overview but not Analytics,
> identity but not context payloads.

That critique is correct and is the organising principle of this spec. Each requirement below is
written against a **contract**, not against the instance that was reproduced. Where the previous
sprint has a task that was ticked but only partly done, this spec says so explicitly rather than
re-deriving it.

### What this sprint admits

Three self-inflicted problems, recorded because the point of a spec is to be honest about cause:

1. **T3.6 was marked complete and was not.** It said "route every window figure through
   `EventVolume`", listing `analytics_stats.rb` call sites by line number. `analytics_stats.rb`
   has **zero** `EventVolume` references and **12** surviving `sum(:occurrence_count)` sites.
   Nor was `dashboard_stats.rb` fully cut over — `top_errors` and `errors_by_severity_7d` still
   use first-seen + lifetime sums — and three further readers were never in scope at all.
   **21 sites across 5 files.** R1 is the direct consequence.
2. **A migration comment claims behaviour that does not exist.** `20260919000001_create_event_counts.rb:28`
   says "RetentionCleanupJob prunes it"; `grep EventCount app/jobs/.../retention_cleanup_job.rb`
   returns nothing. That is a false claim in a durable artifact (R5).
3. **A rationalising comment hid a real gap.** `event_count.rb:72` reads "Losing a bucket degrades
   a time window, it does not lose the count." True of the lifetime count, false of the temporal
   evidence 0.14.0 newly promises. The comment made the swallow look considered (R4).

### Release status — this spec's first output

`EventVolume`, `EventCount` and the `create_event_counts` migration are **new in 0.14.0**.
Therefore R2, R3, R4, R5 and R9 are **not pre-existing bugs**; they are defects this unreleased
version would introduce, and R5 adds a table that grows without any cleanup path.

R6, R7 and (partly) R8 **are** pre-existing and affect published 0.13.0 — see the per-finding
table in `design.md` §F10. "0.13.0 is unaffected by every new finding" was too broad and is
withdrawn.

**Release PR #237 is held.** #237 builds from `main`, which already contains `EventVolume` and
`EventCount`, so no subset of fixes merged into `main` can produce a smaller release. The defined
fallback is a **0.13.1 branch from the published baseline** carrying only R6 and R9, verified
before publication. See `design.md` §F10.

## Scope

**In scope.** The 9 confirmed findings, grouped into 4 PRs by contract (`design.md` §F9).

**Out of scope, deliberately.**
- The full canonical event-envelope refactor. R9 forces *one* normalisation seam (REQ-F20);
  the rest remains future work in `.shipkit/specs/event-envelope/`. `design.md` §F1 takes **three
  bounded seams** as the chosen remedy and explicitly does **not** claim these findings prove the
  full refactor became necessary — Analytics aggregation, producer bucketing and snapshot
  provenance are separate responsibilities.
- The demo app's `GET /admin/seed` route. Re-confirmed present at
  `rails_error_dashboard_demo_app/config/routes.rb:20`, source-only, separate repository.
  Still tracked as T6.7 of the previous sprint.
- T11 / shallow nested capture. The reviewer accepts disclosure as a reasonable resolution.
- T4's stricter remedy (absent user becomes nil). The reviewer explicitly accepts the
  documented-exemplar policy and does **not** count it as a defect. R7 is a different and
  narrower claim — see REQ-F16.

## User stories

- As a security-conscious integrator, I want my `filter_parameters` honoured whatever container
  my variable happens to be, so that a list of records is no less protected than one record.
- As an on-call engineer, I want Overview and Analytics to agree, so that I do not have to guess
  which page is lying.
- As an operator outside UTC, I want "today" to mean my today.
- As an operator reading a storm's timeline, I want events attributed to the interval they
  happened in, even when one buffered batch spans my local midnight — including at a
  non-whole-hour offset such as +05:30.
- As an operator, I want a durable table to have a cleanup path, and I want the comment that says
  so to be true.
- As a developer, I want the same input accepted identically whether capture is sync or async.

## Requirements (EARS)

### A. One redaction policy, every container shape (P-F1)

- **REQ-F1.** Where a captured variable's value is filtered, the system shall apply the filter
  with the variable's own name as the top-level key **regardless of the value's container type**
  — Hash, Array, nested combinations, or scalar. *(R6)*
- **REQ-F2.** For any configured filter pattern, the redaction applied to a captured variable
  shall be **identical to what `ActiveSupport::ParameterFilter` applies to the same structure in
  request params** — no more and no less. Parity is the contract: a pattern naming
  `profile.private_note` shall redact it under a Hash, an Array of Hashes and nested Arrays, and
  shall **not** redact `profile.list.private_note` or a scalar `profile`, because Rails does not
  (verified). Over-redaction is a defect on the same footing as under-redaction.
- **REQ-F3.** The path-preserving filter shall apply to instance variables under their `@`-stripped
  name on the same terms as local variables.
- **REQ-F4.** Filtering shall be applied to the complete variable value **before** display
  metadata (`type`, `truncated`) is attached, so no code path can observe an unfiltered value.
- **REQ-F5.** A regression test shall assert the invariant across the shape matrix
  (hash / array / array-of-hash / hash-of-array / deep nesting / scalar) for String, Symbol,
  Regexp and Proc filter patterns — expected results taken from `ParameterFilter` itself, not
  from intuition, and not one example per shape discovered in the field. Proc patterns shall
  continue to receive `(key, value)` / `(key, value, original_params)`, never a synthesized
  dotted path.

### B. One event-volume model (P-F2)

- **REQ-F6.** Every event-volume figure **in the gem** shall count events whose **own** timestamp
  falls in the window, via one primitive. The scope is not Analytics alone: an inventory of all
  21 `sum(:occurrence_count)` sites across `analytics_stats.rb`, `dashboard_stats.rb`
  (`top_errors`, `errors_by_severity_7d`), `platform_comparison.rb`, `user_impact_summary.rb` and
  `digest_builder.rb` shall classify each figure as EVENT or GROUP, and every EVENT figure shall
  route through that primitive. *(R1)*
- **REQ-F7.** No event-volume figure shall select groups by first-seen `occurred_at` and then sum
  a lifetime `occurrence_count`. Group-scoped metrics (`total_groups`, `unresolved`, `resolved`)
  shall remain group-scoped and keep selecting by first-seen, which is correct for them.
- **REQ-F8.** Overview and Analytics shall report the same total for the same window and filter
  set; an executable cross-page invariant shall assert this. *(This is the test that would have
  caught R1: each page was internally consistent and they disagreed with each other.)*
- **REQ-F9.** Analytics' own sub-totals shall be consistent with its headline total. For an
  **exhaustive** breakdown (every event falls in exactly one bucket) the sum shall **equal** the
  headline total; `≤` shall be used only for breakdowns that are genuinely partial (top-N, or a
  nullable dimension), and each breakdown shall be classified as one or the other. A window whose
  user table shows N events shall not report a total of zero.
- **REQ-F10.** Day and interval bucket keys shall be computed in the **application time zone**
  (`Time.zone`), and window boundaries shall be derived from the same zone, so that SQL grouping
  and Ruby lookup cannot disagree. *(R2)*
- **REQ-F11.** The system shall behave correctly for positive and negative UTC offsets and for
  non-whole-hour offsets (e.g. `Asia/Kolkata` +05:30), and shall have an explicit, documented
  policy where a local day boundary splits a stored bucket. `design.md` §F4 **decides** this
  rather than deferring it: buckets are **15 minutes**, so every supported offset (including
  +05:30 and +05:45) falls on a bucket edge and daily totals stay exact; the fallback, if that
  proves too costly, is hourly buckets with split days labelled approximate — never shown as
  exact.

### C. Storm timing evidence is produced and preserved (P-F3)

- **REQ-F12.** `CountBuffer` shall tally counted-not-stored events **per 15-minute bucket** (the
  §F4 granularity) as well as
  per fingerprint, so that timing is not discarded by the producer. *(R3)*
- **REQ-F13.** Per-bucket tallies shall survive `snapshot!`, enqueue, serialization, restore and
  retry, and `FlushStormCounts` shall reconcile each bucket separately rather than assigning one
  total to the hour of `last_seen_at`.
- **REQ-F14.** The buffer's existing memory cap, overflow accounting and read/write lock
  discipline shall be preserved; bucketing shall not widen the write lock's scope.
- **REQ-F15.** If a bucket write fails with a **transient** store error, then the system shall not
  finalize the batch ledger as applied; the failure shall participate in the same
  rollback-and-retry path as a transient count failure. *(R4)* Permanent failures keep today's
  degrade-and-continue behaviour, and the comment at `event_count.rb:72` shall be corrected to
  state which of the two it is describing.

### D. One provenance policy over every displayed payload (P-F3)

- **REQ-F16.** The fidelity label shall reflect whether **every displayed payload** the row now
  shows came from the current occurrence — including local variables, instance variables,
  breadcrumbs and system health — not request-identity fields alone. A row that retains an
  earlier occurrence's locals while advancing the capture timestamp shall not be labelled
  `full`. *(R7)*
- **REQ-F17.** The set of fields governing provenance shall be defined in exactly one place, so a
  future field cannot be added to the snapshot without being added to the policy.

### E. Bounded work means bounded execution (P-F4)

- **REQ-F18.** The serializer's **default path shall never invoke arbitrary `#inspect`**,
  directly or transitively through an allowlisted container. A Struct whose member has a slow
  `#inspect` shall not reach that member's implementation by default. *(R8)*
  Where a host app explicitly opts a type in, the documentation shall state that it accepts
  unbounded execution for that type: interrupting arbitrary Ruby mid-call requires the `Timeout`
  mechanism rejected in `design.md` §F7, so no unconditional execution bound can honestly be
  promised for opted-in types.
- **REQ-F19.** Where a **Struct** is serialized, its members shall be serialized through the
  bounded serializer rather than via the parent's `#inspect`, under explicit member-count and
  nesting-depth limits so that recursion cannot reintroduce unbounded work.
  **ActiveModel shall receive a safe summary instead**: reading `ActiveModel::Attributes#attributes`
  executes a custom type's `cast` (verified — a 20ms `cast` took 24.3ms), so member-wise traversal
  would run application code by another door. See `design.md` §F7.

### F. One normalization seam for capture input (P-F4)

- **REQ-F20.** Caller-supplied `occurred_at` shall be normalized and validated **once**, before
  the sync/async transport decision, and the normalized value shall be used by both paths. *(R9)*
- **REQ-F21.** Any input accepted by the synchronous path shall be accepted identically by the
  asynchronous path; a capture shall never be silently dropped because of the transport chosen.
  An executable sync/async parity test shall assert this for the documented input forms
  (`Time`, `ActiveSupport::TimeWithZone`, ISO-8601 `String`, `nil`).
- **REQ-F22.** If input normalization fails, then the system shall degrade to a capture with a
  safe default rather than return `nil` and enqueue nothing (Safety Rule 1: never lose the error).

### G. Durable tables have a cleanup path (P-F2)

- **REQ-F23.** When an `ErrorLog` is deleted, its `EventCount` rows shall be deleted. *(R5a)*
- **REQ-F24.** `RetentionCleanupJob` shall delete `EventCount` rows for expired groups, in
  batches, alongside the dependents it already handles. *(R5b)*
- **REQ-F25.** The retention policy for buckets belonging to **still-active** groups shall be
  decided and documented, including its interaction with the lifetime-count fallback term in
  `EventVolume` — pruning buckets while that fallback remains can silently redistribute old
  events onto a group's first-seen date (`design.md` §F8).
- **REQ-F26.** Every claim a migration comment makes about cleanup shall be backed by code, and a
  test shall assert it. *(The specific defect: the comment shipped, the code did not.)*

## Non-functional constraints

Carried forward from the previous sprint; NFR-1..NFR-7 still bind. Additions:

- **NFR-F8.** No requirement here may be satisfied for the reproduced instance alone. Each fix
  lands at the contract, with a test over the **dimension** (container shape, page, transport,
  time zone, payload field) rather than the single case in the review.
- **NFR-F9.** REQ-F18 must **reduce** worst-case capture cost. A bounded-execution mechanism that
  adds a thread or a timeout to the common path is not acceptable on the request path
  (`design.md` §F7 records the mechanism chosen and rejected).
- **NFR-F10.** No comment may describe behaviour that does not exist. Where this sprint finds one,
  it is corrected in the same commit as the code it misdescribes.

## Acceptance

Done means: every REQ above has a task in `tasks.md` and a test that fails before and passes
after; all 10 follow-up probes in `review-evidence/2026-09-19-followup/boundary_spec.rb` flip to
passing; the 11 original contracts that already pass in `prior_contracts_spec.rb` stay passing;
the full suite, browser suite, chaos suite, RuboCop, `bin/i18n-check` and
`bin/check-schema-parity` stay green on SQLite **and** PostgreSQL; and a seed sweep shows no new
order dependence.

Explicitly **not** done by this spec: the full event-envelope refactor. REQ-F20 takes the one
seam R9 forces; `.shipkit/specs/event-envelope/` remains to be written (previous sprint T6.5).
