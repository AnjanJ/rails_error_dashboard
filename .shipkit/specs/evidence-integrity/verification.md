# Verification evidence

How each finding in `spec.md` was confirmed before any code was written.

## Method

The external review (`review-evidence/2026-09-19/REVIEW.md`) was treated as a set of **claims**,
not conclusions. Each of its 14 findings was independently checked by two agents that did not
share context:

1. a **verifier** that read the cited source itself, re-derived the mechanism, and where
   feasible built a minimal standalone reproduction;
2. an **adversarial challenger** that was told to *refute* the verifier — to look for a guard
   elsewhere, a misread path, a contract the gem never promised, or an existing spec proving the
   behavior intentional.

28 agents, 0 errors, ~1.27M tokens, 885 tool calls. Plus hand verification of F1, F2, F3, F5,
F6, F7, F11 and F13 in the main session.

## Result

**14 of 14 confirmed real** (F10 "partly-real": the limitation is real; the code is a defensible
trade-off, so the fix is documentation plus an optional bounded snapshot). **0 refuted.** Every
challenger upheld its verifier's verdict.

| # | Finding | Verdict | Fix risk | Reproduced |
|---|---|---|---|---|
| F1 | Storm reopen loses counts | real | low | yes — deterministic, SQLite |
| F2 | Partial batch marked applied | real | low | yes |
| F3 | Dotted `filter_parameters` ignored for locals | real | low | yes — standalone |
| F4a | Raw `params:` in job arguments | real | low | yes |
| F4b | Raw message on tracing span | real | low | yes |
| F5 | Window totals use first-seen day | real | **high** | yes — SQLite + PG |
| F6 | Per-user counts overcount | real | low | yes |
| F7 | Async event takes worker time/release | real | low | yes |
| F8 | Manual fields discarded; type renamed | real | low | yes |
| F9 | Mixed snapshot labelled fresh+full | real | medium | yes |
| F10 | Shallow raise-time snapshot | partly-real | low | yes |
| F11 | No breadcrumb buffer for jobs | real | low | yes |
| F12 | `inspect` cost unbounded | real | medium | yes |
| F13 | Phone-width detail page broken | real | low | yes — screenshot |

## What the adversarial pass added

This is the part that changed the plan. Four challengers caught hazards their verifier missed:

- **F1 — `update_all` would break live updates.** The "obvious" consistency fix (make the
  resolved branch match the atomic branch above it) bypasses ActiveRecord callbacks, and
  `ErrorLog` has `after_update_commit -> { ErrorBroadcaster.broadcast_update(self) }`
  (`error_log.rb:87`). It would have traded a counting bug for a silent broadcast bug.
  → `design.md` §D1.
- **F5 — the proposed interim mitigation was wrong.** The verifier offered a cheap
  `last_seen_at >= from OR occurred_at >= from` widening. The challenger showed it still sums
  the group's whole lifetime count into the window: `total_today = 2` when one event happened
  today — wrong in the *opposite* direction. Rejected. → `design.md` §D4.
- **F5 — a pure `COUNT(*)` over occurrences is a regression.**
  `spec/queries/analytics_event_counting_spec.rb:137-151` creates a group with
  `occurrence_count: 250` and **zero** occurrence rows and asserts 250. Storm-shed events write
  no occurrence row by design. This makes the bucketed rollup table a hard prerequisite, not an
  optional phase one. → REQ-14.
- **F11 — the fix needs a fix in another file.** Opening a buffer around `perform` makes the
  worker's own crumbs shadow the request's, because `log_error.rb:460-469` harvests the current
  thread *first* and only falls back to the serialized envelope when empty. → REQ-35.
- **F12 — safe-by-default breaks a real spec.** `variable_serializer_spec.rb:385-390` asserts
  Struct `inspect` output contains `"Alice"`. Struct and ActiveModel must be allowlisted, or
  that spec changed deliberately. → REQ-29.
- **F8 — honoring `occurred_at` naively corrupts grouping.** `find_unresolved` matches
  `where("occurred_at >= ?", 24.hours.ago)`, so a backdated report creates a permanently
  unmatchable group. → REQ-24, `design.md` §D6.

## Corrections to the review

The review was accurate and unusually fair (it labelled F10 a documented limitation itself).
Corrections worth carrying forward:

- **The version discrepancy is not a defect.** The review notes `version.rb` says 0.12.1 while
  the changelog prepares 0.13.0. It reviewed a stale checkout: `9664789` upstream is the
  release-please bump to 0.13.0. `git diff 0fd824c..9664789` touches only
  `.release-please-manifest.json`, `CHANGELOG.md` and `version.rb` — **no implementation file** —
  so all findings still apply at HEAD. No task.
- **Line numbers drift by a few lines** in most citations. The material ones: the `inspect` call
  is `variable_serializer.rb:180` (not `:159`, which is the circular-reference guard); the
  pathless filter is `filter_hash_recursive` ~`:281` (not `:199`); the storm decision lines are
  `:57` and `:70` (not `:55`); the breadcrumb SQL guard is `:119` (not `:122`).
- **F13 conflates two independent defects.** The hero squeeze (`flex-shrink: 0` on the action
  row at `show.html.erb:78`) and the 448px horizontal overflow have *different* causes. Fixing
  the hero alone leaves the page scrolling sideways. → T5.11 and T5.12 are separate tasks.
- **F8's "low severity" is imprecise.** `severity` is not a column; `ErrorLog#severity` is
  computed by `Services::SeverityClassifier` from `error_type` (`error_log.rb:182-185`). So the
  parameter must be *rejected*, not stored. → REQ-22, T4.8.
- **F4a understates the scope.** The leak is not only the direct `params:` input; every context
  key `ErrorContext#extract_params` folds into `request_params` is affected. → REQ-9.
- **F1 does not need PostgreSQL to reproduce.** The verifier reproduced it deterministically on
  SQLite by stubbing `update!` to interleave, with real reads, writes and transactions. The
  *fix* (`.lock`) is still only enforceable on PG/MySQL, so T1.1 keeps a PG pass — but the
  regression test can run everywhere.

## Why the existing suite missed all of this

5,009 examples and 141 browser tests passed while every one of these defects was live. The
pattern is consistent and worth internalizing — each gap is structural, not careless:

| Defect | Why the suite was blind |
|---|---|
| F1, F2 | Every storm spec is single-threaded and asserts post-conditions only (0 hits for `Thread`/`.lock`/`concurren`) |
| F3 | Serializer specs cover only flat names; no dotted-path case |
| F4a | The queue-redaction spec passes only the allowlisted `request_params:` form |
| F5 | Fixtures set each group's `occurred_at` directly to the intended day, so first-seen always equals event day |
| F7 | `async_logging_spec.rb` has 28 examples and asserts neither `occurred_at` nor release |
| F8 | The manual-reporter spec *passes* the fields but never asserts them |
| F11 | `breadcrumb_subscriber_spec.rb:8-11` opens a buffer in `before`, so the out-of-request case never runs |
| F13 | The layout QA spec never visits the error **detail** page at any width |

Every one is a test that asserts the implementation rather than the contract. That is the
argument for T6.2 — promoting the reviewer's probes into `spec/` — and for writing each task's
test from the *requirement*, not from the current code.

## Sources

- Review + probes + screenshots: `review-evidence/2026-09-19/`
- Per-agent results: `journal.jsonl` in the workflow transcript directory
  (`~/.claude/projects/-Users-anjan-code-RED/…/subagents/workflows/wf_b0148c64-f29/`)
- Full workflow output: `/private/tmp/claude-501/…/tasks/whmwjbkvq.output`
