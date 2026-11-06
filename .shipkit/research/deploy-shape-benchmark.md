# What RED adds on deploy shapes: every figure

> Researched 2026-10-31 to 2026-11-05 on GitHub's hosted runners, for the spec
> `deploy-shape-benchmark` (REQ-21). Written 2026-11-06 at `4146259`. Each figure below names its shape, its CPU,
> the RED commit it ran and the date of its run. Each run's reports stay on GitHub under its run ID while its
> artifacts last; the two runs from 2026-10-31 have no artifacts now, so their figures come from their logs.

## How to read these figures

- **A shape is Docker limits on a runner, not a plan's machine.** `medium` is 2 CPUs and 4 GB, `small` 1 CPU and
  1 GB, `medium-throttled` 2 CPUs at 0.4 of a CPU's time and 4 GB, and `medium-arm` is `medium` on the arm64
  runner. Swap is off. The app gets CPUs 0 and 1 (`small`: CPU 0). The database, k6 and the rows' PostgreSQL get
  CPUs 2 and 3.
- **Figures compare only on the same CPU, commit and rate.** The runner picks the CPU. `medium` drew an EPYC 9V45
  on three runs and an EPYC 7763 on two, and held 340 to 380 requests a second on the first and 220 on the
  second.
- **The rows** are `bin/benchmark` on PostgreSQL, run inside a container held to the shape: the median of 5 round
  medians, and that side's p95. A row's budget is judged on its median.
- **The load test** is a new Rails 8.1 app with RED added by its installer (async capture, Solid Queue in Puma),
  sent a fixed arrival rate by k6. That rate is half the most the app held with RED off. Each mix has five pairs of
  RED off and on, in ABBA order, each window a restart, 60 s of warm-up thrown away and 120 s measured. "RED
  added" is the median of the five pairs' RED on minus RED off; a negative one is a pair whose RED-on window was
  faster. The mixes: `healthy` sends no failing request, `failing` one in a hundred, `storm` every request.
- **The network delay** is `tc netem` adding 1 ms to the database's replies, from 2026-11-05 on. 1 ms is a chosen
  value: no source gives a typical app-to-database round trip.

## What a shape can't show

- **A real server.** No figure here was measured on a provider's machine, so none can be quoted for a provider or a
  plan. The design's own condition for adding real servers stands: an issue reporting RED adding more than twice
  as much on a real server as on the matching shape, or a page about to quote a figure for a named plan.
- **Neighbours.** CPU time stolen read 0.00% in all 270 load test windows and every rows run. Shared plans steal
  time, and a runner can't produce that.
- **Burst credits.** A burstable plan runs fast until its credits are spent, over hours. A shape's quota is steady
  from the first second.
- **A slower CPU.** A quota makes a fast CPU run less often, not run slower. `medium-throttled` is a fast EPYC
  allowed 0.4 of its time, not a slow core.
- **Which cores.** `medium` on the EPYC 7763 read "2 CPUs on 1 core": one core's two threads, as `t3.medium` is,
  not two cores, as `t4g.medium` is. Only the runs on `c4a5945` and `1c6efc4` recorded their topology.
- **A real network.** The delay is a fixed 1 ms on Docker's bridge, with no jitter, loss or congestion.
- **A real app.** The load test's app has one healthy action and one that raises. A real app's requests do more
  work, which changes what share of its time RED takes.
- **Other stacks and Rubies.** Each was measured once, on `medium` only, as "Stacks and Ruby 4.0" below lists: one
  run each of Sidekiq, MySQL 8.4 and SQLite on Ruby 3.4.12, and of PostgreSQL with Solid Queue on Ruby 4.0.9. No
  other shape ran on them, and one run on one CPU each can't separate a stack from its CPU.

## The runner probe

Run 41214442263, 2026-10-31, commit `cd148d6`, before any shape existed. It tried the assumptions the shapes rest
on, inside a container on each runner.

