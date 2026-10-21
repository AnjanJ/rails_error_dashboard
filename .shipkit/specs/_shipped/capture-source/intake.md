# Intake: Capture source

> Intake taken on 2026-10-15.

## Request
0.16.0: store where each error came from (a server capture vs a `ManualErrorReporter` client
report), so that the source viewer, Copy for LLM and AI help never read files for client-supplied
backtraces. This follows up advisory GHSA-q7r3-w7p3-95h5, whose residual is that an injected frame
can still show any Ruby file or view template under `app/`. Needs a migration; ships in one minor
release with occurrence-context-history.

## Serves goal
None. There is no `.shipkit/product.md`; suggest `/shipkit:product` afterwards.

## Conflicts found
- **Deferred event envelope.** `.shipkit/specs/_shipped/evidence-integrity/design.md` §D8 deferred a
  canonical capture envelope, and a capture-source field would be part of it. The user decided
  to build this **standalone**.
- **Precedent, not a conflict.** `.shipkit/specs/_shipped/environment-awareness/design.md`, "environment
  is a match dimension, not a fingerprint input". Capture source follows it: it must not change
  how errors are grouped.
- No decision record contradicts this.

## Answers
1. Standalone or envelope first? **Standalone.**
2. Errors recorded before 0.16.0 have no marker. **Treat them as server-captured**: they keep View
   Source under the 0.15.0 file rules, and only new client reports are refused.
3. Which goal? **None** (no product.md).

## Assumptions made
- **Nothing is persisted today** (per the grandfather, after searching every migration,
  `spec/dummy/db/schema.rb` and `source` across app/ and lib/):
  - `ManualErrorReporter` sets `context[:source] = source || "manual"` (`manual_error_reporter.rb:98`).
    It reaches the row only as the `request_url` fallback (`error_context.rb:114`).
  - The Rails.error subscriber and the middleware pass `source` but persist nothing.
  - The one exception is crash import, which writes `source: "crash_capture"` inside the
    `environment_info` JSON (`crash_capture.rb:228-239`).
- **Untrusted means `ManualErrorReporter`.** Every other capture path records a backtrace Ruby
  produced in this process, or one RED wrote itself (crash import). Test errors and boot crashes
  count as server captures.
- **Granularity:** the marker must not split groups (the precedent above). A group could in
  principle hold both server and client occurrences, so whether the marker lives on the
  occurrence, the group, or both is a design question (Q2), not an intake one.
- **Readers** to gate: View Source (`_source_code.html.erb` via `read_source_code`), Copy for LLM
  and AI help (`MarkdownErrorFormatter#source_code_section`). Git blame shows commit metadata
  only, but goes through the same gate for consistency.

## Out of scope
- The canonical event-envelope refactor.
- Retroactively classifying old rows from heuristics such as `platform` or
  `request_url = "manual"`.
- Changing what `ManualErrorReporter` accepts, or validating client backtraces at capture.
