# Design: Overhead on deploy shapes

## Approach
Two tools, one workflow. `bin/benchmark` stays the one-minute, in-process, gated check, and learns to run
against a real database and queue. A new `bin/benchmark-load` boots a real Rails app in containers, drives it at
a fixed rate with RED off and on, and writes a report. A hand-dispatched workflow runs both, held to a shape's
CPU and memory, on a free hosted runner. Nothing here touches the gem, a budget or the CI gate.

The stack that the 2026 Rails survey and a new Rails app point to is the default: Ruby 3.4, Rails 8.1, PostgreSQL,
Puma with one process and 3 threads, Solid Queue inside Puma, jemalloc and YJIT on. Sidekiq, MySQL, SQLite and Ruby
4.x are variants, because a run is free and one dispatch picks one stack.

## Decision: Shapes in CI, and no real servers   (→ REQ-16, REQ-19)

**Context.** The maintainer asked for checks on what people deploy to, and whether GitHub CI could do it. A job
can't choose its CPU: six x64 models have been seen on hosted runners, and none appears on AWS's lists. Hetzner and
DigitalOcean publish no models. Larger runners need an organization, and GitHub says self-hosted runners "should
almost never be used for public repositories". Docker can set CPU and memory limits on a runner. No way was found to
produce neighbours' CPU steal or hours-long burst credit behaviour there.

**Alternatives.**
1. CI only: shapes on free hosted runners.
2. CI, plus real Hetzner servers under a €20 cap, to check how far the shapes can be trusted.
3. CI, plus AWS, DigitalOcean and Hetzner, roughly $50 and two new accounts.

**Case for CI only.** It costs nothing, needs no account, leaves no token anywhere and can't leave a server
running. It can be re-run after any change. It adds a real stack, load and CPU and memory limits, which are what
`bin/benchmark` can't see today. It also matches the quarterly goal, which is worded for the CI runner.

**Case against CI only.** It never measures a real server, so "A host's servers look like the runner"
(`_shipped/overhead-benchmark/design.md`) stays untested. Neighbours' CPU steal is probably what matters most on
shared plans, and a runner can't produce it. Nobody will know how close a shape is to the machine it's named after,
so these figures can't be quoted for a provider or a plan.

**Decision.** The maintainer chose CI only on 2026-10-31.
**Falsifiability.** We would add real servers if an issue reports that RED adds more than twice as much on a real
server as on the matching shape, or before any page quotes a figure for a named provider or plan.
**Fired-if.** manual

## Decision: A separate `bin/benchmark-load`, not a mode of `bin/benchmark`   (→ REQ-8, REQ-9, REQ-10, REQ-11, REQ-12, REQ-13)

**Context.** `bin/benchmark` runs inside one Ruby process in about a minute, and CI gates on it. A load test needs
a real app, a database, a queue and a load generator as separate processes, and takes over an hour per shape.

**Alternatives.**
1. A separate entry point, `bin/benchmark-load`, with its own files under `benchmark/load/`.
2. A `--load` mode of `bin/benchmark`.
3. A throwaway script under the gitignored working notes.

**Case for a separate entry point.** The two share almost nothing but the idea. `bin/benchmark` boots `spec/dummy`
before it reads its arguments, and a load run must not. Keeping them apart means the gated check can't slow down or
break because of the load test.

**Case against a separate entry point.** Two tools to learn, and the report's environment block has to be shared or
it drifts. So it's shared: `bin/benchmark-load` reuses the environment code rather than copying it.

**Decision.** We chose option 1.
**Falsifiability.** We would fold it into `bin/benchmark` if CI ever gates on a load test row, since a gated number
should have one home.
**Fired-if.** manual

## Decision: k6 with a constant arrival rate   (→ REQ-9, REQ-10, REQ-15)

**Context.** REQ-9 needs an open model. In a closed model, "when the target system is stressed and starts to respond
more slowly, a closed model load test will wait", which k6's docs call coordinated omission. That would hide the very
slowdown being measured, and RED's cost only shows if the arrival rate holds.