| Check | x64, Xeon Platinum 8370C | arm64, no model name in `/proc/cpuinfo` |
|---|---|---|
| A cpuset of 2 CPUs: what Ruby sees | `Etc.nprocessors` = 2 | `Etc.nprocessors` = 2 |
| 4 GB, swap off | `memory.max` 4294967296, `memory.swap.max` 0 | the same |
| A quota of 0.4 CPU | used 0.41 CPU, throttled 101 times | used 0.41 CPU, throttled 101 times |
| CPU time stolen while throttled | 0.00% | 0.00% |
| `netem` 1 ms | 0.064 ms, then 1.125 ms: 1.06 ms added | 0.104 ms, then 1.178 ms: 1.07 ms added |
| k6 | v1.8.2, linux/amd64 | v1.8.2, linux/arm64 |

## Queue rows, no shape and no delay

Run 41216679726, 2026-10-31, commit `a5e5c47`. The rows on PostgreSQL in a service container, on a whole runner.

| Queue | Runner | CPU | Capture, async | p95 | Capture, sync | Health snapshot |
|---|---|---|---|---|---|---|
| none | x64 | EPYC 9V74 | 226 µs | 1.14 ms | 4.66 ms | 693 µs |
| Solid Queue | x64 | EPYC 9V74 | 2.13 ms | 4.75 ms | 4.56 ms | 681 µs |
| Sidekiq | x64 | Xeon 6975P-C | 398 µs | 742 µs | 4.39 ms | 511 µs |
| none | arm64 | Neoverse-N2 | 411 µs | 1.33 ms | 6.71 ms | 1.24 ms (fails 1 ms) |
| Solid Queue | arm64 | Neoverse-N2 | 3.14 ms | 4.14 ms | 6.31 ms | 1.23 ms (fails 1 ms) |
| Sidekiq | arm64 | Neoverse-N2 | 665 µs | 1.15 ms | 7.42 ms | 1.27 ms (fails 1 ms) |

## The four shapes, the database on the same runner

2026-11-05, before the network delay. Rows and load test in the same run.

| Run | Shape | CPU | Commit | Limits the app saw | Rate (capacity) | Throttled |
|---|---|---|---|---|---|---|
| 41994820359 | `medium` | EPYC 9V45 | `677dfd0` | 2 CPUs, 4.00 GB | 380/s (760) | never |
| 41994824736 | `small` | EPYC 7763 | `677dfd0` | 1 CPU, 1.00 GB | 240/s (480) | never |
| 41994828606 | `medium-throttled` | EPYC 7763 | `677dfd0` | 2 CPUs, 0.40 CPU, 4.00 GB | 55/s (110) | 60 to 98 times a window, 3.47 to 6.37 s |
| 41996203643 | `medium-arm` | Neoverse-N2 | `6b56cb6` | 2 CPUs, 4.00 GB | 190/s (380) | never |

The rows, median (p95):

| Shape | Capture, async | Capture, sync | Health snapshot | Storm check, calm | Reopen collision fallback |
|---|---|---|---|---|---|
| `medium` | 1.32 ms (1.92) | 3.23 ms (4.11) | 468 µs (602) | 4.98 µs (13.03) | 3.36 ms (3.97) |
| `small` | 2.27 ms (2.99) | 5.53 ms (6.82) | 784 µs (906) | 8.07 µs (17.21) | 5.78 ms (6.59) |
| `medium-throttled` | 2.33 ms (4.01) | 5.53 ms (25.07) | 803 µs (6.90 ms) | 8.40 µs (20.21) | 5.90 ms (22.34) |
| `medium-arm` | 2.55 ms (3.54) | 6.50 ms (11.41) | 1.23 ms (1.31), fails 1 ms | 7.68 µs (18.72) | 6.99 ms (7.95) |

What RED added under load, p50 / p95 / p99, in ms:

