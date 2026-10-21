# Design: Rails 7.0 request capture

## Approach
No capture-path change. At boot, `Configuration#validate!` adds one warning when actionpack is
older than 7.0.10, logged through the same `Rails.logger.warn` loop as the other warnings
(`configuration.rb:1004-1006`). The docs say which Rails versions are affected and that Rails 7.0.10
fixes it. The first design, a 7.0-only reporter, is kept below, marked superseded.

## Evidence (2026-10-19)
- actionpack 7.0.10 backported 7.1's reporting. ShowExceptions sets
  `action_dispatch.report_exception` to `!wrapper.rescue_response?` (`show_exceptions.rb:44`), and
  the Executor reports `action_dispatch.exception` when it is set (`executor.rb:16-19`).
  `debug_exceptions.rb`, `exception_wrapper.rb`, `http/request.rb` and ActiveSupport's
  `error_reporter.rb` are byte-identical to 7.0.8.7. The same two lines are in 7.1.6 and 8.1.4.
- A probe through the dummy app, in a scratch worktree and DB, with `show_exceptions` on:

  | Rails | settings | 500 recorded | 404 recorded |
  |---|---|---|---|
  | 7.0.8.7 | production (detailed off) | 0 | 0 |
  | 7.0.8.7 | development (detailed on) | 0 | 0 |
  | 7.0.10 | production | 1 | 0 |
  | 7.0.10 | development | 0 | 0 |
  | 8.1.4 | production and development | 1 | 1 |

- The 8.1.4 row is the dummy app's `ActionDispatch::Reloader`. It is an Executor subclass below
  DebugExceptions, present because code reloading is on, and it reports every exception that
  passes it (`executor.rb:36`). A production app has no Reloader, so 8.1 production records the 500
  and not the 404, as 7.0.10 does. On 7.0 the Reloader's reports reach no subscriber: the dummy
  stack had a Reloader on 7.0.10 too, and it recorded nothing. Out of scope here.
- Rails 7.0.8.7 does not boot on Ruby 3.4 without `mutex_m`, `bigdecimal`, `base64` and `drb` in
  the Gemfile, which it doesn't declare. Apps on it run Ruby 3.3 or older.

## Decision: point affected apps to Rails 7.0.10, not a RED reporter   (→ REQ-1, REQ-2, REQ-3)

**Context.** The gap affects only Rails 7.0.0–7.0.8.7, all end-of-life, and Rails 7.0.10 fixes it
upstream as a patch release. CI's 7.0 rows install 7.0.10, so they can't exercise a RED fix for
older 7.0 versions.

**Alternatives.**
1. A boot warning plus corrected docs.
2. The first design's interceptor, used only below 7.0.10, with a new CI row pinned to Rails
   7.0.8.7 on Ruby 3.3 or older.
3. Raise RED's minimum Rails to 7.0.10.

**Case for 1.** No new code in the capture path, and no CI row to keep alive for end-of-life
versions. Rails' own fix is a patch-level upgrade. The warning reaches teams that never read
release notes.

**Case against 1.** An app that cannot upgrade Rails still records no request errors, and its boot
log carries the warning every time with no way to silence it.

**Decision.** Option 1, the user's choice (`intake.md`).
**Falsifiability.** We would build option 2 if a user reports that they can't move from Rails 7.0.8.x
to 7.0.10.
**Fired-if.** manual

## Decision: warn from `validate!`, not a dashboard banner   (→ REQ-1, REQ-2)

**Context.** The warning has to reach a team on an affected Rails without touching the capture path.

**Alternatives.**
1. A warning in `Configuration#validate!`, beside the Ruby-version warning for
   `detect_swallowed_exceptions` (`configuration.rb:731-736`).
2. A banner on the dashboard.

**Case for 1.** It's an existing path: one condition, logged at boot through `Rails.logger.warn`,
tested in `configuration_validation_spec.rb`. Version checks against the host's environment
already live there.

**Case against 1.** It's a log line. A team that never reads boot logs won't see it, and the banner
would. A banner costs a view change and a new locale key in eleven languages.

**Decision.** Option 1. The condition is `ActionPack.gem_version < Gem::Version.new("7.0.10")`.
**Falsifiability.** We would add the banner if a user on 7.0.8.x reports missing request errors
after 0.16.1 without having seen the warning.
**Fired-if.** manual

