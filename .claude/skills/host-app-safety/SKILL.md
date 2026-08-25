---
description: Host app safety rules and performance budgets for rails_error_dashboard
user-invocable: false
---

# Host App Safety Knowledge Base

This gem runs INSIDE the host Rails app's process. Every line of code we write can break the host app. These rules are non-negotiable.

## The 11 Safety Rules

1. **Never raise in the error capture path** — rescue at every layer. If our error tracker raises while capturing an error, we've made the situation worse.
2. **Never block the request path** — all heavy work (notifications, analytics) must be async/background. The request thread must return ASAP.
3. **Budget every operation** — breadcrumb callback <0.01ms, health snapshot <1ms, total capture <5ms. Measure with `Process.clock_gettime(Process::CLOCK_MONOTONIC)`.
4. **Clean up Thread.current** — always use `ensure` blocks. Puma reuses threads across keepalive connections (Puma #823).
5. **Always re-raise original exceptions** — Sentry #1173: swallowed Sidekiq exceptions prevented retries. After capture, always `raise` the original.
6. **Feature-detect before calling** — `defined?(Puma)`, `respond_to?(:stats)`. Never assume a server/library exists.
7. **Make everything disableable** — every request-path feature needs a config flag. Users must be able to turn off anything that causes problems.
8. **Never use ObjectSpace.each_object** — freezes all threads and grows the heap, and the cost compounds across later GC cycles. Use `GC.stat` for memory info. `ObjectSpace.count_objects` **is** allowed: it returns O(1) type counts without walking the heap, and `DiagnosticDumpGenerator` uses it deliberately.
9. **Never use Signal.trap** — breaks Puma/Sidekiq signal handling (USR1/USR2 reserved). Use rake tasks for diagnostics.
10. **Never store Binding objects** — prevents GC of entire call stack. Extract local variables immediately into plain data.
11. **Never call `Thread#backtrace` across `Thread.list`** — collecting backtraces for every thread holds the GVL while it walks each stack, stalling the whole process. Capture thread name/status/alive only. `DiagnosticDumpGenerator` notes this explicitly.

## Real-World Incidents

### Sentry #1173 — Swallowed Sidekiq Retries
Middleware captured exception but forgot to re-raise. Sidekiq treated failed jobs as successful. Retries never happened. Production data loss.
[sentry-ruby#1173](https://github.com/getsentry/sentry-ruby/issues/1173)

### Puma #823 — Thread-Local Leak Across Keepalive
Thread.current values leaked between requests on the same keepalive connection. Puma only cleaned thread-locals before new work assignment, not between requests.
[puma#823](https://github.com/puma/puma/issues/823)

### Coverband — TracePoint :line Was 2.5x Slower
Abandoned TracePoint :line in favor of Coverage API (1.08x vs 2.5x overhead). Never use :line in production by default.
[coverage_rails_benchmark](https://github.com/danmayer/coverage_rails_benchmark)

### Ruby #18264 — TracePoint Memory Leak
`rb_tp_t` struct allocated with RUBY_TYPED_NEVER_FREE in Ruby 2.6-3.0. Repeatedly creating TracePoints caused unbounded RSS growth. Gate on Ruby >= 3.2.
[bugs.ruby-lang.org#18264](https://bugs.ruby-lang.org/issues/18264)

### Rails AS::Notifications — Subscribers CAN Crash Requests
`iterate_guarding_exceptions` collects subscriber exceptions and RE-RAISES them. A buggy subscriber on `sql.active_record` crashes the SQL query's caller. Breadcrumb subscriber MUST have its own rescue.
[rails fanout.rb](https://github.com/rails/rails/blob/main/activesupport/lib/active_support/notifications/fanout.rb)

### Rack Middleware Constant Mutation
Shared mutable headers hash in a constant grew unbounded across requests. Never use mutable constants for per-request data.
[bernardoamc.com/rails-middleware-leak](https://bernardoamc.com/rails-middleware-leak/)

### Signal.trap — Last Writer Wins
Puma uses USR1 (phased restart), USR2 (full restart). Sidekiq Enterprise uses USR2. Signal.trap completely replaces previous handler — no chaining.
[sidekiq#3803](https://github.com/sidekiq/sidekiq/issues/3803)

### Sentry #1246 — Transport Swallowed Network Errors
`Sentry::Transport.send_data` caught all network errors silently; `transport_failure_callback` never fired on 4xx/5xx. Transport failures were completely invisible. Rescuing is not enough — always log what failed and why. A silent rescue in our notification dispatch would fail the same way.
[sentry-ruby#1246](https://github.com/getsentry/sentry-ruby/issues/1246)

### SolidQueue #271 — Connection Pool Exhaustion
Default pool config didn't account for polling and heartbeat connections. Each worker thread needs its own connection, plus 2 extra: `pool >= (threads * processes) + dispatcher_threads + 2`. If we run background jobs, document the pool requirement — our separate-database option is the mitigation.
[solid_queue#271](https://github.com/rails/solid_queue/issues/271)

### Mailboxer #480 — Index Name Too Long
An engine migration generated `index_mailboxer_notifications_on_notified_object_type_and_notified_object_id`, exceeding PostgreSQL's 63-character limit. The migration fails on the host app's database, during their deploy. Always name compound indexes explicitly in our migrations; never rely on auto-generated names.
[mailboxer#480](https://github.com/mailboxer/mailboxer/issues/480)

### Puma #2767 — Signal Handler Coexistence Is Unsolved
Puma attempted "non-overriding" signal handlers that coexist with handlers registered before it, and had to override its own previous traps while preserving third-party ones. The PR demonstrates the problem is fundamentally hard. This is the evidence behind Rule 9 — don't try to be a good citizen with signals, just don't use them.
[puma#2767](https://github.com/puma/puma/pull/2767)

## Lessons from Competitors

Every major error-tracking SDK has had an incident where it damaged the host app. The pattern repeats: an edge case where the SDK's own error handling fails, and that failure propagates into the application.

**Sentry Ruby** — background worker thread pool for async transport, so network failures never touch the request thread. Transport defines `HTTP_ERRORS` (Timeout::Error, SocketError, Errno constants), all caught and logged, never propagated. `Sentry::Rack::CaptureExceptions` captures, reports, then re-raises. Stated design principle: "Any exception that happens after `Sentry.capture_*` is called shouldn't crash the user's app."

**Honeybadger** — single-threaded worker processing one Notice at a time, isolated from request threads. Queue capped at 100; when full, new notices are **dropped**. Adaptive throttling multiplies delay by 1.05x on throttle responses. Middleware is `rescue Exception => raised; notify; raise` — bare `raise` preserves the original. Synchronous fallback at exit skips the worker queue when the process is already crashing.

**Bugsnag** — `skip_bugsnag` property on exceptions prevents duplicate notifications when re-raised through multiple handlers. Middleware is not allowed to change critical `handledState` properties. Explicit protection against exception-unwrapping infinite loops via the `original_exception` pattern. Built-in middleware can be force-disabled if it misbehaves.

**Key takeaway:** the only defense is defense in depth — rescue at every layer, always re-raise the original, and prefer data loss over application damage. Honeybadger dropping notices at a full queue is the model: our storm protection (circuit breaker + adaptive sampling, v0.8.2) is the same trade made deliberately.

## Performance Budgets

| Operation | Budget | Where |
|-----------|--------|-------|
| Breadcrumb callback | <0.01ms | AS::Notifications subscriber |
| Health snapshot | <1ms | GC.stat + connection_pool + Thread.list |
| Total error capture | <5ms | Middleware + subscriber path |
| Notification dispatch | 0ms sync | Always async via ActiveJob |
| Pattern detection | <10ms | Background job only |
| Analytics queries | <100ms | Dashboard request, not capture path |

## Code Review Checklist

When reviewing changes to the capture path (`middleware/`, `error_subscriber.rb`, `commands/log_error.rb`, `commands/find_or_increment_error.rb`):

- [ ] Every public method has a rescue clause
- [ ] No `raise` statements (except re-raising the original)
- [ ] No blocking I/O (HTTP calls, file reads, external services)
- [ ] Thread.current cleaned in `ensure`
- [ ] No `ObjectSpace.each_object`, `Signal.trap`, `Thread#backtrace`, or `Binding` storage
      (`ObjectSpace.count_objects` is O(1) and allowed — see Rule 8)
- [ ] Feature-gated with config check
- [ ] Performance measured and within budget

## Memory-Bounding Patterns (all three original issues now fixed)

The three unbounded-memory issues this file used to list as open are fixed. They are kept here as
worked examples, because the same mistake is easy to reintroduce. All three live under
`lib/rails_error_dashboard/`, not `app/` — the paths in older notes are stale.

1. **`queries/dashboard_stats.rb`** — `average_resolution_time` loaded every resolved record to
   average them in Ruby. Now aggregates in SQL via `scope.pick(Arel.sql(avg_seconds_sql))`, with a
   per-adapter expression. **Pattern: aggregate in the database, not in Ruby.**
2. **`services/pattern_detector.rb`** — iterated ActiveRecord objects to build an hourly
   distribution. Now a pure function taking an array of plucked timestamps, so the caller controls
   what is loaded. **Pattern: push data loading out to the caller; keep analysis pure.**
3. **`services/cascade_detector.rb`** — nested query loops with no LIMIT. Now `pluck`s
   `(error_log_id, occurred_at)` and runs an O(N + pairs) two-pointer sweep over the time-sorted
   rows. Its own comment records why: ~16 bytes/row instead of ~5KB/row, because the host app
   schedules this job and the lookback window may be large. **Pattern: pluck the two columns you
   need, never load the row.**

When adding any query that could touch an unbounded number of rows, pick one of these three shapes.

## Risk Ratings — Shipped Surfaces

These were written as pre-implementation risk ratings; all of them have since shipped. They now
say where the danger already lives, so treat them as a map of what to re-check when touching
these areas.

- **CRITICAL**: AS::Notifications subscribers (breadcrumbs) — must self-rescue or crash the
  caller's SQL query. TracePoint `:line` (detailed mode) — 2.5x overhead, opt-in only.
  Signal.trap was rated critical and consequently **never built**: the diagnostic dump uses
  `at_exit` and an explicit call instead (see Rule 9).
- **HIGH**: TracePoint `:raise`, swallowed-exception detection, retention DELETE (batch it —
  `in_batches(of: 1000)`, never a single unbounded DELETE).
- **MEDIUM**: system health snapshot, auto-reopen race condition, background job health.
- **LOW**: flexible auth, BRIN index migration, issue-tracker creation.

Since these ratings were written, three further request-path surfaces shipped and belong on the
map: **storm protection** (circuit breaker + adaptive sampling, v0.8.2) and **Rack::Attack event
tracking** are both HIGH — they run on live traffic, and Rack::Attack has already needed four
correctness fixes. **Outbound OTel export** (v0.8.0) is MEDIUM: `Integrations::Tracer.emit?` gates every span on
the master `enable_otel_export` flag, the OTel API actually being loaded, and the span kind
appearing in `config.otel_spans` — which defaults to all four kinds, so it is opt-out per
kind once export is on. When any gate fails it yields a `NOOP_SPAN` and preserves the block's
return value, which is the pattern to copy for any future façade.