| Shape | `healthy` | `failing` | `storm` |
|---|---|---|---|
| `medium` | +0.02 / -0.22 / +0.12 | -0.00 / -0.03 / +1.59 | +0.07 / +0.17 / -2.11 |
| `small` | -0.01 / -0.63 / -0.08 | +0.02 / +0.15 / +1.42 | +0.11 / +0.44 / +0.70 |
| `medium-throttled` | +0.11 / +0.31 / -0.40 | +0.02 / +1.09 / +5.84 | +0.20 / +0.03 / -6.53 |
| `medium-arm` | +0.05 / -0.10 / +0.11 | -0.08 / -0.00 / +0.23 | +0.08 / -0.44 / -0.26 |

## The database 1 ms away

2026-11-05. Every shape delays its database's replies by 1 ms, and the rows' PostgreSQL too.

| Run | Shape | CPU | Commit | Round trip measured | Rate (capacity) |
|---|---|---|---|---|---|
| 42011156654 | `medium` | EPYC 9V45 | `ed0ed7f` | not trustworthy: it timed Docker's DNS (7.56 ms) | 360/s (720) |
| 42011161060 | `medium-arm` | Neoverse-N2 | `ed0ed7f` | not trustworthy: it timed Docker's DNS (4.17 ms) | 190/s (380) |
| 42028790110 | `medium` | EPYC 9V45 | `cb270a8` | 1.07 ms, 1.03 ms of it added | 340/s (680) |
| 42028794330 | `medium-arm` | Neoverse-N2 | `cb270a8` | 1.07 ms, 1.04 ms of it added | 170/s (340) |
| 42058012637 | `medium` | EPYC 7763, "2 CPUs on 1 core" | `1c6efc4` | 1.10 ms, 1.03 ms of it added | 220/s (440) |

`cb270a8` looks the database's name up once before timing. The two `ed0ed7f` runs' rows still had the delay, as
their capture rows show.

The rows, median (p95):

| Run | Capture, async | Capture, sync | Health snapshot | Reopen collision fallback |
|---|---|---|---|---|
| 42011156654 `medium` | 7.12 ms (7.68), fails 5 ms | 12.01 ms (13.77) | 437 µs (504) | 14.02 ms (15.35) |
| 42011161060 `medium-arm` | 8.78 ms (9.42), fails 5 ms | 15.44 ms (20.04) | 1.22 ms (1.28), fails 1 ms | 17.73 ms (18.97) |
| 42028790110 `medium` | 7.23 ms (8.71), fails 5 ms | 11.84 ms (13.60) | 425 µs (494) | 13.94 ms (15.12) |
| 42028794330 `medium-arm` | 8.90 ms (9.58), fails 5 ms | 16.38 ms (21.50) | 1.23 ms (1.31), fails 1 ms | 18.11 ms (19.07) |
| 42058012637 `medium` | 8.00 ms (8.73), fails 5 ms | 14.11 ms (17.23) | 755 µs (825) | 16.25 ms (17.17) |

What RED added under load, p50 / p95 / p99, in ms:

| Run | `healthy` | `failing` | `storm` |
|---|---|---|---|
| 42011156654 `medium` | -0.00 / -0.28 / -0.05 | +0.02 / -0.04 / +0.95 | +0.08 / +0.00 / +1.23 |
| 42011161060 `medium-arm` | +0.03 / -0.03 / +0.15 | +0.01 / -0.00 / +0.44 | +0.30 / -0.19 / +0.45 |
| 42028790110 `medium` | +0.02 / -0.19 / +0.37 | +0.04 / -0.17 / +1.98 | +0.07 / +0.22 / -4.03 (4 pairs) |
| 42028794330 `medium-arm` | -0.10 / -0.26 / -0.31 | -0.01 / +0.04 / +0.38 | +0.24 / -0.56 / +0.42 |
| 42058012637 `medium` | -0.01 / -0.26 / -0.24 | +0.01 / -0.13 / +0.71 | +0.12 / +0.31 / -0.12 |

On 42028790110 one window didn't finish: storm pair 3, RED on, 40,799 of 40,800 requests. It's left out, so that
storm row has four pairs. It is the only invalid window of the 270.

## Stacks and Ruby 4.0

2026-11-06, commit `8d20630`, shape `medium`, each stack's database 1 ms away, and Redis too on Sidekiq's. The
app and the rows both ran on the stack and Ruby named. Every window of the 150 held its rate.

