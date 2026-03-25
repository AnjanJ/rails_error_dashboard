# Rails Error Dashboard — Roadmap

> Last updated: March 25, 2026 | Current version: v0.5.3
> Deep introspection analysis: [DEEP_INTROSPECTION_ANALYSIS.md](DEEP_INTROSPECTION_ANALYSIS.md)
> Faultline comparison: [FAULTLINE_COMPARISON.md](FAULTLINE_COMPARISON.md)
> Time-series strategy: [TIMESERIES_ANALYSIS.md](TIMESERIES_ANALYSIS.md)
> **Host app safety: [HOST_APP_SAFETY.md](HOST_APP_SAFETY.md)** — MUST READ before implementing any feature

## The Big Picture

The gem sits in a **sweet spot**: more capable than Solid Errors (475 stars, minimal by design) and Faultline (64 stars, brand new), but infinitely simpler to run than self-hosted Sentry (12+ Docker services). The positioning is clear:

> **"It's just a gem."** No Docker Compose, no separate services, no DevOps team. `bundle install`, migrate, mount, done.

### Competitive Landscape

| Metric | rails_error_dashboard | solid_errors | faultline | findbug | exception_notification |
|--------|-----------------------|-------------|-----------|---------|----------------------|
| Total Downloads | 9,779 | 276,761 | N/A (git-only) | 1,447 | 22,144,698 |
| GitHub Stars | 35 | 481 | 72 | 25 | 2,185 |
| Last Commit | 2026-03-08 (active) | 2025-11-24 (stale) | 2026-03-06 (active) | 2026-02-25 (active) | 2021-12-28 (dead) |
| Dashboard UI | Yes (Bootstrap 5) | Yes (minimal) | Yes (Tailwind) | Yes | No |
| Notifications | Slack, Email, Discord, PagerDuty, Webhooks | Email | Telegram, Slack, Email, Webhooks | Slack, Email, Discord, Webhooks | Email, Slack, many more |
| Rails Versions | 7.0 - 8.1 | 7.1+ | 8.0+ | 7.0+ | 7.1+ |
| Dependencies | 2 required + optional | 0 extra | 0 extra | 7 (incl. Redis) | 2 |
| Local Variables | Yes (TracePoint) | No | Yes (TracePoint) | No | No |
| Auth | HTTP Basic + Custom Lambda | N/A | Devise/Warden/Lambda | ? | N/A |
| Error Model | Single record + count | Single record | Group + Occurrences | Single record | N/A |
| GitHub Issues | Planned (v0.5) | No | Yes | No | No |
| Auto-Reopen | Yes | No | Yes | No | N/A |
| Telegram | Planned (v0.5) | No | Yes | No | No |
| Performance Monitoring | Planned (v0.6) | No | No | Yes (Redis-based) | No |

> **Detailed comparison:** See [FAULTLINE_COMPARISON.md](FAULTLINE_COMPARISON.md) for full feature-by-feature analysis.

### vs SaaS (Sentry, Honeybadger, Rollbar, Bugsnag, Airbrake)

- **Zero recurring cost** — the biggest pain point with every SaaS is pricing at scale
- **Data sovereignty** — all data stays on your server
- **No external dependencies** — runs on your existing Rails + Postgres stack
- **5-minute setup** — versus Sentry self-hosted needing a DevOps team

### The Unfair Advantage: We're Inside the App

No SaaS can do what a gem running inside the Rails process can do. Sentry gets an error payload over HTTP. We get the entire Ruby VM, the database connection pool, the request lifecycle, `ActiveSupport::Notifications`, `GC.stat`, `ObjectSpace`, the middleware stack, and every model in the app.

Rails already instruments **everything** via `ActiveSupport::Notifications`:
- Every SQL query (`sql.active_record`) — duration, cached?, row_count
- Every controller action (`process_action.action_controller`) — view_runtime, db_runtime, allocations
- Every partial/template render (`render_partial.action_view`) — identifier, allocations
- Every cache read/write (`cache_read.active_support`) — key, hit/miss
- Every job enqueue/perform (`enqueue.active_job`, `perform.active_job`) — adapter, db_runtime
- Every email delivery (`deliver.action_mailer`) — mailer, subject, to
- Every transaction (`transaction.active_record`) — outcome (commit/rollback)
- Deprecation warnings (`deprecation.rails`) — message, callstack
- Unpermitted parameters (`unpermitted_parameters.action_controller`) — rejected keys

Plus direct access to:
- `GC.stat` — heap_live_slots, major_gc_count, total_allocated_objects
- `Process` RSS — memory usage at error time
- `Thread.list` — thread count, backtraces
- `ActiveRecord::Base.connection_pool.stat` — pool size, busy, waiting, dead
- `Puma.stats` — worker capacity, backlog, thread utilization
- `ActiveSupport::CurrentAttributes` — auto-detect current user, tenant, request context
- `Sidekiq::Stats` / `SolidQueue::FailedExecution` — background job health
- `Rails.cache.redis.info` — cache hit rates, memory usage
- Database introspection — table sizes, unused indexes, active queries, lock contention

**Tagline: "Everything Sentry shows you, minus the $442/month bill, plus things only a gem inside your app can know."**

---

## Tier 0 — Insider Advantage Features (only possible because we're inside the process)

These features are impossible or impractical for SaaS error trackers. They represent the gem's unique competitive moat.

### A. Breadcrumbs via ActiveSupport::Notifications (zero config) — DONE
- **What:** Subscribe to Rails instrumentation events, keep a rolling buffer per-request (last 25-50 events). When an error fires, attach the buffer as a timeline. The developer sees every SQL query, cache hit/miss, partial render, and job enqueue that happened before the crash
- **Why:** Sentry and Honeybadger have breadcrumbs, but they require SDK configuration. We get them **automatically** because Rails already emits the events. Zero config for the user
- **Implementation:** `ActiveSupport::Notifications.subscribe` for key events, store in `Thread.current[:error_dashboard_breadcrumbs]`, flush on error capture
- **Effort:** 2-3 days
- **Impact:** Differentiation +++ (neither Solid Errors nor Faultline have this)
- **Implemented:** Ring buffer (40 items), thread-local, 7 event categories (sql, controller, cache, job, mailer, deprecation, custom), color-coded timeline UI, async-compatible. Safe by design: every subscriber wrapped in rescue, message truncation, internal queries filtered, sensitive data filtered

### B. Per-Request SQL Analysis & N+1 Detection — DONE
- **What:** Subscribe to `sql.active_record`, count queries per request, detect repeated query patterns. When an error fires, attach: total query count, total DB time, and flagged N+1 patterns (same query fingerprint executed 3+ times)
- **Why:** N+1 queries are the #1 Rails performance problem. The Bullet gem only works in development. Prosopite is typically disabled in production. We can do lightweight N+1 detection on every request that errors, for free
- **Effort:** 1-2 days
- **Impact:** Differentiation +++ (no error tracker does this)
- **Implemented:** Per-error N+1 detection card (display-time analysis, zero request overhead), smart SQL normalization, configurable threshold (default 3). v0.3.0 added: aggregate N+1 Queries page (`/errors/n_plus_one_summary`) grouped by SQL fingerprint across all errors, eager loading tips with extracted table names

### C. System Health Snapshot at Error Time — DONE
- **What:** At the moment an error is captured, snapshot: process RSS (memory), `GC.stat` (heap pressure, GC count), `Thread.list.count`, `ActiveRecord::Base.connection_pool.stat` (pool exhaustion), and `Puma.stats` if available (server capacity)
- **Why:** Developers always ask "was the server under pressure when this happened?" Memory leaks, connection pool exhaustion, and thread starvation all cause errors that are impossible to diagnose without this context. No SaaS error tracker can capture in-process GC and connection pool stats
- **Effort:** 1 day
- **Impact:** Differentiation ++ (unique to in-process gems)
- **Implemented:** Sub-millisecond capture, every metric individually rescue-wrapped, no ObjectSpace, no Thread backtraces, no subprocess. Displays GC stats, process memory, thread count, connection pool, and Puma stats on error detail page

