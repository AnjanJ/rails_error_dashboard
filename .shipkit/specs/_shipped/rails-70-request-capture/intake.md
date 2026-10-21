# Intake: Rails 7.0 request capture

> Intake taken on 2026-10-19.

## Request
0.16.1: on Rails 7.0, RED records no unhandled request errors. ShowExceptions (and, in
development, DebugExceptions) renders the exception without reporting it, and RED's ErrorCatcher
sits outermost (`insert_before 0`, `lib/rails_error_dashboard/engine.rb:40-43`), so it never sees
it. Add a 7.0-only reporter that sees the exception before it is rendered, never double-reports on
7.1+, and skips `rescue_responses` (404s) the way 7.1 does. Prove it in a real 7.0 production app.
0.16.0 shipped this as a documented "Known limitation: Rails 7.0"; the user chose then to fix it
in a patch release.

## Serves goal
None. There is no `.shipkit/product.md`, so there is no goal list to choose from (not asked).

## Conflicts found
- No decision record covers where RED's middleware sits. Searched `.shipkit/decisions/` (only
  0001, about other gems' files) and every `.shipkit/specs/*/design.md` for "middleware",
  "ShowExceptions" and "7.0".
- **Precedent, not a conflict.** `.shipkit/specs/_shipped/capture-source/spec.md` REQ-2: an error RED
  records any way other than `ManualErrorReporter` is a server capture. The new reporter's
  captures are server captures.

## Answers
No questions asked: the user settled the approach on 2026-10-16 (document in 0.16.0, fix in a
patch release; dropping 7.0 was rejected), and the rest follows from parity with Rails 7.1.

## Assumptions made
- **Parity with 7.1 is the target.** 7.1 reports request errors from its Executor only when
  `!wrapper.rescue_response?` (actionpack 7.1.6 `show_exceptions.rb:37`, `executor.rb:16-19`).
  So on 7.0, RED skips exceptions listed in `ActionDispatch::ExceptionWrapper.rescue_responses`
  (RoutingError, RecordNotFound, RecordInvalid, …), and records nothing a controller's
  `rescue_from` handles (those never leave the controller: actionpack 7.0.8.7
  `action_controller/metal/rescue.rb:22-26`).
- **Development records too.** 7.1 reports development request errors through the same
  Executor path; 7.0's DebugExceptions renders without re-raising there
  (`debug_exceptions.rb:54-74`), so a fix limited to production would leave development silent.
- **Inert on 7.1+.** The reporter does nothing where `Rails.error.report` takes `source:`, the
  check ErrorCatcher already uses (`middleware/error_catcher.rb:73-77`). Its reports carry
  `context[:middleware]`, which the subscriber's dedup already honours (`error_reporter.rb:52-55`),
  because 7.0 sets no "already reported" marker on the exception.
- **Proof, permanent and one-off.** A request spec through the dummy app's real middleware stack
  with show_exceptions on; CI already runs every spec on Rails 7.0 (`.github/workflows/test.yml:21-22`).
  Plus a real Rails 7.0.8.7 production app via a new 7.0 row in
  `tasks/docs-audit/release_scenarios.sh` (with `json < 3`), with Rails 7.0.8.7 installed into a
  scratch gem path, not the shared Ruby.
- The 0.16.0 "Known limitation: Rails 7.0" text is replaced by a fixed-in-0.16.1 note wherever it
  appears.

## Revised later on 2026-10-19: Rails 7.0.10 already fixed it
While setting up a local 7.0 bundle, `~> 7.0.0` resolved to **Rails 7.0.10** (released
2025-10-28), not the 7.0.8.7 the research had read. 7.0.10 backported 7.1's reporting:
ShowExceptions sets `action_dispatch.report_exception` (actionpack 7.0.10
`show_exceptions.rb:44`) and the Executor reports it (`executor.rb:16-19`). A probe through the
dummy app with production settings (a scratch DB, `show_exceptions` on, detailed off) gave:

| Rails | 500 recorded | 404 recorded |
|---|---|---|
| 7.0.8.7 | 0 | 0 |
| 7.0.10 | 1 | 0 |
| 8.1.4 | 1 | (the dummy's Reloader also reports, see the design) |

So only 7.0.0–7.0.8.7 are affected, and CI's 7.0 rows (which install 7.0.10) could never
exercise a fix for them. The 0.16.0 known-limitation note was too broad: it said "Rails 7.0",
but 7.0.10 was never affected.

**Question asked:** Rails fixed this itself in 7.0.10. How should 0.16.1 handle apps on 7.0.0 to
7.0.8.7? **Answer: point to Rails 7.0.10.** No capture-path code. RED logs one warning at boot on
those versions, and the docs and the 0.16.1 notes correct the 0.16.0 note. Rejected: the
interceptor below 7.0.10 with a CI row pinned to 7.0.8.7, and raising RED's minimum to 7.0.10.

The assumptions above about the interceptor, development parity and request-spec proof are
superseded by this answer.

## Out of scope
- Moving ErrorCatcher on 7.1+, or changing what 7.1+ records.
- Running the chaos suite's Phase F on Rails 7.0 (it builds apps with the newest installed Rails,
  `bin/pre-release-test:113-141`).
- Dropping Rails 7.0 support.
