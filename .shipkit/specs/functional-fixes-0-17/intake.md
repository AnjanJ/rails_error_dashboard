# Intake: functional fixes for 0.17.0

> Intake taken on 2026-10-22.

## Request
Fix the functional bugs found by the October code review, for 0.17.0:
1. With a separate error database, the boot-crash import may run before `ErrorLogsRecord` is
   connected to that database.
2. With `custom_fingerprint`, the async worker groups an error under a different hash from sync
   capture and the storm gate.
3. The `error_reporter.rb` header promises `Rails.error.handle` capture, which `#report` skips.
4. A lead: `SwallowedExceptionTracker` may lose counts between `dup` and `clear` when it flushes.
5. A lead: reopening an old resolved duplicate may violate the unique group index on PostgreSQL.
6. Reject Linear webhook deliveries whose timestamp is stale, as Linear's docs recommend.

Verify each item before fixing it. A lead that turns out false is closed with the reason, not fixed.

## Serves goal
"Ship 1.0 — metric: v1.0.0 published on RubyGems with config and public API frozen". 0.17.0 is the
release before 1.0.0.rc1 (`.shipkit/research/1-0-readiness.md`, line 109), and 1.0 is a stability
release (line 9).

## Conflicts found
- **Non-goals** (`.shipkit/product.md`, lines 18–24): none. No fix adds request-path work, and the
  ones on the capture path (the fingerprint and the reopen) must stay inside the capture budget.
  The swallowed-exception tracker runs from a TracePoint, so a fix there must not add a lock to the
  per-raise path.
- **Open specs:** none cover these. `async-job-reconstruct` also edits `commands/log_error.rb`, but
  it is merged (0.16.2) and changes how the worker rebuilds the exception, not the group hash.
  `ci-least-privilege` and `live-updates-client` are merged too; their status lines still say open.
- **Decisions:** `.shipkit/decisions/0001` (never write other gems' files) is not touched.

## Answers
No questions at intake. The user's direction (2026-10-22) and the October review notes answer the
rest. The one open choice, which hash is canonical for a custom fingerprint, the user asked to be
asked when the design reaches it.

## Assumptions made
- **Verify first.** The crash-import order is proven at runtime in a separate-database app before
  it is fixed. Both leads are proven by a failing test or a probe; a lead that does not reproduce is
  closed with its reason and gets no code.
- **The reopen fix**, if the lead is real, rescues the unique violation and falls back to the
  conflicting row, as `#create_new_or_retry` already does. A backfill migration is the heavier
  alternative, weighed in the design.
- **The Linear check** uses the field name and the tolerance from Linear's current webhook docs,
  read before writing the requirement.
- **One PR,** one `fix:` commit per item, as #270 did. The repository squashes with
  `COMMIT_MESSAGES`, so each commit becomes its own CHANGELOG line.
- **Public wording:** fix descriptions only. The PR, commits and these files carry no review IDs.

## Out of scope
- The capture-hardening, live-updates and host-hygiene work planned for 0.17.0 (separate specs).
- Changes to the GitHub, GitLab and Codeberg webhook handlers.
- Regrouping existing error groups beyond what the fingerprint fix decides.
