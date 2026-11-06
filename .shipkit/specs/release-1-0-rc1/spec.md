# Spec: 1.0.0.rc1

> Spec accepted at commit `3e87854` on spec/release-1-0-rc1 (2026-11-06).
> Status: open
> Paths: rails_error_dashboard.gemspec,Gemfile,lib/,app/,config/locales/,benchmark/,.github/workflows/,spec/,test/pre_release/,bin/pre-release-test,docs/,README.md,_getting_started/,.release-please-config.json,ROADMAP.md,.claude/skills/,.shipkit/product.md,.shipkit/research/

## Purpose
1.0.0.rc1 is the release candidate for 1.0.0. It goes out in early December, then about two quiet weeks
follow before 1.0.0 by 2026-12-31. It raises the floors to Rails 7.2 and Ruby 3.3, keeps async capture
inside its budget when the database is across a network, proves the upgrade from every 0.x minor, puts
the demo on the release candidate, and drops the "Beta" label. After it, the public API and the overhead
budgets are frozen (decision `0002`, `docs/PUBLIC_API.md`, `docs/VERSIONING.md`).

## User stories
- As a Rails developer on a managed database, I want RED's capture to stay out of my response time, so
  that a failing request isn't slowed by a queue's round trips.
- As a Rails developer on any 0.x release, I want the upgrade to 1.0 to be tested from my version, so
  that I can take it without reading every changelog.
- As the maintainer, I want the release candidate tried on the demo in production, so that the quiet
  weeks test what 1.0.0 will be.
- As a new user, I want the README to say what RED supports and promises, so that I can decide on it
  without a "Beta" warning that no longer applies.

## Requirements (EARS)

### The floors (decision `0003`)
- **REQ-1.** The gemspec shall require Rails 7.2 or later and Ruby 3.3 or later.
- **REQ-2.** The CI test matrix shall run Ruby 3.3, 3.4 and 4.0 against Rails 7.2, 8.0 and 8.1, each Ruby
  named by its series.
- **REQ-3.** The gem shall hold no code path, warning or dependency pin that exists only for Rails before
  7.2 or Ruby before 3.3.
- **REQ-4.** When an app sets `async_adapter` or `llm_observability_content_capture`, RED shall log one
  deprecation warning and otherwise ignore the value (decision `0004`).

### Capture across a network (decision `0009`)
- **REQ-5.** While a request's Rack env has `rack.response_finished`, async capture shall enqueue its job
  from that callback, after the response, instead of on the request's thread.
- **REQ-6.** Where the request's Rack env has no `rack.response_finished`, or capture runs outside a
  request, async capture shall enqueue on the calling thread.
- **REQ-7.** If the enqueue run from `rack.response_finished` fails, then RED shall log the error
  synchronously from that callback and shall not raise into the server.
- **REQ-8.** The "Capture, async" benchmark row shall time the work RED does before the response, under
  a Rack env that has `rack.response_finished`.
- **REQ-9.** The benchmark shall report the work async capture does after the response as its own row.
- **REQ-10.** While the database is 1 ms away, the "Capture, async" row shall stay under its 5 ms budget
  on every deploy shape. [untested: proved by a dispatch of each shape, recorded in the research file]

### The budgets the freeze writes down
- **REQ-11.** The benchmark shall gate the health snapshot row at 1.5 ms on every CPU.
- **REQ-12.** The product file, the safety skills and the README shall state the same budgets: capture
  5 ms before the response, health snapshot 1.5 ms, storm check 15 µs, breadcrumb 10 µs. [untested: prose,
  verified by reading]

### The upgrade from 0.x
- **REQ-13.** When the maintainer dispatches the upgrade workflow, it shall install the latest patch of
  every 0.x minor from 0.1 to 0.18 in a fresh app, upgrade that app to the branch, and verify it, once each
  on PostgreSQL, MySQL and SQLite.
- **REQ-14.** The upgrade workflow shall run only when dispatched by hand, with a read-only token and no
  secrets.
- **REQ-15.** The upgrading guide shall have a "0.x to 1.0" section that names every removal, the new
  floors and the steps. [untested: prose, verified by reading]

### The release candidate
- **REQ-16.** Where a release has a prerelease version, its GitHub release shall be marked as a
  prerelease.
- **REQ-17.** When the maintainer dispatches the demo's update workflow with a prerelease version, the
  workflow shall deploy that version. [untested: tested in the demo repository's
  `script/update_demo_release_test.rb`, which spec-check can't read]
- **REQ-18.** The demo's scheduled update shall never deploy a prerelease. [untested: tested in the demo
  repository's `script/update_demo_release_test.rb`, which spec-check can't read]
- **REQ-19.** The demo's Gemfile shall accept every 1.x release, and any prerelease that the update
  workflow names. [untested: tested in the demo repository, which spec-check can't read]

### The docs
- **REQ-20.** The README and the docs shall not call RED beta, and shall state Rails 7.2 to 8.1 and Ruby
  3.3 to 4.0.
- **REQ-21.** The docs shall describe only options the code has, and the roadmap's header shall name the
  current version. [untested: prose, verified by reading]
- **REQ-22.** The gem shall not ship the `errors/_stats` partial or its locale keys. [untested: a deletion,
  shown by `bin/i18n-check` finding no orphaned keys and no file rendering the partial]

## Depends on
- **`deploy-shape-benchmark`, T19 to T21,** merged first (intake, answer 4). REQ-8 to REQ-10 change the
  rows that spec built, and REQ-10 needs its shapes.
- **CI's Ruby on ubuntu-26.04.** On 2026-11-05 GitHub's `ubuntu-latest` became ubuntu-26.04, where
  setup-ruby builds only the latest patch of each Ruby series: 3.4.5 is a 404, and 3.4.12 exists. CI's
  `lint` and `audit` pin 3.4.5, and `release.yml` reads `.ruby-version` (3.4.5) in its `test` and
  `publish` jobs. That fix is its own change, ahead of this spec, and nothing here can publish until it
  lands. Every workflow this spec writes names a Ruby series or the latest patch.
- **0.18.1 (#351) released first,** so the last 0.x release before rc1 isn't marked a prerelease by REQ-16.

## Out of scope
- Anything decision `0002` moved to 1.1, the Full Context Error Report among them.
- Replacing Pagy (decision `0006`: pinned through 1.0, replaced in 1.x).
- Renaming any config or ENV name (decision `0008`: frozen as they are).
- Deleting the `async_adapter` and `llm_observability_content_capture` setters (decision `0004`: 2.0).
- RED Pro, the community translations (#156-#165), and the roadmap's open feature ideas.
- Releasing 0.18.1, which is its own release.
- Fixing the CI Ruby versions for ubuntu-26.04, which is its own change (above).

## Release steps
These are the release, not the product, so they have no requirement. `tasks.md` lists them under "After
the gate".
- Set the version with a `Release-As:` trailer, spelled as `design.md` decides.
- Run the upgrade workflow on the release commit, before rc1 and again before 1.0.0.
- Publish, then deploy the demo by dispatch, each with the maintainer's yes.
- Ask early users to try it, in a GitHub discussion or issue.
- After about two quiet weeks, 1.0.0 with `Release-As: 1.0.0`.