| Run | Stack | Ruby | CPU | Round trip, load test | Round trip, rows | Rate (capacity) |
|---|---|---|---|---|---|---|
| 42166023618 | `postgres-solid-queue` | 3.4.12 | Xeon Platinum 8573C | 1.04 ms, 1.01 added | 1.04 ms, 1.02 added | 260/s (520) |
| 42166026955 | `postgres-sidekiq` | 3.4.12 | EPYC 9V74 | database 1.12 ms, 1.08 added; Redis 1.10 ms, 1.05 added | database 1.11 ms, 1.07 added; Redis 1.09 ms, 1.04 added | 260/s (520) |
| 42166030030 | `mysql-solid-queue` | 3.4.12 | EPYC 7763 | 1.10 ms, 1.02 added | 1.10 ms, 1.04 added | 200/s (400) |
| 42166033190 | `sqlite-solid-queue` | 3.4.12 | EPYC 9V74 | none: a file in the app's container | none | 300/s (600) |
| 42166036449 | `postgres-solid-queue` | 4.0.9 | EPYC 7763 | 1.09 ms, 1.02 added | 1.09 ms, 1.01 added | 280/s (560) |

The rows, median (p95). The rows reach MySQL through trilogy, as the test suite does, and the app through mysql2,
as `rails new --database=mysql` makes it:

| Run | Capture, async | Capture, sync | Health snapshot | Storm check, calm | Reopen collision fallback |
|---|---|---|---|---|---|
| 42166023618 PostgreSQL, Solid Queue | 7.76 ms (9.40), fails 5 ms | 13.47 ms (15.26) | 1.11 ms (1.23), fails 1 ms | 7.13 µs (15.87) | 15.50 ms (16.39) |
| 42166026955 PostgreSQL, Sidekiq | 1.47 ms (2.11) | 15.15 ms (18.92) | 653 µs (729) | 6.05 µs (13.01) | 17.00 ms (19.77) |
| 42166030030 MySQL, Solid Queue | 8.85 ms (10.54), fails 5 ms | 14.51 ms (17.73) | 781 µs (873) | 8.60 µs (20.36) | not applicable: its index is PostgreSQL's |
| 42166033190 SQLite, Solid Queue | 885 µs (1.64 ms) | 2.00 ms (2.90) | 640 µs (706) | 6.16 µs (14.63) | 1.91 ms (2.49) |
| 42166036449 PostgreSQL, Solid Queue, Ruby 4.0 | 7.96 ms (9.11), fails 5 ms | 14.36 ms (17.81) | 765 µs (831) | 7.01 µs (11.07) | 16.36 ms (17.68) |

What RED added under load, p50 / p95 / p99, in ms:

| Run | `healthy` | `failing` | `storm` |
|---|---|---|---|
| 42166023618 PostgreSQL, Solid Queue | -0.00 / -0.28 / -0.09 | +0.04 / -0.09 / +0.83 | +0.11 / +0.26 / -1.26 |
| 42166026955 PostgreSQL, Sidekiq | -0.04 / -0.13 / -0.25 | -0.01 / +0.10 / +0.74 | -0.04 / -0.81 / -2.18 |
| 42166030030 MySQL, Solid Queue | +0.14 / -0.11 / +0.09 | -0.08 / -0.34 / +0.82 | +0.15 / +0.21 / +0.04 |
| 42166033190 SQLite, Solid Queue | +0.00 / -0.10 / +0.04 | -0.02 / -0.13 / +0.82 | +0.11 / +0.26 / -1.25 |
| 42166036449 PostgreSQL, Solid Queue, Ruby 4.0 | -0.01 / -0.33 / -0.24 | +0.02 / +0.27 / +1.35 | +0.12 / +0.17 / +0.60 |

## Runs with no load report