**Alternatives.**
1. k6's `constant-arrival-rate` executor, in its official container image.
2. `wrk`, which is closed-loop.
3. `wrk2` or `vegeta`, both open-loop.
4. A hand-written Ruby generator.

**Case for k6.** Iterations "start independently of system response". It reports `dropped_iterations` when it can't
hold the rate, which is REQ-15's signal, and `http_req_duration` and `http_req_failed` directly. It runs from a
pinned image on x64 and arm64, and it writes JSON. A mix is a few lines of script.

**Case against k6.** It's one more dependency to pin, and JavaScript in a Ruby repo. It uses CPU that must not come
from the app's CPUs, so it gets its own. Its percentiles are computed by k6, not by us.

**Decision.** We chose option 1, pinned by image digest.
**Falsifiability.** We would switch to `vegeta` if k6's container goes over 80% of its CPU allowance in a window,
because at that point the generator's own delay is in the numbers.
**Fired-if.** manual

## Decision: RED off is the same image with the gem not required   (→ REQ-8, REQ-11)

**Context.** `_shipped/overhead-benchmark` measures "what RED adds, against the same app without RED". Doing that
under load needs the same app with and without RED, on the same CPUs, with nothing else different.

**Alternatives.**
1. One image. A `RED` environment variable decides `require:` in the Gemfile, and guards the initializer and the mount.
2. Two images, one built without the gem.
3. RED loaded, with `enable_middleware` and `enable_error_subscriber` off.

**Case for one image.** The lockfile, the code and every other gem are the same. Only the thing being measured
changes. Option 3 measures a disabled RED, which isn't the baseline a person deciding whether to install RED cares
about, and its engine still loads.

**Case against one image.** The Gemfile and the initializer carry a switch a real app wouldn't have, so REQ-8 holds
except for that line. RED's migrations stay applied with RED off, though nothing touches those tables then.

**Decision.** We chose option 1.
**Falsifiability.** We would build two images if the off run's process list or memory shows any RED class loaded,
because then "off" isn't off.
**Fired-if.** manual

## Decision: Windows alternate in ABBA order, and restart each time   (→ REQ-11, REQ-13)

**Context.** A runner's speed drifts, and a hosted runner is also shared. Comparing one long off run with one long on
run would count that drift as RED's cost.

**Alternatives.**
1. Pairs in ABBA order (off, on, on, off, and so on), restarting Puma for each window, with 60 s of warm-up thrown
   away and 120 s measured.
2. One long run per mode.
3. Two warm containers taking turns, with no restarts.

**Case for ABBA with restarts.** Adjacent windows see the same conditions, and the alternating order cancels any
steady drift. A restart gives both modes the same warm-up, so YJIT and the app's caches can't favour whichever ran
second. Option 3 leaves RED's background threads running in the idle container during the off window, on the same CPUs.

**Case against ABBA with restarts.** It's slow. Five pairs, three mixes and two windows at 3 minutes each is 90
minutes per shape, plus capacity search. The job limit is 6 hours, so one shape fits comfortably, but a run isn't quick.

**Decision.** We chose option 1.
**Falsifiability.** We would lengthen the windows if the spread between pairs is larger than the median of what RED
added, because then the noise is bigger than the signal.
**Fired-if.** manual

## Decision: Report the median of each pair's difference   (→ REQ-13, REQ-20)

**Context.** REQ-13 asks for what RED added. Pooling every on window and every off window and subtracting throws away
the pairing the windows were built for.

**Alternatives.**
1. For each pair, on minus off at p50, p95 and p99. The headline is the median of the pairs, and the spread is shown
   beside it.
2. Pool all windows per mode, then subtract.
3. A significance test per mix.

**Case for pair differences.** It uses the design above, and a single bad window can't move a median of five. The
spread shows the reader how far to trust it, without a test nobody will check the assumptions of. It's also how
`bin/benchmark` already reports: a median of round medians.