### D. Auto-Enriched User Context via CurrentAttributes — DONE
- **What:** At error time, check `ActiveSupport::CurrentAttributes.subclasses` for the host app's `Current` class. If `Current.user` exists, auto-capture user email/name/id without requiring configuration
- **Why:** Currently the gem requires config or relies on `controller.current_user`. With CurrentAttributes detection, user context is captured automatically — true zero-config. This is how Honeybadger's auto-context works, but we can do it more deeply because we're in-process
- **Effort:** Half day
- **Impact:** Polish ++ (zero-config appeal)

### E. Error Replay — "Copy as curl" / "Copy as RSpec" — DONE
- **What:** Capture HTTP method, path, headers (filtered), params, and body at error time. Generate a one-click "Copy as curl" command and "Copy as RSpec request spec" on the error detail page
- **Why:** The hardest part of fixing a production error is reproducing it. Handing the developer a ready-to-run curl command or test gets them from "I see the error" to "I can reproduce it" in seconds. **No competitor does this**
- **Effort:** 1-2 days
- **Impact:** Novel +++ (genuinely unique differentiator)
- **Implemented:** `CurlGenerator` service + "Copy as curl" button, `RspecGenerator` service + "Copy as RSpec" button. Both in Request Context card on error detail page. Shell-escaped, fail-safe, handles all HTTP methods and edge cases. 14 test cases for RSpec generator

### F. Deprecation Warning Tracker — DONE
- **What:** Subscribe to `deprecation.rails` notifications. Capture deprecation warnings with their callstack and display on a dedicated "Deprecations" tab. Group by warning type, show frequency, and flag which code paths trigger them
- **Why:** Deprecation warnings are "future errors" — things that will break on the next Rails upgrade. No error tracker captures these. This turns the dashboard into a Rails upgrade planning tool
- **Effort:** 1 day
- **Impact:** Unique ++ (no competitor has this)
- **Implemented:** Per-error red summary card with warning message and caller location. v0.3.0 added: aggregate Deprecations page (`/errors/deprecations`) grouped by message+source across all errors, with occurrence counts, affected error links, and 7/30/90 day filtering. Rails Upgrade Guide link

### G. Background Job Health Panel — DONE
- **What:** If Sidekiq is loaded, read `Sidekiq::Stats` (retry queue, dead queue, queue latencies). If SolidQueue, read `SolidQueue::FailedExecution`. Show a "Background Jobs" health panel alongside errors. Correlate failed jobs with error logs
- **Why:** Failed background jobs ARE errors, but most dashboards miss them entirely. Showing retry queue growing, dead jobs accumulating, and queue latency spiking alongside error rates gives a complete operational picture
- **Effort:** 1-2 days
- **Impact:** Operational value ++ (fills a real gap)
- **Implemented:** `SystemHealthSnapshot` service auto-detects and captures Sidekiq (enqueued/processed/failed/dead/scheduled/retry/workers), SolidQueue (ready/scheduled/claimed/failed/blocked), and GoodJob (queued/errored/finished) stats in `system_health` JSON column. Job Health page (`/errors/job_health_summary`) displays per-error job queue stats sorted by failed count, with summary cards (errors with job data, total failed, adapters detected), adapter badges, color-coded failed counts, and 7/30/90 day filtering. Active Job Guide link. Sidebar nav link under `enable_system_health` guard

### H. Database Health Panel — DONE
- **What:** Query `pg_stat_user_tables` (table sizes), `pg_stat_user_indexes` (unused indexes, scan counts), `pg_stat_activity` (active/blocked queries), and connection pool stats. Show as a "Database Health" tab
- **Why:** This is what PgHero does as a standalone gem. Having it built into the error dashboard means developers see database issues in the same context as errors. "Your users table is 4.2GB with 3 unused indexes" next to "ActiveRecord::StatementTimeout errors spiked 3x this week"
- **Effort:** 1-2 days
- **Impact:** Operational value ++ (lightweight PgHero built-in)
- **Implemented:** Two-section DB Health page (`/errors/database_health_summary`). **Section A (Live):** `DatabaseHealthInspector` service queries PostgreSQL system views at display time (not capture path) — connection pool stats (all adapters), table stats from `pg_stat_user_tables` (size, rows, scans, dead tuples, vacuum timestamps), unused indexes from `pg_stat_user_indexes`, connection activity from `pg_stat_activity` (aggregates only). Host app vs gem tables separated, gem tables collapsible. Non-PostgreSQL adapters get info banner with pool stats still shown. **Section B (Historical):** `DatabaseHealthSummary` query extracts `connection_pool` data from `system_health` JSON per-error, with utilization % (color-coded: >=80% danger, >=60% warning), stress-score sorting (busy+dead+waiting), dead/waiting badges, and 7/30/90 day filtering. Database Guide link. Sidebar nav link under `enable_system_health` guard

### I. Cache Health Monitoring — DONE
- **What:** Subscribe to `cache_read.active_support`, track hit/miss ratio over time. Show cache effectiveness on the dashboard. Alert when hit rate drops below threshold
- **Why:** A sudden cache hit rate drop often **precedes** error spikes (Redis went down, cache keys changed after deploy). Correlating cache health with error rate is unique context only an in-process gem can provide
- **Effort:** 1 day
- **Impact:** Operational value + (useful correlation)
- **Implemented:** Per-error cache card with reads, writes, hit rate (color-coded), total time, slowest operation. Hit rate advisories when below 80%. v0.3.0 added: aggregate Cache Health page (`/errors/cache_health_summary`) sorted worst-first across all errors. Rails Caching Guide link

### J. Enriched Error Context (Low-Hanging Fruit) — DONE
- **What:** Capture these additional data points at error time — all trivially available from the Rack env and Rails internals:
  - HTTP method (`request.method`) — GET vs POST matters enormously
  - Response status code — 500? 422? 503?
  - Request headers (filtered allowlist: Content-Type, Accept, Referer, X-Request-Id)
  - Server hostname (`Socket.gethostname`)
  - Request duration at point of failure (timer from middleware entry)
  - Queue time from `X-Request-Start` header (time in load balancer)
  - Database query count and total time for the request
  - Rails environment (`Rails.env`)
- **Why:** These are the data points developers most frequently say are "missing" from error reports. Every SaaS captures HTTP method and headers. We currently don't
- **Effort:** 1 day
- **Impact:** Parity +++ (closes the biggest context gap vs. SaaS)
- **Implemented:** HTTP method, hostname, content type, request duration captured via migrations + ErrorContext value object

---

## Deep Introspection — Ruby VM-Level Capabilities

> **Full analysis**: See [DEEP_INTROSPECTION_ANALYSIS.md](DEEP_INTROSPECTION_ANALYSIS.md) for complete research including competitive analysis, implementation architecture, benchmarks, and sources.

These features use Ruby's VM-level APIs and TracePoint to capture context that **no other error tracker** provides. The research validates that these are production-safe — Sentry ships TracePoint(:raise) globally, and all system health APIs are read-only with <1ms overhead.

### The Killer Combination (Our Unique Differentiator)

No existing tool — not Sentry, not New Relic, not Datadog — combines **all of these** in a single, self-hosted gem:
- Local variables at raise point + instance variables of `self`
- Exception cause chain (root cause detection)
- System health snapshot (GC, memory, connection pool, threads, Puma)
- Breadcrumb trail (SQL, cache, controller actions, log messages)
- Zero-config user context via CurrentAttributes
- Swallowed exception detection (Ruby 3.3+)

