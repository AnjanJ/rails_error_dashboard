# Spec: Overhead benchmark

> Spec accepted at commit `6b1dfab` on spec/0-18-0 (2026-10-29).
> Status: shipped in 0.18.0 (#334, #336, #344). `bin/benchmark` is repo tooling and isn't in the gem.
> Paths: bin/benchmark,benchmark/,.github/workflows/,README.md,_features/,_getting_started/,_guides/,docs/,.claude/skills/host-app-safety/,.shipkit/product.md,spec/

## Purpose
RED promises it costs the host app less than its budgets. Today the only evidence is one
maintainer's laptop numbers in the README. This adds a benchmark anyone can run, and CI runs it and
fails when a budget is broken. Then "under 5 ms per capture, under 15 µs per storm check" is a claim
the repo proves on every change.

## User stories
- As a developer choosing an error tracker, I want overhead numbers I can reproduce myself, so that
  I can trust them.
- As the maintainer, I want CI to fail when a change pushes RED over a budget, so that a regression
  never reaches a release.

## Requirements (EARS)

### The script
- **REQ-1.** The repo shall contain a benchmark that runs with one command, using only the
  development bundle. It needs no network and no external service.
- **REQ-2.** The benchmark shall measure each of these against its budget:
  - total capture of one exception, through the middleware and the error subscriber, with the
    installer's default configuration (async logging): under 5 ms;
  - the storm check per error, with protection calm and with protection active: under 15 µs on the CI runner
    (5 µs until the first CI run on 2026-10-30, see design.md);
  - one breadcrumb callback: under 0.01 ms;
  - one health snapshot: under 1 ms.
- **REQ-3.** The benchmark shall also report, without a budget gate:
  - capture with sync logging;
  - message filtering of a message under 500 characters (a 0.17.0 decision reverses above 1 ms);
  - fitting a 1 MB request body into the params limit (reverses above 5 ms);
  - the reopen-collision fallback (reverses above 5 ms).
- **REQ-4.** For each measurement, the benchmark shall report the median and the 95th percentile
  over a fixed number of iterations, measured after a warm-up, in a table that shows the budget and
  PASS or FAIL.
- **REQ-5.** The benchmark shall run the dummy app in production mode: eager loading on, code
  reloading off.
- **REQ-6.** The output shall record the environment: Ruby, Rails, database adapter, CPU model and
  count, OS, and RED's commit.
- **REQ-7.** If any gated median exceeds its budget, then the benchmark shall exit non-zero.

### CI
- **REQ-8.** CI shall run the benchmark on every push to main, and on pull requests that change the
  capture path. That's the middleware, subscribers, commands, services and storm protection under
  `lib/rails_error_dashboard/`.
- **REQ-9.** The CI run shall write the results table to the job summary, and the job shall fail
  when the benchmark exits non-zero.

### What users read
- **REQ-10.** The README shall quote the CI numbers with the runner hardware and link the
  benchmark, and the sentence saying no benchmark ships shall go. The same change goes in the
  Jekyll copies of that text.

## Out of scope
- Benchmarking dashboard pages or background jobs.
- Making the CI job a required check: decided after it has run for a while.
