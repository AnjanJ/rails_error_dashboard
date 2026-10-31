# Intake: Overhead on deploy shapes

> Intake taken on 2026-10-31.

## Request
The maintainer: "our performance checks should be made on the software and hardware most indie devs and
rails engineers are gonna use to deploy, on things like medium amazon servers, digital ocean, hetzner
servers etc."

On how to do it: "can we find the medium tier hardware they use and work with thast using github ci ?"

## Serves goal
Prove the overhead budget — metric: capture time and storm-check time, measured by a reproducible
benchmark that ships in the repo; target: capture < 5ms, storm check < 15µs, both on the CI benchmark's
runner (the documented budgets); by: 2026-12-31

## Conflicts found
None. Searched: the non-goals in `.shipkit/product.md`, decision records `0001` to `0008`, and the
decisions and out-of-scope list in `_shipped/overhead-benchmark`. No spec is open.

Two things sit close and don't conflict:
- `_shipped/overhead-benchmark` puts "Benchmarking dashboard pages or background jobs" out of scope. This
  work still doesn't time them. It times what a real queue costs on the request thread, and sees workers
  only as load on the same CPUs.
- `_shipped/overhead-benchmark/design.md` assumes "A host's servers look like the runner". This work doesn't
  test that assumption, because it runs on the runner. It stays untested.

## Answers
1. **What should it measure?** The existing rows, with PostgreSQL over a network and a real queue, plus a real
   Rails app under load with RED on and off, reporting request latency.
2. **Which plan?** CI only: no real servers, no accounts and no spend. Offered and declined: CI plus real
   Hetzner servers under a €20 cap, and CI plus AWS, DigitalOcean and Hetzner.

## Assumptions made
- **CI measures a machine's shape, not the machine.** A job can't choose its CPU, and none of the CPU models
  seen on hosted runners appears on AWS's lists. Hetzner and DigitalOcean publish no models to compare. Docker
  can set CPU and memory limits, and there's no known way to produce neighbours' CPU steal or hours-long burst
  credit behaviour on a runner. None of this has been tried on a runner yet.
- **The main stack is what the 2026 Rails survey and a new Rails app point to:** Ruby 3.4, Rails 8.1,
  PostgreSQL (83.8%), Puma (91.8%), one process with 3 threads, Solid Queue inside Puma, jemalloc and YJIT on.
  Sidekiq (61.3%), MySQL (23.2%), SQLite (19.7%) and Ruby 4.x (49.4%) are variants.
- **No gem code changes.** The harness isn't in the gem, and `bin/benchmark`'s budgets and gate stay as they
  are. A change to either needs its own decision record.
- **The tooling lives in this repo,** because the goal says the benchmark ships in the repo.
- **No instance-size data exists.** No source says how many people run a "medium", so the shapes are the
  maintainer's chosen sizes, not a measured popularity.

## Out of scope
- Real servers on any provider, and any spend.
- Claims about a named provider or plan.
- Self-hosted runners, which GitHub says "should almost never be used for public repositories".
- Changing a budget, the CI gate, the README's figures or any gem code.
- Timing dashboard pages or background job execution.
