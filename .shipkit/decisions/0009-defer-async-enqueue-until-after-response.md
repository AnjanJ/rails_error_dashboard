# 0009: Async capture enqueues after the response is sent, where the server allows it

- **Date:** 2026-11-05. Status: accepted (the maintainer confirmed on 2026-11-05, from the deploy shape
  benchmark's runs and a count of capture's statements made the same day).

## Context

Capture's budget is 5 ms (`.shipkit/product.md`, Constraints). The shape benchmark put the database
1 ms away from the app with tc netem (`deploy-shape-benchmark`, T17), as a managed database would be.
There, capture with the installer's async default read 7.12 and 7.23 ms on an EPYC 9V45 and 8.78 and
8.90 ms on a Neoverse-N2 (runs 42011156654, 42011161060, 42028790110, 42028794330). With the database
on the same machine it passes.

One failing request through `ErrorCatcher`, on PostgreSQL with Solid Queue, sends 7 statements on the
request's thread in async mode, and every one is Solid Queue's enqueue of `AsyncErrorLoggingJob`
(`commands/log_error.rb:236`): BEGIN, the job's INSERT, a savepoint, a SELECT of the job, the ready
execution's INSERT, RELEASE and COMMIT. RED itself sends none. So the miss is 7 network round trips
that the host app's response waits on. Solid Queue is Rails 8's default queue. Sidekiq's enqueue is one
Redis round trip.

Rack 3 lets a server run callbacks once the response is sent: `env["rack.response_finished"]`. Puma
8.0.2 implements it (`lib/puma/response.rb`), and so does Rails 8.1's `ActionDispatch::Executor`.

## Alternatives

1. Hand async capture's enqueue to `rack.response_finished` when the request's env has it, and enqueue
   inline as today when it doesn't, or outside a request (jobs, rake, a console).
2. Keep the code, and say the 5 ms assumes the queue's database on the same machine.
3. Raise capture's budget.

## Case for 1

The response leaves before the 7 round trips, so "time RED adds before the response", the thing the
paramount rule protects, holds across a network without RED knowing which queue it has. Where a server
has no such hook, nothing changes. A failed enqueue still falls back to sync logging, after the
response instead of before it. It is the code change for small boxes the benchmark was built to find
before rc1, while a behaviour change is still allowed.

## Case against 1

The Puma thread still spends the round trips after the response, so throughput under errors doesn't
improve, only latency. If the process dies between the response and the callback, that error is lost,
which `.shipkit/product.md` allows ("RED gives up its data, never the host app's uptime"), but which a
user may not expect. It's a second path through capture to test, and a server's hook can behave
differently from Puma's.

## Decision

1. Async capture enqueues in `rack.response_finished` where the env has it, and inline otherwise. The
benchmark gains a row for the work after the response, and the shapes are re-run with the database
1 ms away. Built test-first as a task of the 1.0.0.rc1 spec.

**I would reverse this if** an issue reports errors lost between the response and the callback on a
server RED supports, or if the callback's work slows a host app's throughput by more than the inline
enqueue did (then enqueue inline again, and say what the budget assumes).
**Fired-if.** manual