**Case against pair differences.** Five pairs is few, so p99 over 120 s is a rough figure at a low rate. A difference
can come out negative, which reads oddly. The report will show it as it is rather than clip it.

**Decision.** We chose option 1.
**Falsifiability.** We would add more pairs if the p99 difference changes sign between two runs of the same commit
on the same CPU model.
**Fired-if.** manual

## Decision: Shapes are Docker limits: `cpuset` for whole CPUs, a quota for fractions   (→ REQ-16)

**Context.** A standard runner has 4 vCPUs and 16 GB. A shape has to look smaller to the app, and the database and
load generator must not eat into it. `--cpus` alone sets a time quota but leaves the threads free to run on all four
CPUs, and Ruby and Puma still see four.

**Alternatives.**
1. `--cpuset-cpus` for the whole-CPU shapes, `--cpus` as well for a fractional shape, and `--memory` with swap off.
2. `--cpus` and `--memory` only.
3. systemd slices on the runner.
4. GitHub's `container:` job key.

**Case for cpuset plus quota.** The app sees the CPUs it would see on that machine, and the app and the rest can't
overlap: CPUs 0 and 1 for the app, and 2 and 3 for everything else. `cpu.stat` reports throttling for a quota, so the
throttled shape can prove it was throttled.

**Case against cpuset plus quota.** It needs two CPUs left over, so the largest shape is 2 CPUs. Whether CPUs 0 and 1
are two cores or one core's two threads isn't published and may vary, and that matters: `t3.medium` is one core with
two threads, and `t4g.medium` is two cores. So the report records the topology `lscpu` gives. A quota makes a fast CPU
run less often, not run slower.

**Decision.** We chose option 1.
**Falsifiability.** We would change it if the probe shows `Etc.nprocessors` inside the container differing from the
shape's whole CPUs, or the throttled shape showing no throttling in `cpu.stat`.
**Fired-if.** manual

## Decision: Network delay with `tc netem`, proved by a measured round trip   (→ REQ-17)

**Context.** A managed database is across a network, and `bin/benchmark` has only ever had a local file. The kernel
module is in the package for the runner's listed kernel, but no example of `netem` on a hosted runner was found, so
this is the least certain part of the design.

**Alternatives.**
1. `tc netem` in the database container.
2. A Toxiproxy container between the app and the database.
3. No delay: the containers' bridge network alone.

**Case for netem.** It adds delay in the kernel, with no extra process on the path. The other containers need no
change. The report states the round trip it measured, not the setting.

**Case against netem.** It may not work on a runner, and it needs `NET_ADMIN` on the database container. The 1 ms figure
has no source: no document found gives a typical app-to-database round trip, so it's a chosen value, and the report
says so.

**Decision.** We chose option 1, with Toxiproxy as the fallback.
**Falsifiability.** We would use Toxiproxy if the probe can't load `netem`, or if the measured round trip differs from
the setting by more than 20%.
**Fired-if.** manual

## Decision: A small workflow lands on main first   (→ REQ-18)

**Context.** Running a workflow by hand requires "the file must be on the default branch". So the workflow can't be
dispatched from a branch until a copy is on main. The riskiest assumptions here (cpuset, quota, `netem`, steal) have
only been read about, never tried on a runner.

**Alternatives.**
1. Land a dispatch-only workflow that runs a probe first, then dispatch it with `--ref` to run each branch's version.
2. Add a temporary `push` trigger on a branch.
3. Build everything, then find out at the end.

**Case for landing a probe first.** It tests the riskiest assumptions before anything is built on them, it keeps
REQ-18 true from the first commit, and every later task can prove itself on a real runner. It's small, and it can't
affect anything else in CI.

**Case against landing a probe first.** A not-yet-useful workflow sits on main for a while, and it needs a pull request
and your OK before any build task can start.

**Decision.** We chose option 1.
**Falsifiability.** We would use option 2 if GitHub stops running a branch's version of a workflow under `--ref`.
**Fired-if.** manual

## What the probe found

