# Design: Overhead benchmark

## Approach
- **`bin/benchmark`**, a Ruby script in the repo (not in the gem's `files`), runs with
  `env -u RAILS_VERSION bin/with-ruby bundle exec bin/benchmark`. It sets up the app it measures in
  four steps:
  1. it requires `spec/dummy/config/application.rb`;
  2. before `initialize!` it sets eager loading on, reloading off and the log level to `warn`, and
     points both databases at a scratch SQLite file in `tmp/` (REQ-5);
  3. it sets Active Job to an adapter that serialises each job, as every real backend does, and
     then drops it, so the number is RED's cost and not a queue backend's;
  4. it loads the dummy schema into the scratch file.

  Added after T4's first CI run on 2026-10-30: it then turns YJIT on, and the environment block
  records it. New Rails apps run production with YJIT on, and it's worth about 1.5x on these rows
  on the M3 Max, so the numbers can't be left to whatever the shell exports. Every number before
  this was measured with YJIT on by accident, from an exported `RUBY_YJIT_ENABLE`.

  It never touches `spec/dummy/db/test.sqlite3`, so it can't collide with a running rspec.
- **Each measurement runs the same way:** a warm-up, then 5 rounds of N iterations, each timed with
  `Process.clock_gettime(CLOCK_MONOTONIC)`. The script reports the median and p95 of each round, and
  the median of the round medians. That last number is the one gated (REQ-4, REQ-7).
- **What's measured** (REQ-2, REQ-3):

| Measurement | How | Budget |
|---|---|---|
| Capture (async, the installer's default) | A Rack app that raises a pre-built exception, under `ErrorCatcher` and the `Rails.error` subscriber, minus the same app with RED's middleware and subscriber off | < 5 ms |
| Storm check, calm | `StormProtection::Gate.admit!` with the breaker closed (`Gate.reset!` before the scenario) | < 15 µs |
| Storm check, shedding | the same, with the breaker shedding and the open threshold out of reach | < 15 µs |
| Storm check, breaker open | the same, with the breaker driven open | < 15 µs |
| Breadcrumb callback | the body of RED's `sql.active_record` subscriber (build the event, then `handle_sql`), with a buffer on the thread | < 0.01 ms |
| Health snapshot | `SystemHealthSnapshot.capture` | < 1 ms |
| Capture (sync) | as the first row, with `async_logging = false` | reported |
| Message filtering | `SensitiveDataFilter.filter_message` on a 400-character message | reported (a 0.17 decision reverses above 1 ms) |
| Params fitting | `CaptureLimits.request_params` on a 1 MB JSON body | reported (reverses above 5 ms) |
| Reopen-collision fallback | `FindOrIncrementError` on a resolved row whose identity an unresolved row already holds | reported (reverses above 5 ms) |

  Added during T4's review on 2026-10-30: "protection active" (REQ-2) is more than one state, and
  T3 had timed only `:open`. Shedding makes the calm row's bucket decision and then counts as
  `:open` does, so it's the gate's slowest branch: 4.5 µs against 4.3 µs for open on the M3 Max.
  Each is a gated row. `:half_open` isn't timed: it swaps the bucket decision for a cheaper probe
  counter. A breaker only sheds once a bucket rolls, ten seconds in, so the scenario brings the roll
  forward instead of waiting.
- **Output:** a Markdown table: name, median, p95, budget, PASS/FAIL. Above it, the environment
  (REQ-6): Ruby, Rails, adapter, CPU model and count (from `/proc/cpuinfo` or `sysctl`), OS, RED
  commit. With `--summary <file>` the table is also appended to that file. CI passes
  `$GITHUB_STEP_SUMMARY`. Added during T4's review on 2026-10-30: `--smoke` runs every scenario for
  a few iterations and labels the output as meaningless, so the suite can run the real script end
  to end (no network, the summary file, the exit status) in seconds instead of a minute.
- **CI:** a `benchmark` job in `.github/workflows/ci.yml` (REQ-8, REQ-9):
  - one row: Ruby 3.4, Rails 8.1, SQLite;
  - `permissions: contents: read`, with actions pinned by SHA as `spec/ci/workflows_spec.rb`
    requires;
  - it runs on every push to main;
  - on a PR, it runs when the existing `changes` job reports a capture-path change. A new
    `capture` output matches `lib/rails_error_dashboard/(middleware|subscribers|commands|services)/`,
    `error_reporter.rb` or `bin/benchmark`. Added during T4 on 2026-10-30: it also matches
    `benchmark/` and `.github/workflows/ci.yml`. A change to a scenario or to this job can move the
    numbers as much as a change to the capture path, and the PR that changes the job has to be able
    to run it;
  - the row sets `RAILS_VERSION` to 8.1 rather than relying on the Gemfile's default, which moves
    when a new Rails series ships;
  - it isn't added to the ruleset's required checks yet (out of scope).
- **README** (REQ-10): the three sentences at `README.md:128`, `:145` and `:161`, plus
  `docs/FEATURES.md:572` and `docs/LLM_OBSERVABILITY.md:295`, quote the CI numbers and the runner,
  and link `bin/benchmark`. This lands only after the job has produced numbers on main.

## Decision: A hand-rolled timing loop, not benchmark-ips   (→ REQ-1, REQ-4)

**Context.** The budgets are per-operation times ("< 5 µs per storm check"). No benchmark gem is in
the Gemfile.

**Alternatives.**
1. A small loop over `CLOCK_MONOTONIC`, collecting per-iteration samples and computing median and
   p95.
2. `benchmark-ips` (a new development dependency).
3. Ruby's `Benchmark.realtime` over a batch.

**Case for 1.** The budgets are latencies, and percentiles are their natural measure. `benchmark-ips`
reports iterations per second with a deviation, not p95. There's no new dependency, and the code is
short enough to read in one sitting, which matters for a number meant to be trusted.

**Case against 1.** Timing one 2 µs call adds the clock's own cost, tens of nanoseconds, to every
sample. `benchmark-ips` amortises that over batches and has years of tuning; a hand-rolled loop can
get subtle things wrong, such as GC pauses landing in samples. The p95 includes those pauses, which
is honest, but it's noisier.

**Decision.** We chose option 1, with batching for the microsecond-scale rows (storm check,
breadcrumb: 100 calls per sample; health snapshot: 10). Added during T3 on 2026-10-30: macOS's
`CLOCK_MONOTONIC` ticks in whole microseconds, and every unbatched sample there was a whole
microsecond, so a 2 µs call timed alone was mostly rounding.
**Falsifiability.** We would batch the capture rows too if their round-to-round spread on the CI
runner exceeds 20% of the median.
**Fired-if.** manual

## Decision: Measure what RED adds, against the same app without RED   (→ REQ-2)

**Context.** "Total capture < 5 ms" is RED's budget, not the cost of raising and rescuing an
exception, which the host app pays with or without RED.

**Alternatives.**
1. Time the failing request with RED and without RED, in the same process, and report the
   difference.
2. Time `Commands::LogError.call` directly.
3. Time the full request with RED and report the total.

**Case for 1.** It's the number a user cares about: how much slower a failing request is because
RED is installed. It includes everything RED does on the request thread: the middleware, the
subscriber, the storm gate, the payload and the enqueue. And it leaves out what RED doesn't do.

**Case against 1.** A difference of two noisy numbers is noisier than either. Both sides share a
process, so caches warm differently, which is why each scenario gets its own warm-up and rounds.
Option 2 is steadier, but it skips the middleware and subscriber cost, so it would understate
RED's real cost.

**Decision.** We chose option 1.
**Falsifiability.** We would add option 2 as the gated number if the round-to-round spread of the
capture difference on CI exceeds 50% of its median.
**Fired-if.** manual

## Decision: Gate in CI on the median of round medians, on one pinned row   (→ REQ-7, REQ-8, REQ-9)

**Context.** The maintainer chose to fail CI on a breach (2026-10-29), knowing the README's storm
check is 2.4 µs on Apple Silicon against a 5 µs budget, and that a shared runner is slower. CI
already has a `changes` job (`ci.yml:135-167`) that decides whether `upgrade` runs. GitHub treats a
skipped job as passing, so a path-conditional job can later become required.

**Alternatives.**
1. Gate on the median of 5 round medians; report p95 without gating it.
2. Gate on the best round (the lowest median), as the timing spec in #329 does.
3. Gate on p95.

**Case for 1.** The median of medians resists a noisy round or two without hiding a real
regression, and it matches what a budget means: the typical cost, not a lucky one. One pinned row
keeps numbers comparable between runs.

**Case against 1.** CI may fail on runner noise rather than on RED, especially for the storm check,
where the headroom is about 2x. (Corrected during T4: after the budget decision below, the shedding
row leaves about 1.2x on the runner.) That's the cost the maintainer accepted. Option 2 rarely flakes, but it reports the best case.
Option 3 would flake constantly on GC pauses.

**Decision.** We chose option 1.
**Falsifiability.** We would change the gate if, in its first month, the job fails on main three or
more times with no change to the capture path between the failing run and the green run before it.
**Fired-if.** manual

## Decision: The storm check's budget is 15 µs on the CI runner, not 5 µs on a laptop   (→ REQ-2, REQ-7, REQ-9)

**Context.** The 5 µs budget had only ever been compared with an M3 Max: 3.3 µs calm, 4.5 µs
shedding and 4.3 µs open, all with YJIT on. The first CI runs (2026-10-30, three runs, a 4-vCPU AMD
EPYC 7763, YJIT on) measured 8.6 to 9.1 µs calm, 11.6 to 12.3 µs shedding and 11.4 to 11.8 µs open.
The runner is about 2.7x slower on every row, and YJIT isn't the difference. Identity is 2.65 µs of
the M3 Max's 4.5 µs, but a perfect memo of it still pays about 0.7 µs for its lookup and the two
reads that build its key, which gives about 7 µs on the runner. Reaching 5 µs there means 1.8 µs on
the M3 Max, and everything outside identity already costs about 1.4 µs.

**Alternatives.**
1. Gate at 15 µs on the runner.
2. Gate at 20 µs on the runner.
3. Memoize the identity, then gate at about 10 µs.
4. Keep 5 µs as a goal, and report the storm rows without gating them.

**Case for 1.** A host's servers look like the runner, not like an M3 Max, so this is the number
that means something, and anyone can read it in the job summary. 15 µs sits between today's 12.3 µs
and the estimated 17 to 24 µs of the code before `storm-gate-hot-path`, so it would have caught that
regression, which option 2 misses on the calm row. At 12 µs, a process handling 1,000 errors a
second spends about 1.2% of one core on the check.

**Case against 1.** It's three times the number the README has published, so the claim gets weaker.
The headroom is about 1.2x against a 6% spread between runs, and GitHub doesn't promise a CPU model,
so a slower host could fail the job with no change in RED. The 17 to 24 µs estimate is the M3 Max
figures scaled by 2.7, not a measurement. Option 3 gives a better number, but it reverses the gate's
"no shared mutable caches" design on the capture path and still doesn't reach 5 µs. Option 4 is the
quickest, but nothing would fail if the gate regressed.

**Decision.** The maintainer chose option 1 on 2026-10-30.
**Falsifiability.** We would raise the budget or move to a pinned runner if a storm row fails on
main on a CPU other than the EPYC 7763 with no change to the capture path. We would add the memo
(option 3) if a host reports the storm check as a measurable share of a storm.
**Fired-if.** manual
