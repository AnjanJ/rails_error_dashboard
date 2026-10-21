# Product: rails_error_dashboard (RED)

> Product reviewed on 2026-10-21.

## One line
Self-hosted Rails error tracking that runs inside the app it watches, showing the Ruby state and Rails health behind every exception without ever putting that app at risk.

## Users
- Rails developers investigating production failures in their own app, who need what Ruby and Rails were doing at the moment of failure, not just a stack trace.
- Solo founders, indie hackers and small teams who want no monitoring account, no ingestion service and no per-event fees.
- Teams whose error data must stay on infrastructure they control.

## Goals this quarter
- Ship 1.0 — metric: v1.0.0 published on RubyGems with config and public API frozen; target: released; by: 2026-12-31
- Prove the overhead budget — metric: capture time and storm-check time, measured by a reproducible benchmark that ships in the repo; target: capture < 5ms, storm check < 5µs (the documented budgets); by: 2026-12-31
- Grow adoption — metric: total RubyGems downloads and GitHub stars; target: 100,000 downloads and 200 stars (55,630 and 94 on 2026-10-21); by: 2026-12-31

## Non-goals
- **Paramount:** no feature that can raise into, block or slow the host app beyond its budget, however valuable. When RED and the host app conflict, RED gives up its data, never the host app's uptime.
- **Paramount:** no feature on the request path that cannot be switched off by config.
- **Paramount:** no process-wide side effects in the host process: no signal handlers, no heap walks, no cross-thread backtraces, no retained Bindings.
- No APM or performance monitoring until error tracking is best-in-class ("depth before breadth", ROADMAP item Z).
- The free gem never requires a separate service, agent, sidecar or monitoring account; it runs only inside the host app.
- No removing a shipped free feature, and no caps on the user's own data.

## Metrics that matter
- **Host-app incidents caused by RED** (it raised into, blocked or slowed a host app). The paramount number: the rules say never.
- Capture overhead against the budgets above (not measured reproducibly yet; the benchmark goal fixes that).
- Adoption: RubyGems downloads and GitHub stars.
- Issue response time: time to first response on a new issue.
- Developer experience. The aim is an experience so good that Rails developers can't imagine monitoring errors with anything else. Measured by:
  - install to first error: minutes from `bundle add` to the first error on the dashboard, on a fresh app (not timed yet)
  - setup issues per release: new issues about install, upgrade or docs
  - release scenarios pass: fresh, upgrade and uninstall on SQLite, PostgreSQL and MySQL across Rails 7.0–8.1, before every release

## Constraints
- **Paramount: the host app comes first.** RED runs inside the host app's process, so every line of RED can break the host app. These outrank every goal, feature and deadline in this file:
  - Never raise in the capture path, never block a request, and always re-raise the original exception (a swallowed one broke Sidekiq retries in sentry-ruby#1173).
  - Budget every operation: total capture < 5ms, health snapshot < 1ms, breadcrumb < 0.01ms; notifications and analysis are always async.
  - Fail open: under an error flood, shed RED's own context and writes before touching the host app (storm protection).
  - Detect a library before calling it; optional dependencies degrade silently.
  - Migrations run inside the host app's deploy: replay-safe, and RED never writes another gem's files (decision 0001).
  - The full 11 rules, budgets, incidents and review checklist: `.claude/skills/host-app-safety/SKILL.md`.
- MIT and free forever, a promise already made in the README.
- Rails 7.0–8.1, Ruby 3.2–4.0, PostgreSQL, MySQL or SQLite; the host app's own database or a separate one.
- Adds nothing to the host app's asset pipeline, and error data stays in the host app's database.
- Beta: config and API may change until 1.0.
- Maintained mainly by one person.

## Now / Next / Later
- **Now:** the three goals above. The post-0.16.1 cleanup finished on 2026-10-21; nothing else is in flight.
- **Next:** native-speaker reviews of the 9 open locales (#156–#165), which are community-owned by design.
- **Later:** RED Pro, a hosted edition to make money from RED. It comes after publishing the "free forever" stewardship commitment (business case §10), and the remote-transport spec needs a refresh first. Any transport must still obey the paramount rules: async, and fail open.