**What the developer sees** (unified error report):
```
Error: NoMethodError — undefined method 'email' for nil
  at app/controllers/users_controller.rb:42 in `show`

Local Variables:
  user_id = 123
  user = nil                    <- THE BUG
  format = "html"

Cause Chain:
  1. NoMethodError: undefined method 'email' for nil
  2. ActiveRecord::RecordNotFound: Couldn't find User with id=123  (ROOT CAUSE)

Instance Variables (@self = UsersController):
  @current_user = User#1 (admin@example.com)
  @_request = GET /users/123

Breadcrumbs (last 15 events):
  12:00:01.001  [sql]     SELECT "users".* FROM "users" WHERE id = 1  (0.3ms)
  12:00:01.005  [ctrl]    UsersController#show started
  12:00:01.010  [sql]     SELECT "users".* FROM "users" WHERE id = 123  (0.2ms, 0 rows)
  12:00:01.012  [log]     WARN: User 123 not found
  12:00:01.015  [raise]   ActiveRecord::RecordNotFound at user.rb:15
  12:00:01.016  [rescue]  Rescued at users_controller.rb:38  <- SWALLOWED!
  12:00:01.018  [raise]   NoMethodError at users_controller.rb:42

System Health:
  Memory: 412 MB RSS | GC: 7 major, 35 minor | heap_free: 132,000
  DB Pool: 3/15 busy | 0 waiting | 0 dead
  Puma: 2/5 threads busy | backlog: 0

Environment:
  Ruby 3.3.0 | Rails 7.1.3 | Server: web-1 (PID 12345)
  User: Current.user = User#1 (admin@example.com)
  Request: POST /users/123 (18ms, db: 0.5ms)
```