Run 41214442263 on main, `cd148d6`, 2026-10-31, on `ubuntu-24.04` and `ubuntu-24.04-arm`. Every check passed on both.

| Check | x64 (Xeon 8370C) | arm64 |
|---|---|---|
| `cpuset`: `Etc.nprocessors` | 2 | 2 |
| Memory | 4 GB, swap 0 | 4 GB, swap 0 |
| Quota of 0.4 CPU | 0.41 used, throttled 101 times | 0.41 used, throttled 101 times |
| `netem` at 1 ms | added 1.06 ms | added 1.07 ms |
| CPUs 0 and 1 | one core's two threads | two cores |
| CPU steal, all CPUs busy for 10 s | 0.00% | 0.00% |

So the design's assumptions hold, and Toxiproxy isn't needed. Two things to carry forward:

- **The two `medium` shapes aren't like-for-like.** On x64, `medium` is one core with two threads, as `t3.medium` is. On
  arm64 it's two cores, as `t4g.medium` is. Reports state the topology, and nothing should compare the two directly.
- **On x64 the app gets one core and everything else gets the other,** because CPUs 2 and 3 are a separate core. That's a
  cleaner split than the design assumed.

## Data / interface changes

**Environment variables for `bin/benchmark`** (REQ-1, REQ-2, REQ-3). `BENCHMARK_DATABASE_URL` and `BENCHMARK_QUEUE`.
`ci.yml`'s job sets neither, so the gated row doesn't change. With a database URL the schema comes from `db/migrate`,
not `spec/dummy/db/schema.rb`: that file is hand-kept for SQLite, and a host gets its PostgreSQL-only indexes from the
migrations. Building that schema drops every table first, which is why REQ-2 exists.

**Sidekiq** isn't in the Gemfile. It goes in the development group with `require: false`, as `solid_queue` already does,
so loading it changes nothing for other specs. Solid Queue's tables come from its own schema file, in the scratch
database only. Neither touches a host app.

**Shapes** (REQ-16). Each is named for its size, never for a product.

| Shape | App CPUs | CPU quota | Memory | The size of |
|---|---|---|---|---|
| `medium` | 2 | none | 4 GB | a 2 vCPU, 4 GB plan |
| `small` | 1 | none | 1 GB | a 1 vCPU, 1 GB plan |
| `medium-throttled` | 2 | 0.4 CPU | 4 GB | a burstable plan at a 20% per-vCPU baseline |
| `medium-arm` | 2 | none | 4 GB | a 2 vCPU, 4 GB ARM plan, on the free arm64 runner |

**Stacks.** `postgres-solid-queue` (the default), `postgres-sidekiq`, `mysql-solid-queue`, `sqlite-solid-queue`.
SQLite has no network delay. Ruby is `3.4` (the default) or `4.0`.

**Traffic mixes** (REQ-12). All are at the same rate. Healthy reads an order from the database and renders it. A failing
request raises 60 frames down, as `bin/benchmark` does. 1% failing is one such request in a hundred, and the storm is
every request. Storm protection's defaults are 30 full captures per fingerprint per minute, shedding at 10 errors a
second and opening at 50, so what a mix exercises depends on the rate. The report states the rate and the errors per
second, and a reader shouldn't compare mixes at different rates.

**Reports** (REQ-13, REQ-14, REQ-19, REQ-20). `bin/benchmark-load` writes JSON, and Markdown from it. The compare tool
reads the JSON. Each window records its mix, RED off or on, the three percentiles, requests, dropped iterations,
unexpected statuses, CPU steal, `cpu.stat` throttling and whether it's valid. The header carries the environment block,
the CPU topology, the measured database round trip and the line that says it's a shape.

**The workflow** (REQ-18). `.github/workflows/deploy-benchmark.yml`: `workflow_dispatch` only, with choice inputs for
shape, stack and Ruby, read through `env:` and never expanded in a script, as `spec/ci/workflows_spec.rb` requires. It has
`contents: read`, no secrets, pinned actions, and uploads the report as an artifact.
