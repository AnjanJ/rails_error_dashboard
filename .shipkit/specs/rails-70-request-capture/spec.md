# Spec: Rails 7.0 request capture

> Spec accepted at commit `da1e915` on spec/0-16-1.
> Status: open
> Paths: lib/rails_error_dashboard/configuration.rb,README.md,docs/,_getting_started/,_reference/,spec/

## Purpose
On Rails 7.0.0 to 7.0.8.7, Rails renders a request's error page without reporting the exception,
so RED records no unhandled request errors. Rails 7.0.10 (2025-10-28) fixed this upstream. 0.16.0
documented it as a known limitation of "Rails 7.0", which was too broad. Tell the affected apps,
at boot and in the docs, that upgrading Rails to 7.0.10 fixes it. Revised on 2026-10-19 after the
7.0.10 finding; see `intake.md`. The first version of this spec, a 7.0-only reporter, is
superseded (`design.md`).

## User stories
- As a developer on Rails 7.0.8.x, I want RED to tell me that request errors aren't being
  recorded and how to fix it, so I don't assume my app has none.

## Requirements (EARS)
- **REQ-1.** While the host app runs a Rails older than 7.0.10, when RED validates its
  configuration at boot, RED shall log one warning saying that this Rails version does not report
  the request exceptions it renders as error pages, so RED cannot record them, and that upgrading
  to Rails 7.0.10 or later fixes it.
- **REQ-2.** While the host app runs Rails 7.0.10 or later, RED shall not log that warning.
- **REQ-3.** The README, the Quickstart and the Troubleshooting guide, and their Jekyll copies,
  shall say that unhandled request errors are not recorded on Rails 7.0.0 to 7.0.8.7, and that
  Rails 7.0.10 fixes it. [untested: prose, verified by reading]

## Out of scope
- A RED reporter for Rails 7.0.0 to 7.0.8.7. Rejected (`intake.md`, `design.md`).
- Raising RED's minimum Rails to 7.0.10.
- Recording development-mode request errors on Rails 7.0. No 7.0 patch version reports them.
- What 7.1+ records through `ActionDispatch::Reloader` when code reloading is on (seen in the
  probe; see `design.md`).

## Release steps
Not requirements, because they describe the release rather than the product:
- The 0.16.1 release notes correct the 0.16.0 "Known limitation: Rails 7.0": only 7.0.0 to 7.0.8.7
  are affected, Rails 7.0.10 fixes it, and RED now warns at boot. The 0.16.0 CHANGELOG section
  stays as written.
- A real Rails 7.0.10 production app records a raising request once and a 404 not at all, via a
  7.0 row in the local release scenario runner.