- 41994832334, `medium-arm`, Neoverse-N2, `677dfd0`, 2026-11-05: the health snapshot row failed (1.24 ms), and the
  run stopped before the load test. `6b56cb6` runs the load test after a row misses, and 41996203643 replaced it.
  Its rows: capture, async 2.70 ms (3.69), sync 6.78 ms (11.95).
- 42055160402, `medium`, EPYC 7763, `c4a5945`, 2026-11-05: the load test stopped in its first minutes on a
  `require_relative` the app's container couldn't resolve. `1c6efc4` fixed it, and 42058012637 replaced it. Its
  rows: capture, async 8.52 ms (9.57), sync 14.85 ms (17.02), health snapshot 768 µs (827).

## What the figures say

1. **On a healthy request, RED's cost doesn't show above the noise.** Across the 9 load reports, what RED added
   to `healthy` read -0.10 to +0.11 ms at p50, -0.63 to +0.31 ms at p95 and -0.40 to +0.37 ms at p99, with
   pairs of both signs.
2. **A request that fails costs more, and the throttled shape shows it most.** `failing` p99 is above zero in
   every report: +0.23 to +5.84 ms. Under `medium-throttled`, RED added +5.84 ms at p99 and +1.09
   ms at p95, every pair positive at both (p99 pairs +5.26 to +11.60). The compare tool reads that as 8.26x the
   +0.71 ms of 42058012637's `medium`, on the same CPU model, though at a different commit, a different rate and
   with the database 1 ms away on `medium` only.
3. **A storm costs little at p50, and its tail is noise.** `storm` p50 read +0.07 to +0.30 ms, above zero in every
   report and with every pair positive in six of the nine. Its p99 swings from -6.53 to +1.23 ms, and one `medium-throttled` pair read -53.46 ms.
4. **Capture misses its 5 ms budget once the database is 1 ms away.** In the rows, async capture read 1.32 to 2.55
   ms with the database on the runner (2.70 on 41994832334), and 7.12 to 8.90 ms with the delay. Sync read 11.84
   to 16.38 ms. Counted locally against PostgreSQL and Solid Queue on 2026-11-05, async capture sends 7 statements
   on the request's thread, all of them Solid Queue's enqueue, and none of RED's own. Decision `0009` moves that
   enqueue after the response, for 1.0.0.rc1. The load test's `failing` mix shows less of it, probably because
   its p99 sits at the edge of its 1% failing requests rather than among them.
5. **The health snapshot fails 1 ms on arm64 and passes on AMD x64.** Neoverse-N2 read 1.22 to 1.27 ms in every
   run. AMD x64 read 425 to 803 µs, and 425 to 437 µs on the EPYC 9V45 with the database 1 ms away, so it
   doesn't wait on the database. Under `medium-throttled` its p95 was 6.90 ms. The budget becomes 1.5 ms on every
   CPU in 1.0.0.rc1.
6. **The storm check's medians stay under 15 µs, but not its p95.** In the shape runs, medians read 4.59 to
   12.11 µs. The p95 went over 15 µs at least once on every CPU, the EPYC 9V45 included (15.37 µs on
   41994820359), and up to 26.57 µs under `medium-throttled`.
7. **The shapes held.** Each showed the app its limits from inside its container, `medium-throttled` was throttled
   in all 30 windows, the delay read 1.03 and 1.04 ms added against 1 ms set, and 269 of 270 windows held their
   rate.
8. **Capture's miss is Solid Queue's enqueue across the network, on every stack that has one.** Async capture failed
   5 ms on PostgreSQL (7.76 ms, and 7.96 on Ruby 4.0) and on MySQL (8.85 ms), with Solid Queue in the database
   server 1 ms away. It passed with Sidekiq (1.47 ms), whose enqueue is one call to Redis, and on SQLite (885 µs),
   where nothing crosses a network. Under load the stacks read alike: `healthy` within -0.04 to +0.14 ms at p50,
   and `failing` p99 +0.74 to +1.35 ms. Ruby 4.0's run read like Ruby 3.4's, on a different CPU. The health
   snapshot's one miss, 1.11 ms, was on the Xeon Platinum 8573C, where CI's overhead benchmark has missed it too.
