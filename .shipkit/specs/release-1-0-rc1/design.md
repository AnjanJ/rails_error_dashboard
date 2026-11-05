# Design: 1.0.0.rc1

## Approach
Five pieces of work, then the release.

1. **The floors.** The gemspec, the CI matrix and every branch for an older Rails or Ruby, as decision
   `0003` says. The Gemfile's sqlite3 `~> 1.4` branch for Rails 7.0 goes, and with it the two Dependabot
   alerts it keeps open.
2. **Capture after the response.** Decision `0009` is already made: async capture hands its enqueue to
   `rack.response_finished` where the env has it. This design only settles where the line falls, how
   the benchmark times both halves, and what the budget then means. The capture budget becomes "5 ms
   before the response", which is what the paramount rule protects.
3. **The budgets.** Health snapshot 1.5 ms on every CPU, keeping the gate (intake, answer 1). The other
   budgets stay as they are.
4. **The upgrade matrix.** A dispatch-only workflow that upgrades from the latest patch of every 0.x
   minor, on each of the three databases (intake, answer 2).
5. **The release candidate.** How the version is spelled and marked, how the demo takes it (intake,
   answer 3), the docs pass, and the stats partial that decision record's clause deletes at the tag.

The public API doesn't change. `docs/PUBLIC_API.md` lists no view, partial or locale key ("What's
private": "i18n keys", "The dashboard's HTML, CSS and JavaScript"), so REQ-22 is allowed in a minor, and
so before 1.0.

## What was checked

### What runs a `rack.response_finished` callback
- **Rack's SPEC** (https://github.com/rack/rack/blob/main/SPEC.rdoc): "If present, an array of callables
  that will be run by the server after the response has been processed. Typically this will be after
  sending the response to the client, but it could also be if an error occurs while generating the
  response or sending the response." Each is called in reverse order with `env`, `status`, `headers`
  and `error`.
- **Puma 8.0.2** (tag `v8.0.2`, `93853280`): `lib/puma/client_env.rb:152` sets
  `env["rack.response_finished"] ||= []` on every request. `lib/puma/response.rb:123-131` runs the
  callables in reverse in an `ensure`, so they also run when the app raised. A callable that raises a
  `StandardError` is rescued and logged only at debug level, so RED must rescue its own.
- **Rails 8.1's `ActionDispatch::Executor`** (`actionpack/lib/action_dispatch/middleware/executor.rb`,
  tag `v8.1.1`) pushes `proc { state.complete! }` before it calls the app. Callbacks run in reverse, so
  one RED adds later runs before the executor completes, still inside the executor, with its database
  connection checked out.
- **RED's own middleware.** `ErrorCatcher` is inserted at position 0 (`engine.rb:50`), outside the
  executor, and keeps the env in `Thread.current[:rails_error_dashboard_request_env]` until its
  `ensure` clears it, with the breadcrumb buffer (`middleware/error_catcher.rb:29,63-66`). So every
  report made during a request, the executor's included, can see the env. The callback must not read
  either thread-local, because both are gone by the time it runs.

