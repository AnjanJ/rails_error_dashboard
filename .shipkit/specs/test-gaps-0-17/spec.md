# Spec: test gaps for 0.17.0

> Spec accepted at commit `bf66194` on test/test-gaps-0-17.
> Status: open
> Paths: spec/commands/,spec/lib/rails_error_dashboard/,spec/ci/,test/pre_release/,bin/pre-release-test,.github/workflows/,lefthook.yml

## Purpose
Some of RED's tests and checks pass whatever the code does: a locking test inside the test
transaction, a "never raises" test whose input never raises, chaos checks that assert `true` on
both branches, a CI job that reports success after doing nothing, and a pre-commit hook that runs
no specs when two are staged. Other behaviour has no test at all: the exit and end-of-request
drains, the TracePoint features in a real app, and the second app's migration replay. This spec
makes each of them able to fail, and makes every PR check block a merge, plus a new
dependency and workflow audit.

## User stories
- As the maintainer, I want every check that passes to mean the behaviour works, so that a green
  run before a release is evidence and not decoration.
- As the maintainer, I want every PR check to block a merge, and vulnerable dependencies or unsafe
  workflow changes to fail CI, so that nothing reaches main or a release unchecked.

## Requirements (EARS)

### Capture under concurrency
- **REQ-1.** When several captures of the same error run at once, each on its own database
  connection, against one existing unresolved row, RED shall leave that one row with its
  occurrence count raised by the number of captures.

### Breadcrumbs
- **REQ-2.** If a breadcrumb handler raises, then RED shall let the instrumented block complete
  without an exception, for each of the seven events it subscribes to (SQL, controller action,
  cache read, cache write, job perform, mailer delivery, deprecation).

### Exit and end-of-work drains
- **REQ-3.** Where Rack::Attack tracking, missing-translation tracking, storm protection, crash
  capture and swallowed-exception detection are enabled, when the host process exits normally,
  RED shall run each of those five features' exit drains.
- **REQ-4.** Where Rack::Attack tracking, missing-translation tracking, storm protection and
  swallowed-exception detection are enabled, when a unit of work wrapped by the Rails executor
  completes, RED shall run each of those four features' end-of-work drains.

### HTTP chaos phase
- **REQ-5.** When a request error is captured in the HTTP chaos app, the chaos phase shall fail
  unless the captured row names the controller and the action that raised.
- **REQ-6.** When a request raises `Timeout::Error` in the HTTP chaos app, the chaos phase shall
  fail unless the error is captured with medium severity.
- **REQ-7.** While the HTTP chaos app runs Rails 7.1 or later, when a request raises an exception
  Rails maps in `rescue_responses` (ParameterMissing, RecordNotFound, RecordInvalid), the chaos
  phase shall fail unless the response carries the mapped status (400, 404, 422) and no error row
  is recorded for it.

### TracePoint features in a real app
- **REQ-8.** Where local-variable capture is enabled in the HTTP chaos app, when a request raises,
  the chaos phase shall fail unless the captured row holds the raising method's local variables.
- **REQ-9.** Where instance-variable capture is enabled in the HTTP chaos app, when a request
  raises, the chaos phase shall fail unless the captured row holds the controller's instance
  variables.
- **REQ-10.** Where swallowed-exception detection is enabled in the HTTP chaos app, when a request
  rescues an exception without re-raising it, the chaos phase shall fail unless that exception is
  recorded as swallowed.
- **REQ-11.** Where swallowed-exception detection is enabled in the HTTP chaos app, the chaos
  phase shall fail unless the swallowed-exceptions page answers 200 and lists the swallowed
  exception.

### Second app joining a shared error database
- **REQ-12.** When a second app installs RED against an error database a first app already uses,
  the multi-app chaos run shall replay every one of the second app's migrations against that
  database, and fail if a migration step exits non-zero.
- **REQ-13.** When the second app's migrations have replayed, the multi-app chaos run shall fail
  unless every error the first app recorded is still there with its environment unchanged.

### CI
- **REQ-14.** When a pull request neither comes from a release branch nor changes a file under
  `db/migrate/`, CI shall report the upgrade-path check as skipped, not as passed.
- **REQ-15.** When a pull request comes from a release branch or changes a file under
  `db/migrate/`, CI shall run the upgrade-path test.
- **REQ-16.** If the dependencies a pull request resolves include a gem version with a published
  advisory, checked against an advisory database fetched in the same run, then the `audit` check
  shall fail.
- **REQ-17.** If a workflow file has an actionlint error, then the `audit` check shall fail.
- **REQ-18.** If a workflow file has a zizmor finding of low severity or higher, then the `audit`
  check shall fail.
- **REQ-19.** Every workflow shall pin each action it uses to a full commit SHA.
- **REQ-20.** The "Protect main branch" ruleset shall require every check a pull request runs: the
  27 that run today, plus `audit` and `changes`. [untested: a repository setting, changed after
  the jobs have passed once on main; verified by reading the ruleset through the API]

### Pre-commit hook
- **REQ-21.** When more than one spec file is staged, the pre-commit spec hook shall run every
  staged spec and fail the commit if any of them fails.

## Out of scope
- **The storm cooldown's 60-second default:** already covered. `circuit_breaker_spec.rb` runs the
  real breaker on the default configuration with a fake clock (still open at 50 s, half-open at
  70 s), and `configuration_spec.rb` pins the default.
- Running specs for staged `lib/` files in the pre-commit hook: the hook runs staged specs only,
  by design.
- A real queue backend in chaos, and Brakeman (not in the repository; a separate decision).
- Documentation that counts the PR checks: updated separately once the new jobs exist.
