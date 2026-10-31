# Intake: overhead benchmark

> Intake taken on 2026-10-29.

## Request
Product goal 2, the research's blocker 5:
- **What:** a committed, reproducible benchmark of RED's overhead against its documented budgets,
  run in CI.
- **Replaces:** the README's single-machine figures (`README.md:128,161`). The README itself says
  "a reproducible benchmark script is not yet part of the gem".
- **Why it matters beyond 1.0:** decision 0002 makes it the 1.0 launch headline.

## Serves goal
"Prove the overhead budget: capture time and storm-check time, measured by a reproducible benchmark
that ships in the repo; target: capture < 5ms, storm check < 5µs" (`.shipkit/product.md`).

## Conflicts found
- **None with the non-goals.** The benchmark runs in RED's repo, not in host apps, and doesn't ship
  in the gem.
- **Decisions waiting on these numbers.** Several 0.17.0 decisions say they'd reverse "if the
  overhead benchmark shows X":
  - oversize params handling above 5 ms for a 1 MB body;
  - message filtering above 1 ms for a typical (under 500-character) message;
  - the reopen-collision fallback above 5 ms.

  They're in `.shipkit/specs/_shipped/capture-hardening-0-17/design.md` and
  `functional-fixes-0-17/design.md`. The benchmark measures those paths too, so the clauses can
  actually be checked.
- **CI noise.** The README's storm-check figure is 2.4 µs on Apple Silicon against a 5 µs budget. A
  shared CI runner may be about 2x slower, so the gate could flake. The user chose a real gate
  anyway: a flake there is real news about the budget claim.

## Answers (2026-10-29)
1. **Ships as its own PR, not tied to a gem release,** and lands first, for the launch story.
2. **CI reports and fails on breach.** It runs on pushes to main and on PRs that touch the capture
   path, writes a table to the job summary, and fails if a median exceeds its budget. The README
   quotes the CI numbers and names the runner hardware.

## Assumptions made
- **Budgets come from the host-app-safety table:**
  - total capture < 5 ms;
  - storm check < 5 µs (product goal);
  - breadcrumb callback < 0.01 ms;
  - health snapshot < 1 ms.
- **It measures the configuration the installer writes** (async logging on), plus sync logging,
  reported separately.
- **The script lives in the repo** (`bin/benchmark` or `benchmark/`), not in the gem's files.
- **Whether the CI job becomes a required check** is decided after it has run green for a while.
  It isn't required at first.

## Out of scope
- Benchmarking dashboard pages.
- Publishing a blog post (the adoption track).