### How a Ruby prerelease is spelled
- **RubyGems** (https://guides.rubygems.org/versioning/, "Prerelease versions"): "Any version containing
  a letter, like `1.0.0.pre`, `2.0.0.rc1`, or `1.5.0.beta.3`, is a prerelease version." "`gem install
  hola` installs the newest stable version, and only `gem install hola --pre` picks the release
  candidate." "Bundler considers a prerelease only when a requirement explicitly names one."
- **Checked with `Gem::Version` on Ruby 3.4.5:** `1.0.0-rc.1` becomes `1.0.0.pre.rc.1`, and `1.0.0.rc1`
  stays `1.0.0.rc1`. All four spellings tried are prereleases and sort below `1.0.0`. None satisfies
  `~> 0.9` or `~> 1.0`, so no pinned app takes the release candidate by accident.
- **release-please** (`googleapis/release-please`, read on main; neither file has changed since 2023,
  and the pinned action v5.0.0 depends on `release-please ^17.6.0`):
  - `src/version.ts` parses with
    `/(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)(-(?<preRelease>[^+]+))?(\+(?<build>.*))?/`, which is
    not anchored. `Release-As: 1.0.0.rc1` matches `1.0.0` and drops `.rc1`, so it would release
    1.0.0 itself. A prerelease has to be written with a dash: `Release-As: 1.0.0-rc.1`.
  - The `ruby` strategy's `VersionRB` updater (`src/updaters/ruby/version-rb.ts`) writes
    `stringifyRubyVersion(this.version)` without the dot option, so `version.rb` gets `"1.0.0-rc.1"`
    and RubyGems publishes it as `1.0.0.pre.rc.1`. The dot form exists in `src/updaters/ruby/common.ts`
    but the `ruby` strategy doesn't use it.
  - The manifest config's `"prerelease": true` creates "Prerelease" GitHub releases "that have
    pre-major or prerelease versions" (`docs/manifest-releaser.md`; `schemas/config.json`: "Create the
    GitHub release as prerelease").
  - The README's "Release-As" section: a commit with `Release-As: x.x.x` in its body opens a pull request
    for that version.
- **Not verified:** what release-please proposes for a `fix:` after `1.0.0-rc.1` without a trailer, and
  the plain tag `rubygems/release-gem` makes for a prerelease (the plain `v0.18.0` tag sits on a
  different commit from `rails_error_dashboard/v0.18.0`, so the action probably makes it). The release
  steps set every version with a trailer, so the first doesn't matter.

### The demo
On the demo's `main`: `Gemfile:48` pins `gem "rails_error_dashboard", "~> 0.9"`.
`.github/workflows/update-demo-release.yml` runs every 30 minutes and on dispatch. It runs
`script/update_demo_release.rb`, which reads the version from RubyGems' gem endpoint and raises unless
it matches `/\A\d+\.\d+\.\d+\z/`, and then refuses a GitHub release tagged other than
`rails_error_dashboard/v<version>` or marked prerelease. On a change it runs the tests, commits to
`main`, and Render deploys it.

### The upgrade matrix
RubyGems lists 104 stable versions in 18 minors. The latest patches are 0.1.38, 0.2.4, 0.3.1, 0.4.2,
0.5.15, 0.6.4, 0.7.2, 0.8.4, 0.9.1, 0.10.0, 0.11.9, 0.12.1, 0.13.0, 0.14.4, 0.15.0, 0.16.2, 0.17.0 and
0.18.0. Every one requires Ruby >= 3.2 and Rails >= 7.0, with no upper bound (0.1.38, 0.5.15, 0.9.1 and
0.14.4 checked on the v2 API), so each resolves in a Rails 8.1 app. `bin/pre-release-test full_upgrade`
starts from the latest release only, and only on SQLite.

## Decision: Defer only the enqueue, not the job's arguments   (→ REQ-5, REQ-6, REQ-7)

**Context.** Decision `0009` moves async capture's enqueue after the response. Before the enqueue,
`LogError`'s async path builds the job's arguments on the request thread: the exception's data, the
context, breadcrumbs, and local and instance variables when they're on. That work reads the request,
`Thread.current` and the breadcrumb buffer, which `ErrorCatcher`'s `ensure` clears before any callback
runs. It sends nothing to the database.

**Alternatives.**
1. Build the arguments on the request thread as now, and move only `AsyncErrorLoggingJob.perform_later`
   and its checks into a closure that the callback runs.
2. Move the whole async branch into the callback.

**Case for 1.** Only the enqueue sends anything over the network: the seven statements counted on
2026-11-05 are all Solid Queue's. The closure holds plain data that is already built, so it reads
nothing that has been cleared or reused. The inline path and the deferred path share the same
arguments, so one spec can compare them.

**Case against 1.** The arguments are still built before the response. With local variables on, that is
the larger part of what's left, and it stays in the request's time.

**Decision.** We chose option 1.
**Falsifiability.** We would also defer building the arguments if the "Capture, async" row's median before
the response is over 1 ms on the EPYC 7763 with the database 1 ms away.
**Fired-if.** manual

## Decision: Find the hook through `ErrorCatcher`'s env   (→ REQ-5, REQ-6)

**Context.** Capture reaches `LogError` from `ErrorCatcher`, from Rails' error reporter, from manual
reports and from jobs. Only some of those pass a request.

**Alternatives.**
1. Read `Thread.current[:rails_error_dashboard_request_env]` and use its `rack.response_finished` when it
   is an Array.
2. Pass the env down from each caller.
3. Use `rack.after_reply`, Puma's older hook.

**Case for 1.** `ErrorCatcher` already keeps the env there for the whole request, and it is outermost,
so every report during a request can see it. Nothing else changes signature. Without the middleware
(`enable_middleware = false`), outside a request or in a job, the thread-local is nil, and capture
enqueues inline as REQ-6 asks.

**Case against 1.** It depends on `enable_middleware`: an app that turns the middleware off gets the
inline path even under Puma. A thread-local is easy to leave set by mistake, so the spec has to cover a
second request on the same thread.

**Decision.** We chose option 1. Option 3 is Puma-only, and Rack 3 names `rack.response_finished`.
**Falsifiability.** We would pass the env down if an issue shows a report made during a request that
doesn't see the env.
**Fired-if.** manual

## Decision: Time both halves, and gate only the first   (→ REQ-8, REQ-9, REQ-10)

**Context.** `bin/benchmark` calls `LogError` with no request, so after `0009` its "Capture, async" row
would still time the inline path. The 5 ms budget protects the time before the response.

**Alternatives.**
1. Run the row inside an env with an empty `rack.response_finished` array, as Puma sets it. Time the
   call against 5 ms, then time running the callbacks as a new row, "Capture, async, after the response",
   with no budget.
2. Gate the after-the-response row too, at a new budget.
3. Leave the rows alone, and measure only in the load test.

**Case for 1.** The gated row times what the budget protects. The new row keeps the cost after the
response visible, where `0009`'s reversal clause watches throughput. Both run in the one-minute check and
in each shape's rows.

**Case against 1.** A synthetic env proves only that RED uses the hook, not that a server calls it. The
load test (a real Puma) and the chaos phase that boots Puma cover that, and they are slower.

**Decision.** We chose option 1.
**Falsifiability.** We would gate the after-the-response row if an issue reports a host's Puma threads
saturating under errors because of RED's callbacks.
**Fired-if.** manual

## Decision: Health snapshot at 1.5 ms on every CPU   (→ REQ-11, REQ-12)

**Context.** The health snapshot misses 1 ms on two Xeons CI draws (1.15 to 1.30 ms) and on every arm64
run (1.23 to 1.33 ms), while AMD x64 passes (0.47 to 0.86 ms) (intake, answer 1). It reads in-process
metrics only: 437 µs on x64 with the database 1 ms away.

**Alternatives.**
1. 1.5 ms on every CPU, and keep the gate.
2. A budget for each architecture.
3. Keep 1 ms, and change the gate to allow misses.

**Case for 1.** One number to freeze and quote. Every CPU seen so far passes it, with room. The gate
still catches a real regression.

**Case against 1.** It loosens the fast CPUs' budget by half, so a regression of up to 0.6 ms on an EPYC
9V45 passes unseen.

**Decision.** The maintainer chose option 1 on 2026-11-05.
**Falsifiability.** We would set a budget for each architecture if the row fails on main on any CPU with
no change to the health snapshot.
**Fired-if.** manual

## Decision: A dispatch-only upgrade matrix, its from-versions read from RubyGems   (→ REQ-13, REQ-14)

**Context.** The maintainer chose the latest patch of every minor from 0.1 to 0.18, on PostgreSQL, MySQL
and SQLite, dispatch-only, run before rc1 and before 1.0 (intake, answer 2). That is 54 upgrades. The
harness's upgrade test reads its from-version from RubyGems so that it can't rot
(`bin/pre-release-test`, `latest_published_version`), and runs on SQLite only.

**Alternatives.**
1. A new workflow whose first job reads the latest patch of each 0.x minor from RubyGems and hands the
   list to a matrix of from-version by database, each row running the harness's upgrade test with that
   version and database.
2. The same, with the 18 versions written in the workflow.
3. A loop inside the existing "Upgrade Path" job.

**Case for 1.** Each row passes or fails on its own and shows which version broke. It can't fall behind
a new 0.18.x. The harness gains a version and a database choice, which the PR job can keep using with
its defaults.

**Case against 1.** It depends on RubyGems' API at dispatch, and a yanked version changes the list
quietly. 54 rows take runner time, and MySQL and PostgreSQL need service containers in each.

**Decision.** We chose option 1.
**Falsifiability.** We would write the versions down if the job that reads them fails two dispatches in
a row because of RubyGems' API.
**Fired-if.** manual

## Decision: How the release candidate's version is spelled   (→ REQ-16)

**Context.** release-please sets the version from a `Release-As:` trailer, but only with a dash, and
the `ruby` strategy writes the dash into `version.rb` (above). So the automatic path publishes
`1.0.0.pre.rc.1`, not the `1.0.0.rc1` RubyGems' guide shows. `release.yml`'s dispatch path publishes
whatever `version.rb` says, after checking the typed version matches it.

**Alternatives.**
1. `Release-As: 1.0.0-rc.1` through the release PR, and set `"prerelease": true`. RubyGems gets
   `1.0.0.pre.rc.1`, the tag is `rails_error_dashboard/v1.0.0-rc.1`, and the changelog and manifest
   follow as for every release.
2. Set `version.rb` to `"1.0.0.rc1"` by hand, publish with `release.yml`'s dispatch, and make the tag
   and GitHub release by hand.
3. Change release-please's strategy or add an updater so it writes the dot form.

**Case for 1.** It is the path every release has taken, with its tests, tag, changelog and smoke test.
The manifest moves to `1.0.0-rc.1`, so the next release PR can't propose a 0.x version from main.

**Case against 1.** Three spellings: `RailsErrorDashboard::VERSION` is `"1.0.0-rc.1"`, the gem is
`1.0.0.pre.rc.1`, and the tag has the dash. The demo's script matches a tag to the RubyGems version, so
it has to map one to the other. `"prerelease": true` marks every pre-major release as a prerelease, so it
lands only after 0.18.1, and a later 0.x security release from its own branch needs the flag off there.

**Decision.** Proposed: option 1. Option 2 leaves the manifest at 0.18.x, so the next release PR on main
would propose a 0.x version over the 1.0 code. Option 3 changes the release tooling during the freeze.
The maintainer decides at the design gate.
**Falsifiability.** We would change the spelling if RubyGems or Bundler shows `1.0.0.pre.rc.1` wrongly to
users, such as `gem install --pre` not picking it.
**Fired-if.** manual

## Decision: The demo takes a prerelease only by dispatch   (→ REQ-17, REQ-18, REQ-19)

**Context.** The maintainer chose to run rc1 on the demo, and each deploy needs their yes (intake,
answer 3). The update workflow deploys on a schedule, refuses anything but `X.Y.Z`, and refuses a GitHub
release marked prerelease. `~> 0.9` excludes 1.0.0 and every prerelease, and Bundler takes a prerelease
only when the requirement names one.

**Alternatives.**
1. The pin becomes `">= 0.9", "< 2"`. The dispatch gains a `version` input. When it names a prerelease,
   the script writes that version into the Gemfile's requirement as its floor, maps the RubyGems version
   to its tag, and deploys. The schedule keeps refusing prereleases.
2. The schedule also deploys a prerelease once it is published.
3. Keep the demo on 0.18.x until 1.0.0.

**Case for 1.** The dispatch is the maintainer's yes. The schedule can't move the demo onto a release
candidate by itself, and it can't move it back either, because the script already skips anything older
than what's locked. When 1.0.0 ships, the schedule takes it as it takes any stable release.

**Case against 1.** Two ways in, and the dispatch path runs only twice (rc1, and an rc2 if there is one),
so a fault in it shows up on the day. The tag mapping depends on the spelling chosen above.

**Decision.** We chose option 1.
**Falsifiability.** We would keep the demo on 0.x if the dispatch deploy of rc1 fails its verification
twice.
**Fired-if.** manual

## Decision: Delete the stats partial before the tag   (→ REQ-22)

**Context.** `_shipped/live-updates-hardening-0-17` kept `errors/_stats.html.erb` after removing the
stats broadcast, and said it would be deleted "if 1.0.0.rc1 is tagged and no issue has mentioned
rendering the stats partial from a custom view". Its clause, `git tag -l 'v1.0.0*' | grep -q .`, fires
at rc1's tag. Searches of the issues for "stats partial" and "errors/stats" on 2026-11-06 found none
about a custom view. The partial has a view spec and five keys (`red.errors.stats.*`) in each of the
eleven locales.

**Alternatives.**
1. Delete the partial, its view spec and its keys in rc1.
2. Keep it until 2.0.

**Case for 1.** Nothing built in renders it, and the dashboard's HTML and i18n keys are private. Deleting
it in the release candidate lets the quiet weeks show whether anyone did render it.

**Case against 1.** An app whose custom index renders it gets a `MissingTemplate` error on upgrade, in the
release that is meant to be the safe one.

**Decision.** We chose option 1.
**Falsifiability.** We would restore it in 1.0.0 if an rc1 user reports a custom view that renders it.
**Fired-if.** manual

## Data / interface changes
- **Gemspec:** `required_ruby_version >= 3.3.0` and `rails >= 7.2.0` (REQ-1).
- **Capture:** no new option and no changed signature. Under a server with `rack.response_finished`, a
  captured error's row appears after the response rather than before it (REQ-5).
- **Benchmark:** a new reported row, "Capture, async, after the response", and the health snapshot's
  budget at 1.5 ms (REQ-9, REQ-11).
- **Workflows:** a new dispatch-only upgrade workflow (REQ-13, REQ-14), the test matrix at 9 rows
  (REQ-2), and release-please's `prerelease` flag (REQ-16).
- **Removed:** the `errors/_stats` partial and its locale keys, which are private (REQ-22).
- **Demo:** its Gemfile requirement, and a `version` input on its update workflow (REQ-17 to REQ-19).
