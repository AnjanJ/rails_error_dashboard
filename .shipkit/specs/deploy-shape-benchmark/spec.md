# Spec: Overhead on deploy shapes

> Spec accepted at commit `5e7d7be` on spec/deploy-shape-benchmark (2026-10-31).
> Status: open
> Paths: bin/benchmark,bin/benchmark-load,benchmark/,.github/workflows/deploy-benchmark.yml,spec/benchmark/,spec/ci/,.shipkit/research/

## Purpose
RED's figures come from GitHub's runners and an M3 Max, on one idle process with SQLite and a fake queue. This
gives the repo a free way to measure what RED adds to a real app under load, on a real database and queue, held
to the CPU and memory of the machines Rails apps run on. It measures their shape in GitHub CI, not the machines.

## User stories
- As a Rails developer on a small server, I want to know how much RED slows my requests, so that I can
  decide to install it.
- As the maintainer, I want the budgets and README figures to rest on a real stack under load, so that 1.0
  doesn't freeze a claim that only holds on one idle process.

## Requirements (EARS)

### The rows on a real stack
- **REQ-1.** Where `BENCHMARK_DATABASE_URL` is set, `bin/benchmark` shall run every scenario against that
  database instead of its scratch SQLite file.
- **REQ-2.** If the database named by `BENCHMARK_DATABASE_URL` doesn't have `benchmark` in its name, then
  `bin/benchmark` shall exit with an error before it changes anything.
- **REQ-3.** Where `BENCHMARK_QUEUE` names `solid_queue` or `sidekiq`, `bin/benchmark` shall enqueue through
  that adapter instead of its null adapter.
- **REQ-4.** If a scenario can't run on the current database, then `bin/benchmark` shall report that row as
  not applicable and finish the run.
- **REQ-5.** The report shall name the CPU architecture, and shall name a CPU on ARM Linux, where
  `/proc/cpuinfo` has no `model name`.
- **REQ-6.** The report shall state the CPU limit and memory limit the process runs under.
- **REQ-7.** The report shall state the share of CPU time stolen during the run.

### The load test
- **REQ-8.** The load test shall serve a real Rails app through Puma in production mode, with RED added by its
  installer and the app otherwise on the Rails generator's defaults.
- **REQ-9.** The load test shall send requests at a fixed arrival rate, whatever the response times.
- **REQ-10.** When no rate is given, the load test shall measure the app's capacity with RED off and use half
  of it.
- **REQ-11.** The load test shall alternate RED-off and RED-on windows at the same rate, at least five pairs
  per traffic mix.
- **REQ-12.** The load test shall run three traffic mixes: all healthy, 1% failing, and an error storm.
- **REQ-13.** The load test report shall give p50, p95 and p99 latency per mix with RED off and on, and what
  RED added in each pair.
- **REQ-14.** The load test report shall give the share of CPU time stolen in each window.
- **REQ-15.** If a window drops requests or returns an unexpected status, then the load test shall mark that
  window invalid and leave it out of the results.

### Shapes in GitHub CI
- **REQ-16.** When the maintainer dispatches the deploy benchmark workflow with a shape, the workflow shall run
  the rows and the load test inside containers held to that shape's CPU and memory limits.
- **REQ-17.** Where a stack has a network database, the workflow shall add that shape's network delay between
  the app and the database.
- **REQ-18.** The workflow shall run only when dispatched by hand, with a read-only token and no secrets.
- **REQ-19.** A report from a shape shall say that it measures the machine's shape, not the machine.

### Comparing the results
- **REQ-20.** When given two load test reports, the compare tool shall print what RED added in each, per mix,
  and the ratio between them.
- **REQ-21.** The research file shall hold every figure with its shape, CPU, commit and date. [untested:
  prose, verified by reading]

## Out of scope
- Real servers on any provider, and any spend. The maintainer chose CI only on 2026-10-31.
- Claims about a named provider or plan. A shape isn't that machine.
- Self-hosted runners.
- Changing a budget, the CI gate, the README's figures or any gem code.
- Timing dashboard pages or background job execution.

## Release steps
None of this ships in the gem. No release follows from it.