### K. Local Variable Capture at Raise Point (TracePoint :raise) — DONE (v0.4.0)
- **What:** Enable `TracePoint.new(:raise)` to capture `tp.binding.local_variables` at the exact moment an exception is raised. Store on the exception object as inspected strings (never hold Binding references). Display on error detail page
- **Why:** The single most impactful debugging feature. Sentry is the **only** SaaS offering this — they shipped it in production ([PR #1580](https://github.com/getsentry/sentry-ruby/pull/1580), [PR #1589](https://github.com/getsentry/sentry-ruby/pull/1589)) and measured 3.53x slowdown on exception raising — but since exceptions are rare, real-world impact was "not observable" after a week of production testing. **Faultline also ships this** (their v0.1.0 has it on by default)
- **Implementation:**
  - Opt-in: `config.capture_local_variables = false` (default off, like Sentry)
  - **Two modes (learned from Faultline):**
    - **Efficient mode (default):** Single `:raise` TracePoint only (Sentry pattern). Captures locals at raise point. Misses app-code context when exceptions originate in gems
    - **Detailed mode (opt-in):** Dual `:line` + `:raise` TracePoint (Faultline pattern). `:line` tracks last app-code binding on every line. When `:raise` fires in gem code (e.g., `ActiveRecord::RecordNotFound`), falls back to the last app binding. Shows variables from the user's code that *triggered* the error, not gem internals. Higher overhead but more useful context
  - Filter to app code: `next unless tp.path&.start_with?(Rails.root.to_s)`
  - Skip system exceptions: `SystemExit`, `SignalException`, `Interrupt`
  - Skip re-raises: check `instance_variable_defined?(:@_red_locals)` (Sentry pattern)
  - Extract immediately, truncate to 200 chars, never store Binding (prevents GC leaks)
  - **Critical**: Use `Rails.application.config.filter_parameters` to scrub sensitive values
  - **Variable serializer (learned from Faultline):** Implement circular reference detection (thread-local `Set` of `object_id`s), depth limit (4), array limit (20), hash limit (30), auto-filter sensitive variable *names* (password, secret, token, api_key, etc.)
- **Effort:** 2-3 days
- **Impact:** Differentiation +++ (game-changing for debugging)

### L. Exception Cause Chain Analysis (Root Cause Detection) — DONE
- **What:** Walk `Exception#cause` chain (Ruby 2.1+) to find root cause. Display as collapsible chain on error page. Auto-label: "Surface error: ActionView::Template::Error → Root cause: PG::ConnectionBad (3 levels deep)"
- **Why:** Developers fix the surface error without seeing the root cause. The chain reveals hidden issues. **Zero overhead** — just walking object references, no TracePoint needed
- **Implementation:** Walk `exception.cause` with max depth 10. If TracePoint locals were captured, include locals at each cause level. Add `cause_chain` JSONB column
- **Effort:** 1 day (half day without UI)
- **Impact:** Debugging value ++ (zero overhead, high value)
- **Implemented:** `CauseChainExtractor` service walks cause chain (max depth 5, circular detection), stored as JSON in `exception_cause` column

### M. Instance Variable Capture on `self` — DONE (v0.4.0)
- **What:** At raise point, capture `tp.self.instance_variables` with safe truncation. Show: "The controller had `@user = User#42`, `@order = nil`"
- **Why:** Combined with locals, gives complete object state. Like `better_errors` in development, but production-safe
- **Implementation:** Same TracePoint as K (no additional overhead). Filter sensitive names (`@password`, `@token`, `@secret`). Truncate each value to 200 chars. Configurable via `config.capture_instance_variables = false`
- **Effort:** Half day (additive to K)
- **Impact:** Debugging value ++

### N. Swallowed Exception Detection (TracePoint :rescue, Ruby 3.3+) — DONE (v0.4.0)
- **What:** Subscribe to `:rescue` TracePoint to track silently rescued exceptions. Build a "Swallowed Exceptions" dashboard showing exceptions raised frequently but never reaching the error handler
- **Why:** **No competitor detects this.** Silent `rescue => e; nil; end` hides real problems. Example output: "NoMethodError raised 500/hr, 497 silently rescued at `payment_processor.rb:89`"
- **Implementation:**
  - `TracePoint.new(:rescue)` stores rescue location on exception via `@_red_rescues` instance variable
  - Compare raise vs rescue counts per exception class per location
  - Aggregate hourly, show on dedicated dashboard tab
  - Requires Ruby 3.3+ (version gate with `RUBY_VERSION >= "3.3"`)
  - Note: Ruby uses `tp.raised_exception` (not `tp.rescued_exception`) for both events
- **Effort:** 2-3 days (including dashboard UI)
- **Impact:** Novel +++ (genuinely unique — no competitor has this)

### O. Process Crash Capture (at_exit hook) — DONE (v0.4.0)
- **What:** Register `at_exit` hook to capture fatal exception (`$!`), GC state, thread state. Write to disk synchronously (DB may be unavailable during crash). Import on next boot
- **Why:** Last safety net for process-killing errors. Does NOT run on `exit!` or `SIGKILL`
- **Implementation:** `at_exit { capture_crash($!) if $! && !($!.is_a?(SystemExit) && $!.success?) }`
- **Effort:** Half day
- **Impact:** Reliability ++

### P. On-Demand Diagnostic Dump — DONE (v0.4.0)
- **What:** `Signal.trap("USR1")` generates full diagnostic snapshot (threads, GC, memory, pools, recent errors) to `/tmp/`. Zero overhead until triggered
- **Why:** Standard Unix practice (Puma, Sidekiq, Unicorn all do this). Operators send `kill -USR1 <pid>` during incidents
- **Implementation:** Signal handler sets a flag, background thread collects and writes JSON. Dashboard can display the dump
- **Effort:** Half day
- **Impact:** Operational value ++

### Q. Method Complexity Analysis at Error Point — ICEBOX
- **What:** Use `RubyVM::InstructionSequence.of(method).disasm` to report complexity of the failing method (instruction count, branch count, call count). MRI-only
- **Why:** Complex methods cluster errors. Surfacing complexity helps prioritize refactoring
- **Effort:** 1 day
- **Impact:** Unique + (niche)
- **Status:** Moved to ICEBOX — niche feature, will revisit when there's user demand

### R. Rack Attack Event Tracking — DONE (v0.4.0)
- **What:** Subscribe to `throttle.rack_attack` and `blocklist.rack_attack` instrumentation events. Show throttled/blocked requests alongside errors on a dedicated panel. Correlate rate-limit events with error spikes
- **Why:** Rate-limited users often trigger errors immediately after. Seeing "429 throttled 50 times then 500 errors spiked" reveals causation. Rack Attack already emits AS::Notifications events — zero integration cost
- **Implementation:** `ActiveSupport::Notifications.subscribe("throttle.rack_attack")`, guard with `defined?(Rack::Attack)`, store as breadcrumbs or dedicated counter
- **Effort:** Half day
- **Impact:** Operational + (useful if Rack Attack is installed)

### S. ActionCable Connection Monitoring -- DONE (v0.5.0)
- **What:** Track WebSocket connection counts, channel actions, transmissions, subscription confirmations/rejections. Surface ActionCable health alongside errors
- **Why:** WebSocket connection exhaustion causes cascading failures in apps with real-time features. No error tracker surfaces this data
- **Implementation:** `ActionCableSubscriber` subscribes to 4 AS::Notifications events as breadcrumbs. `SystemHealthSnapshot` captures live connection count + adapter. Dashboard page at `/errors/actioncable_health_summary`
- **Config:** `enable_actioncable_tracking = true` (requires `enable_breadcrumbs = true`)
- **Shipped:** v0.5.0 (March 24, 2026)

### T. Zeitwerk Loading Error Capture
- **What:** Capture `Zeitwerk::NameError` events during `eager_load!` — when a file doesn't define the expected constant. Surface on a "Boot Errors" panel
- **Why:** Autoloading errors are silent in development (lazy loading) but crash in production (eager loading). Catching them at boot and surfacing them prevents deploy surprises
- **Implementation:** Guard with `defined?(Zeitwerk)`, register callback via `Rails.autoloaders.main.on_load` or rescue `Zeitwerk::NameError`
- **Effort:** Half day
- **Impact:** Reliability + (prevents deploy surprises)

### U. ActiveStorage Service Health
- **What:** Check storage service reachability (`ActiveStorage::Blob.service.exist?` with a known key) and capture blob stats. Surface storage health on the system health panel
- **Why:** Storage service failures (S3 outage, disk full, permission issues) cause errors that are hard to diagnose without service health context
- **Implementation:** Guard with `defined?(ActiveStorage)`, read service config, attempt lightweight health check. Add to diagnostic dump
- **Effort:** Half day
- **Impact:** Operational + (useful for apps with file uploads)

### V. Production Code Path Coverage
- **What:** Use Ruby's `Coverage.setup(oneshot_lines: true)` (near-zero ongoing overhead) combined with `Coverage.suspend/resume` (Ruby 3.2+) to track which code paths were executed before an error occurred. Show "executed lines" overlay on source view
- **Why:** Knowing exactly which lines ran before a crash narrows debugging scope dramatically. `oneshot_lines` mode fires each line callback only once, making it practical for production
- **Implementation:** Enable in diagnostic mode only. Suspend/resume around error capture. Store as compact bitset per file. **Caveat:** Coverage is process-global (not thread-local), so results may blend in multi-threaded Puma. Best for diagnostic/single-threaded use
- **Effort:** 2-3 days
- **Impact:** Debugging ++ (unique, no competitor has this)

### W. YJIT Runtime Stats — DONE (v0.4.0)
- **What:** Capture `RubyVM::YJIT.runtime_stats` (Ruby 3.1+) at error time — JIT code region size, compilation count, cache invalidations. Surface on system health panel
- **Why:** YJIT invalidations can cause sudden performance degradation that correlates with error spikes. Seeing "YJIT invalidation count jumped 10x" alongside errors reveals JIT-related regressions
- **Implementation:** Guard with `defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?`, read `runtime_stats`. Add to system health snapshot and diagnostic dump
- **Effort:** Half day
- **Impact:** Operational + (useful for YJIT-enabled apps)

### X. RubyVM Cache Health — DONE (v0.4.0)
- **What:** Capture `RubyVM.stat` — `global_method_state`, `global_constant_state`, `class_serial`. Detect rapidly incrementing counters that indicate hot-path monkey-patching invalidating all method/constant caches
- **Why:** Method cache invalidation is a subtle performance killer. If `global_method_state` jumps rapidly, something is redefining methods in a hot path — this causes all cached method lookups to be re-resolved
- **Implementation:** Read `RubyVM.stat` in system health snapshot. Track delta between captures to detect rapid invalidation
- **Effort:** Half day
- **Impact:** Debugging + (niche but diagnostic)

### Z. Performance Monitoring (Request Timing and SQL Analysis)
- **What:** Lightweight request performance tracking using `ActiveSupport::Notifications`. Subscribe to `process_action.action_controller` for total request time, view time, and DB time. Subscribe to `sql.active_record` for query counts and slow query detection. Aggregate into a "Performance" dashboard page showing: slowest endpoints, request duration percentiles (p50/p95/p99), slow query patterns, and request throughput over time
- **Why:** findbug (competitor) has performance monitoring as a key differentiator. We already subscribe to AS::Notifications for breadcrumbs, so extending to performance metrics is a natural evolution with minimal additional overhead. This turns the gem from "error tracking" into "error tracking + performance monitoring," which is how Sentry, New Relic, and Datadog position themselves
- **Implementation:**
  - Opt-in: `config.enable_performance_monitoring = false` (default off)
  - Reuse existing breadcrumb AS::Notifications infrastructure (breadcrumb subscribers already capture SQL, controller, and cache events)
  - New `PerformanceSample` model with: controller, action, method, status, total_duration, db_duration, view_duration, allocations, query_count, timestamp
  - Sampling: configurable `config.performance_sampling_rate = 0.1` (sample 10% of requests by default to minimize storage)
  - Dashboard page at `/errors/performance` with: slowest endpoints table, duration distribution chart, request volume over time, slow query patterns
  - Per-error correlation: link performance data to errors occurring in slow requests
  - **Storage budget:** Use same retention policy as errors. With 10% sampling and 90-day retention, a 100 req/s app stores ~77M rows/90 days. Consider rollup tables for aggregation
- **Effort:** 3-4 days
- **Impact:** Differentiation +++ (closes gap with findbug, positions us alongside Sentry/New Relic)
- **Host app safety:** Sampling keeps overhead minimal. Subscriber is async, never blocks the request. Ring buffer pattern from breadcrumbs proven safe. Budget: <0.1ms per sampled request

### Y. Lazy Backtrace via Thread.each_caller_location (Ruby 3.2+)
- **What:** Use `Thread.each_caller_location` (Ruby 3.2+) as a more efficient alternative to `caller_locations`. Stops iterating after finding the first app-code frame instead of generating the full backtrace
- **Why:** `caller_locations` generates the entire call stack as an array. `Thread.each_caller_location` is lazy — it yields frames one by one and can stop early. For deep stacks (100+ frames), this reduces allocation and speeds up app-frame detection
- **Implementation:** Guard with Ruby version check. Use in `LocalVariableCapturer` and `SwallowedExceptionTracker` for faster app-frame filtering
- **Effort:** Half day
- **Impact:** Performance + (optimization, not user-facing)

### Performance Budget for Deep Introspection

All overhead numbers validated against Sentry's production benchmarks and Ruby documentation.

| Feature | Normal Operation | During Error | Production Safe? | Evidence |
|---------|-----------------|-------------|-----------------|----------|
| TracePoint :raise (locals) | ~0% | 3.53x on raise (~μs) | **Yes** | Sentry ships globally, tested 1 week+ in prod |
| TracePoint :rescue | ~0% | Same as :raise | **Yes** | Same frequency profile as :raise |
| Exception#cause chain | 0% | Negligible (pointer walk) | **Yes** | Pure Ruby, no allocation |
| Instance variables on self | 0% | <0.1ms with truncation | **Yes** | Read-only object inspection |
| System health snapshot | 0% | <1ms (all read-only APIs) | **Yes** | GC.stat, pool.stat are instant |
| Breadcrumbs (AS::Notifications) | <0.01ms/event | 0% (already collected) | **Yes** | Events already fired by Rails |
| CurrentAttributes capture | 0% | <0.1ms (thread-local read) | **Yes** | Read-only, per-thread |
| at_exit hook | 0% | N/A (process dying) | **Yes** | Standard Ruby pattern |
| Signal handler | 0% until triggered | ~100ms for snapshot | **Yes** | Standard Unix practice |
| RubyVM::InstructionSequence | 0% | ~1ms (read-only) | **Yes** | MRI only |
| Rack Attack event tracking | <0.01ms/event | 0% (already collected) | **Yes** | Events already fired by Rack Attack |
| ActionCable connection count | 0% | <0.1ms | **Yes** | Read-only connection list |
| YJIT runtime stats | 0% | <0.1ms | **Yes** | Read-only, Ruby 3.1+ |
| RubyVM.stat | 0% | <0.01ms | **Yes** | Read-only, instant |
| Coverage oneshot_lines | Near-zero after first fire | N/A (diagnostic mode) | **Conditional** | Process-global, not thread-safe |

**Total overhead for ALL always-on features during error**: < 2ms
**Total overhead for breadcrumb collection during normal requests**: < 0.1ms/request

---

## Tier 1 — High Impact, Builds Credibility (do these first)

### 1. JSON API — ICEBOX
- **What:** Add RESTful JSON endpoints for errors CRUD, stats, and applications
- **Why:** This is the #1 gap. Without an API, no external tool can integrate — no CI/CD checks ("fail deploy if error spike"), no custom dashboards, no mobile app, no Zapier/n8n webhooks. Every SaaS competitor has this. It also unblocks many features below
- **Community impact:** Enables an entire ecosystem of integrations. Developers who need programmatic access currently have zero options with self-hosted Rails gems
- **Effort:** 2-3 days
- **Status:** Moved to ICEBOX — will revisit when there's user demand

### 2. Breadcrumbs (Activity Trail Before Error)
- **What:** Capture the last N events (HTTP requests, SQL queries, cache operations, log entries, job enqueues) that happened before an error occurs. Display as a timeline on the error detail page
- **Why:** This is the single most-loved feature in Sentry and Honeybadger. It answers the question every developer asks: *"What happened right before this crashed?"* Rails makes this easy via `ActiveSupport::Notifications` — the instrumentation hooks already exist
- **Community impact:** Genuine differentiator vs. Solid Errors and Faultline, neither of which have breadcrumbs. The kind of feature that makes people tweet about a tool
- **Effort:** 2-3 days

### 3. Deploy/Release Tracking
- **What:** Add `config.current_release` (git SHA, version tag, or custom string). Track which release each error first appeared in. Show a "New in this release" badge. Add a releases timeline view
- **Why:** Rollbar and Bugsnag built their brands on this. Developers want to answer: *"Did this deploy introduce new errors?"* and *"Is this release stable?"* The gem already captures `git_sha` in error context — this is about surfacing it as a first-class concept
- **Community impact:** Release tracking is a top-3 feature request across all error tracking discussions. Self-hosted tools rarely have it
- **Effort:** 2 days

### 4. Notification Rules & Throttling — DONE
- **What:** Replace "all errors trigger all notifications" with configurable rules: alert on first occurrence only, alert when threshold exceeded (5+ in 5 min), alert by severity, per-error-type suppression, notification cooldown periods. Add per-error `last_notified_at` timestamp and configurable cooldown (default 5 min)
- **Why:** Alert fatigue is the #1 complaint about error tracking tools. Without throttling, a single bug in a hot endpoint generates hundreds of Slack messages. Every SaaS competitor has this. Faultline already ships with per-error cooldown, threshold alerts (10/50/100/500/1000), critical exception override, and environment gating
- **Community impact:** Separates "toy" from "production-ready" in most developers' minds
- **Effort:** 1-2 days
- **Implemented:** `NotificationThrottler` service — severity minimum filter, per-error cooldown (5 min default), threshold milestones (10/50/100/500/1000). In-memory Mutex-protected, fail-open, zero DB changes

### 4a. Auto-Reopen Resolved Errors on Recurrence — DONE
- **What:** When a new exception matches the fingerprint of a resolved error, auto-transition it back to `new` status instead of creating a duplicate record. Add `recently_reopened?` method. Include special "reopened" messaging in notifications
- **Why:** Currently `find_or_increment_by_hash` only searches `unresolved` errors, creating duplicate records when resolved errors recur. Faultline, Sentry, and Honeybadger all auto-reopen. This is the expected behavior for error tracking tools
- **Community impact:** Prevents duplicate error records, gives developers clear signal that a "fixed" bug is back
- **Learned from:** Faultline comparison (their `ErrorGroup.find_or_create_from_exception` searches all statuses)
- **Effort:** Half day
- **Implemented:** `FindOrIncrementError` searches unresolved → resolved/wont_fix → create new. Preserves full history, sends reopen notifications, dispatches `:on_error_reopened` plugin event

### 4b. Flexible Authentication (Devise/Warden/Custom Lambda) — DONE
- **What:** Add `config.authenticate_with` lambda support alongside existing HTTP Basic auth. Execute via `instance_exec` for controller context access. Keep HTTP Basic as default for backward compatibility
- **Why:** HTTP Basic Auth with a single shared password doesn't work for real teams. Faultline's lambda-based auth supports Devise, Warden, and fully custom auth with zero hard dependencies
- **Community impact:** Unblocks adoption for any app using Devise (majority of Rails apps)
- **Learned from:** Faultline's `authenticate_with = ->(request) { ... }` pattern via `instance_exec`
- **Effort:** 1 day
- **Implemented:** `config.authenticate_with` lambda runs in controller context via `instance_exec`. Returns truthy to allow access, falsy for 403 Forbidden. Falls back to HTTP Basic Auth when nil

### 4c. Custom Fingerprint Lambda — DONE
- **What:** Add `config.custom_fingerprint = ->(exception, context) { ... }` that returns a hash merged into the fingerprint components. Allow users to customize error grouping without modifying gem internals
- **Why:** Faultline ships this. Power users need control over grouping — e.g., group by tenant, or ignore line numbers for certain error types
- **Learned from:** Faultline comparison
- **Effort:** Half day
- **Implemented:** `config.custom_fingerprint` lambda receives `(exception, context)`, returns String used as fingerprint. Validated in `validate!`

### 5. Data Retention & Cleanup — DONE
- **What:** Configurable retention policies — auto-delete errors after N days via background job. Batch deletion (`in_batches(of: 1000).delete_all`) to prevent table locks. Rake task for manual cleanup. Verify task integration
- **Why:** `retention_days` defaults to 90 days. In production, the error_logs table would grow unbounded without enforcement. Self-hosted tools must handle their own data lifecycle. GlitchTip uses the same pattern (`GLITCHTIP_MAX_EVENT_LIFE_DAYS`)
- **Community impact:** Every production deployment will eventually hit this. Having it from day one signals maturity
- **Effort:** 1 day
- **Implemented:** `RetentionCleanupJob` with batch deletion (dependents pre-deleted, then errors in 1000-record batches). Default 90-day retention. `rails error_dashboard:retention_cleanup` rake task with confirmation prompt. Verify task checks retention policy. Scheduling guidance in initializer template

### 5a. BRIN Index + Functional Index for Time-Series Queries (PostgreSQL) — DONE
- **What:** Add conditional migration that uses BRIN index on `occurred_at` for PostgreSQL (72KB vs 676MB for B-tree, near-identical time-range query performance). Add functional index on `date_trunc('day', occurred_at)` to speed up Groupdate queries by up to 70x
- **Why:** Error logs are insert-heavy, naturally time-ordered data — the exact use case BRIN indexes are designed for. Our DashboardStats makes 7+ COUNT queries per page load; AnalyticsStats does `group_by_day` over 30 days. These indexes make both instant. Zero runtime dependency, just smarter indexing
- **Community impact:** Dashboard stays responsive at 100K+ rows without any user configuration
- **Learned from:** Time-series database research. See [TIMESERIES_ANALYSIS.md](TIMESERIES_ANALYSIS.md)
- **Effort:** Half day
- **Implemented:** Migration adds BRIN index on `occurred_at` + functional index for Groupdate (PostgreSQL only, graceful SQLite fallback)

---

## Tier 2 — Competitive Parity Features (close the gap with SaaS)

### 6. User Impact Scoring
- **What:** Surface "this error affected 847 unique users in the last 24 hours" prominently. Rank errors by user impact, not just occurrence count. Show affected user trend over time
- **Why:** The gem already captures `user_id` with errors — this is about aggregating and surfacing it. Sentry and Honeybadger both highlight user impact as a key prioritization metric. An error hitting 1 user 1000 times is very different from an error hitting 1000 users once each
- **Community impact:** Helps teams prioritize what to fix first. Directly translates to business value
- **Effort:** 1 day

### 7. Smarter Error Grouping Controls
- **What:** Allow custom fingerprinting rules (user-provided lambda/proc for grouping). Add a "merge errors" UI action. Add a "split error" action for over-grouped errors. Show grouping confidence score
- **Why:** Error grouping is either too aggressive (lumps unrelated errors) or too loose (same error appears as 50 entries). Sentry lets users define custom fingerprints. The gem's current SHA256 hash approach is good but not user-tunable
- **Community impact:** Power users care deeply about this. Frequent source of complaints with every error tracker
- **Effort:** 2-3 days

### 7a. Telegram Notifications
- **What:** Add Telegram Bot API integration for error notifications. Configure with `config.enable_telegram_notifications = true` and `config.telegram_bot_token` / `config.telegram_chat_id`. Send formatted error alerts to Telegram channels or groups
- **Why:** Faultline has Telegram and we don't. Telegram is the dominant messaging platform in Eastern Europe, CIS countries, and parts of Asia. Adding it closes a competitive gap and opens the gem to a large developer community
- **Implementation:** `TelegramErrorNotificationJob` using the Telegram Bot API (`https://api.telegram.org/bot<token>/sendMessage`). No gem dependency needed, just HTTP POST via `Net::HTTP` (already in stdlib). Format with Markdown, include error type, message, URL, and severity badge
- **Effort:** Half day
- **Impact:** Adoption ++ (closes gap with faultline, reaches new developer communities)

### 8. GitHub/GitLab Issue Creation
- **What:** One-click "Create GitHub Issue" from the error detail page. Pre-fill with error details, backtrace, context. Link back to the error in the dashboard. Track issue status
- **Why:** Faultline (a direct competitor) already has this and it's likely contributing to their faster star growth (64 vs 28). This bridges the gap between "I see the error" and "I'm working on it"
- **Community impact:** Most-requested integration across all error tracking tools. Natural next step after "see error -> assign error"
- **Effort:** 1-2 days

### 9. Environment/Stage Awareness
- **What:** Track which environment errors come from (development/staging/production). Filter by environment. Show environment badge on errors. Separate notification rules per environment
- **Why:** Currently there's no concept of environment — all errors are treated equally. In practice, a staging error is very different from a production error. Every SaaS competitor separates these
- **Community impact:** Any team with staging + production environments needs this
- **Effort:** 1 day

### 10. Reduce Runtime Dependencies — DONE
- **What:** Make `turbo-rails`, `browser`, `httparty`, and `chartkick` optional. Core gem should only require `pagy` and `groupdate`. Load optional features only if the dependency is available
- **Why:** 9 runtime dependencies is a red flag for production Rails apps. Solid Errors has zero extra dependencies. Every unnecessary dependency is a potential version conflict, security surface, and bundle bloat
- **Community impact:** Dependency count is one of the first things experienced Rails developers check before adding a gem. Reducing from 9 to 2-3 required deps significantly lowers the adoption barrier
- **Effort:** 1 day
- **Implemented:** Reduced from 9 required to 2 (pagy, groupdate). browser, httparty, chartkick, turbo-rails are optional with graceful degradation

---

## Tier 3 — Polish & Production Hardness

### 11. RBAC (Role-Based Access Control)
- **What:** Add roles: admin (full access), developer (resolve/comment/assign), viewer (read-only). Support multiple credential sets. Build on top of the flexible auth system added in v0.2 (item 4b)
- **Why:** The v0.2 flexible auth (Devise/Warden/lambda) handles authentication and basic authorization. RBAC adds granular permission levels on top. Currently all authenticated users have full delete/resolve/modify access
- **Community impact:** Required for any team larger than a solo developer. Blocker for enterprise adoption
- **Note:** Basic auth flexibility (Devise/Warden/custom lambda) was accelerated to v0.2 based on Faultline comparison
- **Effort:** 2-3 days

### 12. Audit Logging
- **What:** Track who resolved, deleted, assigned, or commented on errors. Show audit trail on each error
- **Why:** In a team environment, accountability matters. When an error is re-opened, you need to know who resolved it and when
- **Community impact:** Standard expectation for any production tool that modifies state
- **Effort:** 1 day

### 13. Scheduled Digests
- **What:** Daily/weekly email digest summarizing: new errors, top errors by impact, resolution rate, MTTR trends. Configurable schedule and recipients
- **Why:** Not everyone lives in the dashboard. A morning email saying "12 new errors yesterday, 3 critical, MTTR improved 20%" keeps the team informed without context-switching
- **Community impact:** Low-effort, high-visibility feature that makes the gem feel "enterprise-ready"
- **Effort:** 1-2 days

### 14. Health Check Endpoint
- **What:** Add `/error_dashboard/health` that returns JSON with: database connectivity, error count, last error timestamp, queue status
- **Why:** "Who watches the watchmen?" If the error dashboard itself is broken, you need to know
- **Community impact:** Small feature, big signal of production maturity
- **Effort:** Half day

### 15. Performance Fixes
- **What:** Fix the N+1 query in `top_errors_by_impact` (calls `ErrorLog.find()` in a loop). Batch user email lookups in analytics. Add database partitioning guidance for large tables
- **Why:** The dashboard will get slow at scale. The N+1 in the main dashboard stats query is the most critical
- **Community impact:** Performance issues are discovered at the worst time (when you have lots of errors to look at)
- **Effort:** 1 day

---

## Tier 4 — Differentiators (stand out from the crowd)

### 16. AI-Powered Error Summaries
- **What:** Optional integration with OpenAI/Anthropic API to generate plain-English summaries of errors: "This NoMethodError on line 42 of users_controller.rb is likely caused by a nil user object when the session expires"
- **Why:** Sentry launched "Seer" for AI-assisted grouping and it's their most talked-about feature. For a self-hosted gem, even a simple "summarize this error" button using the user's own API key would be genuinely useful and highly shareable
- **Community impact:** Would generate significant buzz. "Self-hosted error tracking with AI summaries" is a headline that writes itself
- **Effort:** 2-3 days

### 17. Error Replay (Request Reproduction) — DONE
- **What:** Capture enough request context (method, path, headers, params, body) to generate a reproducible curl command or RSpec request spec. One-click "Copy as curl" or "Copy as test"
- **Why:** The hardest part of fixing an error is reproducing it. If the dashboard can hand you a ready-to-run curl command, that's a massive time-saver. No competitor does this well
- **Community impact:** Genuinely novel feature that would differentiate from every competitor
- **Effort:** 2 days
- **Status:** Fully implemented — `CurlGenerator` + `RspecGenerator` services with copy-to-clipboard buttons on error detail page

### 18. Inline Error Resolution (Fix Suggestions)
- **What:** For common error patterns (nil method calls, missing keys, type mismatches), show a suggested fix with the relevant code snippet
- **Why:** Goes beyond "here's the error" to "here's how to fix it." Could be done with pattern matching (no AI needed) for the top 20 error types
- **Community impact:** Turns the dashboard from a monitoring tool into a debugging assistant
- **Effort:** 2-3 days

### 19. Comparison Mode
- **What:** Compare two time periods side-by-side: "This week vs last week" — new errors, resolved errors, error rate change, MTTR change
- **Why:** Trend analysis is more actionable than point-in-time stats
- **Community impact:** Useful for sprint retros and weekly standups
- **Effort:** 1-2 days

### 20. Webhook Signature Verification (HMAC)
- **What:** Sign outbound webhook payloads with HMAC-SHA256 so receivers can verify authenticity
- **Why:** Without signatures, anyone who discovers the webhook URL can send fake error notifications. Standard practice for production webhooks
- **Community impact:** Security-conscious teams won't use unsigned webhooks
- **Effort:** Half day

---

## Tier 5 — Community & Growth (not code, but critical)

### 21. Submit to awesome-ruby
- The [awesome-ruby](https://github.com/markets/awesome-ruby) list is the most-referenced curated list for Ruby gems
- Not being on it means most developers will never discover the gem
- **Single highest-leverage action for visibility**

### 22. Submit to Ruby Toolbox
- Ruby Toolbox categorizes gems and shows comparative stats
- Being listed under "Exception Notification" alongside exception_notification, solid_errors, and airbrake would immediately surface the gem

### 23. Write a Launch Blog Post
- "Why I built a self-hosted error dashboard for Rails" on dev.to or Medium
- Include comparison table vs. Solid Errors vs. Sentry self-hosted
- Show screenshots, link to live demo
- This is how gems get their first 100 stars

### 24. Fix Default Credentials Warning
- Raise an error on startup if `dashboard_username` is still "gandalf" and `dashboard_password` is still "youshallnotpass" in production
- Users will ship with demo credentials — this is a security issue that will come up in every code review

---

## Priority Matrix & Release Plan

### Implementation Phases

Each phase builds on the previous. Phase 1 features are quick wins (hours each). Phase 3-4 are the game-changers that differentiate us from every competitor.

| Priority | Feature | Effort | Impact | Phase |
|----------|---------|--------|--------|-------|
| **NOW** | Submit to awesome-ruby & Ruby Toolbox | 1 hour | Visibility +++ | Community |
| **NOW** | Fix default credentials warning | 1 hour | Trust +++ | Community |
| **NOW** | Write launch blog post | 4 hours | Awareness +++ | Community |
| | | | | |
| ~~**v0.2**~~ | ~~Exception cause chain (L)~~ | ~~2-3 hours~~ | ~~Debugging ++~~ | ~~Phase 1: Quick Wins~~ **DONE** |
| ~~**v0.2**~~ | ~~Enriched error context (J) — method, headers, hostname, timing~~ | ~~4-6 hours~~ | ~~Parity +++~~ | ~~Phase 1~~ **DONE** |
| ~~**v0.2**~~ | ~~Structured backtrace (use `backtrace_locations`)~~ | ~~2-3 hours~~ | ~~Quality ++~~ | ~~Phase 1~~ **DONE** |
| ~~**v0.2**~~ | ~~Environment info — Ruby, Rails, gem versions at boot~~ | ~~2-3 hours~~ | ~~Context ++~~ | ~~Phase 1~~ **DONE** |
| ~~**v0.2**~~ | ~~Auto user context via CurrentAttributes (D)~~ | ~~3-4 hours~~ | ~~Zero-config ++~~ | ~~Phase 1~~ **DONE** |
| ~~**v0.2**~~ | ~~Sensitive data filtering (use `filter_parameters`)~~ | ~~4-6 hours~~ | ~~Safety +++~~ | ~~Phase 1~~ **DONE** |
| ~~**v0.2**~~ | ~~Notification rules & throttling (with per-error cooldown)~~ | ~~1-2 days~~ | ~~Production-readiness +++~~ | ~~Phase 1~~ **DONE** |
| ~~**v0.2**~~ | ~~Auto-reopen resolved errors on recurrence~~ | ~~Half day~~ | ~~Correctness +++~~ | ~~Phase 1~~ **DONE** |
| ~~**v0.2**~~ | ~~Custom fingerprint lambda~~ | ~~Half day~~ | ~~Extensibility ++~~ | ~~Phase 1~~ **DONE** |
| **v0.2** | Data retention enforcement (background job, batch delete) | 1 day | Production-readiness ++ | Phase 1 |
| ~~**v0.2**~~ | ~~BRIN index + functional index for PostgreSQL~~ | ~~Half day~~ | ~~Performance +++~~ | ~~Phase 1~~ **DONE** |
| ~~**v0.2**~~ | ~~Reduce dependencies (make optional)~~ | ~~1 day~~ | ~~Adoption barrier --~~ | ~~Phase 1~~ **DONE** |
| ~~**v0.2**~~ | ~~Backtrace line numbers in error detail view~~ | ~~PR #69~~ | ~~UX ++~~ | ~~Community contribution~~ **DONE** |
| ~~**v0.2**~~ | ~~Loading states & skeleton screens (Stimulus)~~ | ~~PR #71~~ | ~~UX +++~~ | ~~Community contribution~~ **DONE** |
| | | | | |
| **ICEBOX** | JSON API | 2-3 days | Extensibility +++ | Deferred |
| ~~**ICEBOX**~~ | ~~Flexible auth (Devise/Warden/custom lambda)~~ | ~~1 day~~ | ~~Adoption +++~~ | ~~Deferred~~ **DONE (v0.3.0)** |
| | | | | |
| **v0.3** | Rollup/summary tables (optional `rollup` gem) | 1-2 days | Performance +++ | Phase 2: System Health |
| ~~**v0.3**~~ | ~~System health snapshot as JSONB column (C)~~ | ~~2-3 days~~ | ~~Differentiation ++~~ | ~~Phase 2~~ **DONE** |
| ~~**v0.3**~~ | ~~System health UI (display in error detail)~~ | ~~1-2 days~~ | ~~UX ++~~ | ~~Phase 2~~ **DONE** |
| | | | | |
| ~~**v0.4**~~ | ~~Breadcrumb collector — ring buffer, thread-local (A)~~ | ~~1-2 days~~ | ~~Foundation +++~~ | ~~Phase 3: Breadcrumbs~~ **DONE** |
| ~~**v0.4**~~ | ~~AS::Notifications subscriber — SQL, controller, cache, jobs~~ | ~~2-3 days~~ | ~~Differentiation +++~~ | ~~Phase 3~~ **DONE** |
| ~~**v0.4**~~ | ~~Logger breadcrumbs~~ | ~~Half day~~ | ~~Context ++~~ | ~~Phase 3~~ **DONE** |
| ~~**v0.4**~~ | ~~Manual breadcrumb API (`RailsErrorDashboard.add_breadcrumb`)~~ | ~~Half day~~ | ~~Extensibility ++~~ | ~~Phase 3~~ **DONE** |
| ~~**v0.4**~~ | ~~Breadcrumb persistence (text column on error_logs)~~ | ~~1 day~~ | ~~Storage ++~~ | ~~Phase 3~~ **DONE** |
| ~~**v0.4**~~ | ~~Breadcrumb timeline UI~~ | ~~2-3 days~~ | ~~UX +++~~ | ~~Phase 3~~ **DONE** |
| ~~**v0.4**~~ | ~~N+1 detection from SQL breadcrumbs (B)~~ | ~~1 day~~ | ~~Differentiation +++~~ | ~~Phase 3~~ **DONE** |
| | | | | |
| ~~**v0.5**~~ | ~~Local variable capture — TracePoint `:raise` (K)~~ | ~~2-3 days~~ | ~~Game-changer +++~~ | ~~Phase 4: TracePoint~~ **DONE (v0.4.0)** |
| ~~**v0.5**~~ | ~~Variable serializer (circular detection, depth limits, sensitive names)~~ | ~~1 day~~ | ~~Safety +++~~ | ~~Phase 4~~ **DONE (v0.4.0)** |
| ~~**v0.5**~~ | ~~Instance variable capture on self (M)~~ | ~~1 day~~ | ~~Debugging ++~~ | ~~Phase 4~~ **DONE (v0.4.0)** |
| **v0.5** | Debugger Inspector UI (side-by-side source + variables) | 1-2 days | UX +++ | Phase 4 |
| ~~**v0.5**~~ | ~~Swallowed exception detection — TracePoint :rescue (N)~~ | ~~2-3 days~~ | ~~Novel +++~~ | ~~Phase 4~~ **DONE (v0.4.0)** |
| ~~**v0.5**~~ | ~~Swallowed exception dashboard UI~~ | ~~2-3 days~~ | ~~UX ++~~ | ~~Phase 4~~ **DONE (v0.4.0)** |
| | | | | |
| **v0.5** | Deploy/release tracking | 2 days | Workflow +++ | Phase 5: Workflow |
| ~~**v0.5**~~ | ~~Error replay — copy as curl/RSpec (E)~~ | ~~1-2 days~~ | ~~Novel +++~~ | ~~Phase 5~~ **DONE (v0.4.0)** |
| **v0.5** | GitHub/GitLab issue creation | 1-2 days | Workflow ++ | Phase 5 |
| **v0.5** | Telegram notifications (7a) | Half day | Adoption ++ | Phase 5 |
| **v0.5** | Optional PostgreSQL partitioning generator | 1-2 days | Scale ++ | Phase 5 |
| **v0.5** | User impact scoring | 1 day | Prioritization ++ | Phase 5 |
| ~~**v0.6**~~ | ~~Process crash capture — at_exit hook (O)~~ | ~~Half day~~ | ~~Reliability ++~~ | ~~Phase 5~~ **DONE (v0.4.0)** |
| ~~**v0.6**~~ | ~~On-demand diagnostic dump (P)~~ | ~~Half day~~ | ~~Operational ++~~ | ~~Phase 5~~ **DONE (v0.4.0)** |
| | | | | |
| ~~**v0.7**~~ | ~~Deprecation warning tracker (F)~~ | ~~1 day~~ | ~~Unique ++~~ | ~~Phase 6: Health Panels~~ **DONE (v0.3.0)** |
| **v0.6** | Missing translation tracking (I18n silent errors) | Half day | Unique ++ | Phase 6 |
| **v0.6** | Validation failure pattern tracking (ActiveModel) | 1 day | Insight ++ | Phase 6 |
| ~~**v0.7**~~ | ~~Background job health panel (G)~~ | ~~1-2 days~~ | ~~Operational ++~~ | ~~Phase 6~~ **DONE (v0.3.1)** |
| ~~**v0.7**~~ | ~~Database health panel (H)~~ | ~~1-2 days~~ | ~~Operational ++~~ | ~~Phase 6~~ **DONE (v0.3.1)** |
| ~~**v0.7**~~ | ~~Cache health monitoring (I)~~ | ~~1 day~~ | ~~Operational +~~ | ~~Phase 6~~ **DONE (v0.3.0)** |
| **v0.6** | Environment awareness | 1 day | Team workflow ++ | Phase 6 |
| ~~**v0.7**~~ | ~~Rack Attack event tracking (R)~~ | ~~Half day~~ | ~~Operational +~~ | ~~Phase 6~~ **DONE (v0.4.0)** |
| **v0.6** | Performance monitoring — request timing, slow queries (Z) | 3-4 days | Differentiation +++ | Phase 6 |
| **v0.6** | ActionCable connection monitoring (S) | Half day | Operational + | Phase 6 |
| **v0.6** | Zeitwerk loading error capture (T) | Half day | Reliability + | Phase 6 |
| **v0.6** | ActiveStorage service health (U) | Half day | Operational + | Phase 6 |
| ~~**v0.7**~~ | ~~YJIT runtime stats (W)~~ | ~~Half day~~ | ~~Operational +~~ | ~~Phase 6~~ **DONE (v0.4.0)** |
| ~~**v0.7**~~ | ~~RubyVM cache health (X)~~ | ~~Half day~~ | ~~Debugging +~~ | ~~Phase 6~~ **DONE (v0.4.0)** |
| | | | | |
| **v0.8** | RBAC | 2-3 days | Enterprise ++ | Phase 7: Enterprise |
| **v0.8** | Audit logging | 1 day | Enterprise ++ | Phase 7 |
| **v0.8** | Scheduled digests | 1-2 days | Engagement ++ | Phase 7 |
| **v0.8** | Adaptive sampling (auto-reduce on spike) | 2-3 days | Resilience ++ | Phase 7 |
| **v0.8** | Optional TimescaleDB generator (hypertables, compression, continuous aggregates) | 2-3 days | Scale +++ | Phase 7 |
| | | | | |
| **v1.0** | Full Context Error Report (unified view) | 3-5 days | Flagship +++ | Phase 8: 1.0 |
| **v1.0** | Error-environment correlation | 3-5 days | Analytics ++ | Phase 8 |
| **v1.0** | AI error summaries | 2-3 days | Buzz +++ | Phase 8 |
| **v1.0** | Comparison mode | 1-2 days | Analytics ++ | Phase 8 |
| **v1.0** | Production code path coverage — Coverage oneshot_lines (V) | 2-3 days | Debugging ++ | Phase 8 |
| **v1.0** | Lazy backtrace — Thread.each_caller_location (Y) | Half day | Performance + | Phase 8 |
| **ICEBOX** | Method complexity analysis (Q) | 1 day | Unique + | Deferred |

---

## Internal Audit Summary (Current Strengths & Weaknesses)

### What's Strong Today
- Error capture & deduplication (9/10) — SHA256 hashing, smart normalization, custom fingerprint, auto-reopen, cause chain
- Error context (9/10) — request (HTTP method, hostname, duration), job, platform, user (CurrentAttributes), git SHA, environment info, sensitive data filtering
- Configuration (9/10) — 100+ options, sensible defaults, env var support, comprehensive validation
- Error lifecycle (8.5/10) — 5 states, assignment, priority, snooze, comments, batch ops, auto-reopen on recurrence
- Notifications (8.5/10) — 5 channels (Slack, Email, Discord, PagerDuty, Webhooks), severity filter, per-error cooldown, threshold milestones, plugin callbacks. Missing: Telegram (planned v0.5)
- Analytics (8/10) — baseline alerts, similar errors, cascades, correlation, patterns
- Search & filtering (8/10) — 11 filters, PostgreSQL full-text search, pagination
- Source code integration (8/10) — source reader, git blame, GitHub links
- Multi-tenancy (8/10) — per-app isolation, auto-detection, shared DB
- Deployment (8/10) — 3-step install, works with Thruster, API-only mode
- Dependencies (9/10) — only 2 required (pagy, groupdate), 4 optional with graceful degradation

### What Needs Work
- API (3/10) — no JSON endpoints at all (ICEBOX)
- User management (7/10) — HTTP Basic Auth + custom lambda (Devise/Warden/session), no RBAC yet
- ~~Local variables (0/10)~~ — **DONE (v0.4.0)** — TracePoint(:raise) locals + instance vars + swallowed detection
- Integrations (6/10) — limited ecosystem, no GitHub issue creation (Faultline has this), no Telegram (Faultline has this), sketch-level plugins
- Performance monitoring (0/10) — no request timing or slow query tracking (findbug has this, planned v0.6)
- Dashboard performance (7.5/10) — no rollup tables, no partitioning guidance. BRIN indexes added. See [TIMESERIES_ANALYSIS.md](TIMESERIES_ANALYSIS.md)
- Testing (9.5/10) — 2636 unit specs, 7 system tests, 1264+ chaos test assertions

### What Was Fixed (v0.2 Quick Wins)
- ~~Auto-reopen (0/10)~~ — Now auto-reopens resolved/wont_fix errors on recurrence
- ~~Notifications (7.5/10)~~ — Now has severity filter, per-error cooldown, threshold milestones
- ~~Request context (7/10)~~ — Now captures HTTP method, hostname, content type, request duration
- ~~Dependencies (6/10)~~ — Reduced from 9 required to 2 (pagy, groupdate) + optional
- ~~Sensitive data~~ — Filters passwords, tokens, credit cards, SSNs by default (24 built-in patterns)
- ~~Error context~~ — Exception cause chain, environment info, CurrentAttributes, custom fingerprint, structured backtrace
- ~~UX~~ — Backtrace line numbers (PR #69), loading states & skeleton screens with Stimulus controller (PR #71)
