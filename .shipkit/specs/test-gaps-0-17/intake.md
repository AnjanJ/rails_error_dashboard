# Intake: test gaps for 0.17.0

> Intake taken on 2026-10-23.

## Request
Close the test gaps found before 0.17.0: checks that pass whatever the code does, hooks and
drains nothing verifies, features no chaos app turns on, and CI checks that don't block merges.
Add a required `audit` job (bundle-audit with a fresh advisory database, actionlint, zizmor) and
require every PR check in the "Protect main branch" ruleset.

## Serves goal
Ship 1.0 — metric: v1.0.0 published on RubyGems with config and public API frozen; target:
released; by: 2026-12-31. (0.17.0 is the stability release before the 1.0 release candidate.)

## Conflicts found
None. Searched `.shipkit/product.md` (non-goals), the open specs, `.shipkit/decisions/` (one
record, 0001, about other gems' files) and the decision blocks in open specs' `design.md`.
Related, not conflicting: `ci-least-privilege` REQ-13 pins `release.yml`'s actions to commit
SHAs; this work pins the other workflows the same way.

## Answers
1. Where does the "should the upgrade test run?" decision live, so the upgrade job can show as
   Skipped? — A new single-purpose `changes` job, and it is required too: unrequired, a failing
   `changes` job would skip the upgrade test and let a release PR merge untested. Required checks
   become the 27 that run today, plus `audit` and `changes`: 29.

## Assumptions made
- Already decided by the maintainer (2026-10-23): require every PR check, plus a required `audit`
  job running bundle-audit with a fresh advisory database, actionlint and zizmor.
- The `audit` job must pass on the day it becomes required, so the findings it reports today are
  fixed rather than suppressed: actions in `ci.yml`, `test.yml`, `pages.yml` and
  `smoke-test-demo.yml` are pinned to commit SHAs (Dependabot's `github-actions` updates already
  run weekly, `.github/dependabot.yml`), `pages.yml`'s write permissions move to the job that
  needs them, its checkout stops persisting credentials, and two shellcheck warnings in
  `test.yml` are quoted away. zizmor gates at low severity and above, on `.github/workflows/`.
  Its "help" findings are low severity too, so the deliberate ones (three ad-hoc `gem install`
  lines for tools, one `./.github/workflows/...` call) get an inline ignore with the reason.
  Only the informational Pages base-path note falls below the gate. (Corrected after the design
  review: the first draft said help notes would not fail the gate.)
- The storm cooldown's 60-second default needs no new test: `circuit_breaker_spec.rb` already runs
  the real breaker on the default configuration with a fake clock (open at 50 s, half-open at
  70 s), `circuit_breaker.rb:246` reads the setting, and `configuration_spec.rb` pins the default.
- On Rails 7.1 and later, Rails does not report exceptions listed in `rescue_responses`
  (ParameterMissing 400, RecordNotFound 404, RecordInvalid 422), observed in the HTTP chaos app on
  2026-10-23. The chaos phase asserts that behaviour instead of accepting either outcome.
- The ruleset is widened only after the `audit` and `changes` jobs exist on main and have passed
  once, so the required names match the check runs exactly.

## Out of scope
- Running specs for staged `lib/` files in the pre-commit hook (it runs staged specs only, by
  design).
- A real queue backend in chaos, and every other gap already closed.
- Brakeman (not in the repository; adding it is a separate decision).
