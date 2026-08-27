# F — Deep introspection verification (primary-source: vendor Ruby agents cloned and grepped; docs from GitHub docs repos)

## F1 Local variables at raise — TABLE-STAKES
- Sentry sentry-ruby: `include_local_variables` (now `data_collection.stack_frame_variables`), default false, TracePoint(:raise) → `tp.binding.local_variables` — identical mechanism to RED. Free SDK option. https://docs.sentry.io/platforms/ruby/configuration/options/ ; sentry-ruby/lib/sentry-ruby.rb#L67-L81
- Honeybadger: `exceptions.local_variables` via binding_of_caller (incompatible with better_errors). https://docs.honeybadger.io/lib/ruby/gem-reference/configuration/ ; plugins/local_variables.rb
- Rollbar: TracePoint(:call,:return,:b_call,:b_return,:c_call,:c_return,:raise) binding stack, per-frame locals, scrubbed; `locals[:enabled]`. rollbar-gem notifier/trace_with_bindings.rb, item/locals.rb
- Datadog: Dynamic Instrumentation captures locals on demand (not at raise); Exception Replay not for Ruby. Partial.
- Faultline: dual TracePoint(:line)+(:raise), always on, filtered, Ruby ≥3.2 Rails ≥8. Yes.
- Bugsink: renders `frame.vars` from sentry-ruby (free self-hosted). Yes (display).
- No: AppSignal, Bugsnag, Airbrake/Errbit, Raygun, Skylight, RorVsWild, Scout, New Relic, solid_errors, exception_notification, exception_hunter, Telebugs. Dev-only gems: better_errors, exception_details, pretty_backtrace (ko1, TracePoint(:raise)+RubyVM::DebugInspector).
- RED's differentiator = packaging only: opt-in, Rails filter_parameters reuse, size limits, no Binding retention.

## F2 Instance variables of self at raise — UNIQUE-AMONG-TRACKERS
- Sentry: locals only. Honeybadger/Rollbar: bindings captured but only locals exported (Partial-indirect). Faultline: serialises `_ivars` of objects appearing as local values, never `tp.self` (Partial). Datadog DI: `target_self: tp.self`, 20-ivar limit, on demand not at raise (Partial). better_errors/exception_details: yes, dev-only.
- Claim wording: "no *tracker* captures self's instance variables at the raise point"; not "no tool".

## F3 Swallowed exception detection — SHARED-WITH Datadog; aggregate ratio page unique
- **Datadog dd-trace-rb ≥2.16.0 Error Tracking handled errors**: `DD_ERROR_TRACKING_HANDLED_ERRORS=user|third_party|all`; source: "`:rescue` event was added in Ruby 3.3 … event = RubyVersion.is?(">= 3.3") ? :rescue : :raise". Ruby 2.7+ MRI, requires an active APM span; each rescued exception → Error Tracking issue; no raise/rescue ratio aggregate. docs/GettingStarted.md#error-tracking ; lib/datadog/error_tracking/component.rb
- Faultline/solid_errors/Sentry/Honeybadger: only explicit `Rails.error.handle` (Partial). No `:rescue` TracePoint in Sentry/HB/Rollbar/Bugsnag/AppSignal/Airbrake.
- RubyGems search: no runtime gem besides RED (only static: rubocop-swallow-exception, Lint/SuppressedException).
- README "No tool detects silently rescued exceptions" = FALSE. Defensible: only Datadog's paid APM does rescue-level detection (Ruby 3.3+, needs span); RED does it free, without APM, and aggregates raise/rescue ratios by location; no self-hosted/free tracker does it.

## F4 at_exit crash capture — TABLE-STAKES
- Honeybadger `exceptions.notify_at_exit` default true; Bugsnag automatic at_exit UNHANDLED_EXCEPTION; AppSignal `enable_at_exit_reporter` default true (ignores SystemExit/SignalException); Sentry partial (runner only); Airbrake documented recipe; Datadog native crashtracker (covers segfaults — beyond at_exit). No: Rollbar, Raygun, Skylight, RorVsWild, Scout, NR, Faultline, solid_errors, Telebugs.
- RED twist (JSON file → import next boot, GC/uptime attached) = implementation detail.

## F5 On-demand diagnostic dump — SHARED-WITH sigdump/rbtrace/New Relic thread profiler; bundled stored snapshot unique among trackers
- sigdump: SIGCONT → all-thread backtraces + object counts + GC profile to /tmp. rbtrace: attach, backtraces, ObjectSpace. New Relic thread profiler: UI-started, 100ms stack sampling, Ruby agent ≥3.5.5, threads only. AppSignal diagnose = config check; MRI probe = minutely metrics. Puma INFO signal = thread backtraces. Faultline README explicitly excludes "Memory profiling or GC introspection".
- RED reality: no Signal.trap (rule #9); triggers = dashboard button + rake. ROADMAP item P's USR1 wording stale.

## F6 Production code-path coverage in dashboard — UNIQUE-AMONG-TRACKERS
- Coverband: standalone, richer (persisted Redis, per-file %, dead-code review, mountable UI, oneshot mode). deep-cover/simplecov test-time. Zero trackers touch `Coverage.` API.
- Must state constraints: diagnostic mode only, process-global (multi-threaded Puma blends), in-memory peek_result, no persistence.

## F7 Thread.each_caller_location — SHARED-WITH Sentry & Rails core; NOT implemented in RED (0 hits). Do not market.

## README claim checks
(a) "Pay extra for local variable capture (Sentry)" — FALSE. Free SDK boolean; pricing page gates volume only; Bugsink renders the same payload free. Rewrite: "Local variables are opt-in in Sentry's SDK; RED enables local AND instance variables with Rails filter_parameters scrubbing out of the box."
(b) "No tool detects silently rescued exceptions" — FALSE (Datadog). Rewrite as above.
Files to correct: README.md L69-70 and L440 ("No other error tracker does this"); ROADMAP item P (USR1), item V ("no competitor has this" → among trackers only); docs/FEATURES.md swallowed section if it repeats the claim.