## Superseded on 2026-10-19: the first design, a 7.0-only reporter
The records below were approved with the first version of the spec, before the 7.0.10 finding.
They are superseded by "point affected apps to Rails 7.0.10" above. Their REQ numbers refer to
that first version.

On Rails 7.0 only, RED registers a DebugExceptions interceptor. Rails calls it with the request
and the exception before anything renders. It records the exception straight to RED when Rails
is about to render it rather than re-raise it, unless Rails answers it with a rescue response.
Nothing changes on 7.1+, where the interceptor is never registered. ErrorCatcher stays where it
is and keeps recording what propagates.

Source read for this design: actionpack 7.0.8.7 and 7.1.6, unpacked under the session scratchpad
(`rails_src/r70`, `rails_src/r71`):
- 7.0 `debug_exceptions.rb:12-17`: `interceptors` is one shared array that `register_interceptor`
  appends to. The middleware holds the same array object (default argument at `:19`), so
  registering after the stack is built still takes effect.
- `:36-39`: `invoke_interceptors` runs before `raise exception unless request.show_exceptions?`.
- `:43-52`: an interceptor that raises is rescued and logged.
- 7.0 ShowExceptions renders without reporting (`show_exceptions.rb:30-35`). Executor reports only
  exceptions that propagate (`executor.rb:16-18`).
- 7.1 Executor reports a rendered exception only when `!wrapper.rescue_response?`
  (`show_exceptions.rb:37`, `executor.rb:16-19`).

## Decision: a DebugExceptions interceptor, registered on actionpack < 7.1   (→ REQ-1, REQ-2, REQ-5, REQ-9)

**Superseded** on 2026-10-19 by "point affected apps to Rails 7.0.10".

**Context.** On 7.0 the exception is rendered inside ShowExceptions (production) or DebugExceptions
(development), both below RED's outermost ErrorCatcher. The reporter has to see it before that,
and must never stop a host app from booting or answering.

**Alternatives.**
1. `ActionDispatch::DebugExceptions.register_interceptor`, a public Rails API that runs on every
   exception reaching DebugExceptions.
2. A second RED middleware, `insert_after ActionDispatch::DebugExceptions`.
3. Read `payload[:exception]` from the `process_action.action_controller` notification.

**Case for 1.** It sees exactly what reaches DebugExceptions, in production and development
alike. It doesn't edit the middleware stack, so a host app that removed or replaced DebugExceptions
just never calls it (option 2's `insert_after` raises at boot when DebugExceptions is missing).
Rails rescues anything it raises. Exceptions a `rescue_from` handles never leave the controller,
so it never sees them (REQ-5). It also catches routing errors and exceptions from mounted Rack
apps, which option 3 misses.

**Case against 1.** It's a process-wide registry, not a per-app setting. It runs even when
`show_exceptions` is off, so it has to make the show/raise check itself (next decision). It
depends on DebugExceptions being in the stack, which it is in every default Rails 7.0 stack, API
apps included.

**Decision.** Option 1. RED registers the interceptor once, from the engine, only when
`ActionPack.gem_version < Gem::Version.new("7.1")`. It checks the actionpack version because
the defect is actionpack's rendering path. ErrorCatcher's `report_takes_source?` asks about
ActiveSupport's API instead.
**Falsifiability.** We would move to a middleware if a Rails 7.0 app is found where
DebugExceptions is not in the stack and request errors go unrecorded.
**Fired-if.** manual

## Decision: record only what Rails is about to render   (→ REQ-1, REQ-2, REQ-3)

**Superseded** on 2026-10-19 by "point affected apps to Rails 7.0.10".

**Context.** With `show_exceptions` off, the exception propagates past DebugExceptions. 7.0's
Executor then reports it, untagged, and RED records that report. ErrorCatcher reports it again,
tagged, and is deduplicated. If the interceptor also reported it, the untagged Executor report
would come second and slip past the dedup (`error_reporter.rb:52-55` skips only tagged repeats).
The same exception would be recorded twice.

**Alternatives.**
1. The interceptor records only when `request.show_exceptions?` is true, the same check
   DebugExceptions makes next (`debug_exceptions.rb:38`).
2. Widen the subscriber's dedup to skip any repeat of an exception object within a request,
   tagged or not.

**Case for 1.** It's local to the new code. With show_exceptions on, nothing else on 7.0 sees the
exception, so this is the only record. With it off, the existing path records it once. No other
path's behaviour changes.

**Case against 1.** It duplicates one line of Rails' own logic, which could drift. It can't: the
check is 7.0-only, and 7.0 is frozen.

**Decision.** Option 1.
**Falsifiability.** We would widen the dedup if a REQ-3 spec on the 7.0 row records a request
exception twice.
**Fired-if.** manual

## Decision: record straight to RED, not through `Rails.error.report`   (→ REQ-1, REQ-6)

**Superseded** on 2026-10-19 by "point affected apps to Rails 7.0.10".

**Context.** ErrorCatcher reports through `Rails.error.report`, so every error subscriber in the
host app receives it. On 7.0, no subscriber has ever received exceptions that ShowExceptions
renders.

**Alternatives.**
1. Call RED's own subscriber (`RailsErrorDashboard::ErrorReporter#report`) with the request in
   the context and `context[:middleware]` set.
2. Call `Rails.error.report`, as ErrorCatcher does.

**Case for 1.** RED fixes its own recording without changing what other tools in the host app
receive. A host on 7.0 that also uses a Rails.error subscriber (an APM, Sentry's subscriber) gets
no new, possibly duplicate, reports. The subscriber still does its own context building, the
recursion guard and the dedup.

**Case against 1.** RED behaves inconsistently with itself: ErrorCatcher broadcasts on 7.0 and the
interceptor doesn't. Other subscribers on 7.0 still miss these errors, though that is Rails 7.0's
behaviour, not RED's.

**Decision.** Option 1. The report passes `handled: false`, `severity: :error`, the request,
`middleware: true`, and `source: "application.action_dispatch"`, the source 7.1 uses for the same
errors, so 7.0 records look like 7.1's. It's recorded as a server capture (capture-source REQ-2).
**Falsifiability.** We would broadcast instead if a user on 7.0 asks for these errors to reach their
other Rails.error subscribers.
**Fired-if.** manual

## Rescue responses (→ REQ-4)
No choice here: the interceptor skips an exception when
`ActionDispatch::ExceptionWrapper.new(backtrace_cleaner, exception).rescue_response?` is true, the
same call 7.1 makes before reporting.

## Decision: prove it with request specs on the dummy app, per Rails row   (→ REQ-1 – REQ-9)

**Superseded** on 2026-10-19 by "point affected apps to Rails 7.0.10".

**Context.** The existing ErrorCatcher spec calls the middleware directly with a stubbed reporter
(`spec/lib/rails_error_dashboard/middleware/error_catcher_spec.rb:21-43`). That can't show where
anything sits in the stack. CI runs every spec on Rails 7.0 (`.github/workflows/test.yml:21-22`).

**Alternatives.**
1. Request specs through the dummy app's real stack, against a small test controller and route
   added to the dummy app (it has none that raise). Each example sets
   `action_dispatch.show_exceptions` and `action_dispatch.show_detailed_exceptions` on
   `Rails.application.env_config` and restores them afterwards. Per-request env values would not
   work: Rails 7.0 merges `env_config` over every request's env (railties 7.0.8.7
   `engine.rb:716`, values from `application.rb:255-256`). The 7.0-only examples run on the 7.0
   rows and REQ-9's on the others.
2. Build a 7.0 `ActionDispatch::MiddlewareStack` by hand in a unit spec.
3. Only the real-app check from the release steps.

**Case for 1.** It's the real middleware stack and the real subscriber, on every CI run, at no
extra CI cost. Each requirement gets its own example.

**Case against 1.** The 7.0 examples are skipped on every other row, so a local run on Rails 8.1
proves nothing about them. They have to be run once locally with a 7.0 bundle, in a worktree with
its own lockfile. The dummy app is not a production app, which is why the release steps add a
real 7.0.8.7 production app as well.

**Decision.** Option 1, plus the release-step app.
**Falsifiability.** We would add option 2 if the dummy app can't reproduce 7.0's production render
path (detailed exceptions off) through `Rails.application.env_config` alone.
**Fired-if.** manual

## Data / interface changes
None. No migration, no new configuration, no change to what 7.1+ records.
