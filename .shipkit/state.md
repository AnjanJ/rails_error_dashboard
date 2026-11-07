# Handoff

> Written 2026-11-07 at commit `fd641303`, on the branch `feat/rc1-after-response` (T4-T8 of rc1).

## In flight
- **`release-1-0-rc1`** is the one open spec: `.shipkit/specs/release-1-0-rc1/` (accepted 2026-11-06, merged
  in #359 with decision `0009`). Six pull requests, in the order of its tasks.md: the floors (T1-T3, merged
  in #360), capture after the response and the budgets (T4-T9), the upgrade matrix (T10-T11), the docs and
  the stats partial (T12-T14), the prerelease flag (T15), then the demo (T16-T17). The release steps under
  "After the gate" each need the maintainer's yes.
- **T4-T9 are on `feat/rc1-after-response`.** T4-T8 are done: async capture hands its enqueue to
  `rack.response_finished` (`commands/log_error.rb`), the "Capture, async" row times the work before the
  response under a Puma-style env, "Capture, async, after the response" reports the rest with no budget, and
  the health snapshot is gated at 1.5 ms. On #362's CI (run 42356111086, a Xeon 6973P-C) the rows read 137 µs
  before the response, 15 µs after it, and 418 µs for the health snapshot. T5 reached past its file list: phase F needs async capture under a
  real Puma, and only the sync HTTP app ran it, so `full_async` now boots Puma and runs phase F
  (`bin/pre-release-test`), with the TracePoint features on in its initializer. Its fixtures add
  `/test/deferred_error` and an initializer that holds that error's enqueue 1.5 s, which F9 times against
  the response. T5 also removed phase F's Ruby 3.3 and Rails 7.1 branches that T3 left.
- **T9 needs the maintainer's yes** for its benchmark dispatches: each shape re-run with the database 1 ms
  away, its runs recorded in the research file, then the five files that state the budgets.

## Done
- **rc1's floors merged in #360** (`b832160f`) on 2026-11-07: Rails 7.2 and Ruby 3.3, the test matrix at 9
  rows, and the code for older versions removed. Main's ruleset lost the 11 required checks for Ruby 3.2
  and Rails 7.0/7.1 first, with the maintainer's yes. The two sqlite3 Dependabot alerts (#331's) closed as
  fixed on the merge. The merged branches of #358 and #359 were deleted on GitHub.
- **`deploy-shape-benchmark` is finished.** T21 merged in #358 (`27720d6c`) on 2026-11-06, the last of its
  tasks: the deploy benchmark workflow takes a `shape`, a `stack` and a `ruby`. With the database 1 ms away,
  async capture missed its 5 ms budget only where Solid Queue's enqueue crosses the network (on `medium` at
  `8d20630`: PostgreSQL 7.76 ms, 7.96 ms on Ruby 4.0, MySQL 8.85 ms, against Sidekiq 1.47 ms and SQLite
  885 µs). Decision `0009` answers it in rc1. All 21 of its tasks are ticked. Every figure from its
  dispatches, with its run, is in `.shipkit/research/deploy-shape-benchmark.md`, and how each task was
  proved is in this file as of `7e1abc40`.
- 0.18.0 shipped 2026-10-31, about three weeks ahead of its target. RubyGems, the GitHub Release, both
  tags and the demo all carry it. Its eight specs moved to `.shipkit/specs/_shipped/`, each marked
  "shipped in 0.18.0 (#N)".
- Issue #326 is closed. #341 fixed it on 33 migrations, not the 26 in its title.
- #349 merged 2026-11-05 (`05fa121`): `AiAgentClassifier.name(user_agent)` no longer replaces `Class#name`;
  the lookup is `agent_name`. Also merged that day: #348 (setup-ruby 1.336.0), and the demo's #74 (five
  flagged gems) and #75 (Rails 8.1.4.1, for GHSA-wm3x-v3qw-4jh3).
- 0.18.1 shipped 2026-11-05 (#351, `657ea2a`), with #349's fix. RubyGems and the GitHub Release carry
  it. `keep-module-name` moved to `.shipkit/specs/_shipped/`, marked "shipped in 0.18.1 (#349)".
- The same day GitHub's `ubuntu-latest` became ubuntu-26.04, where setup-ruby builds only the latest
  patch of each Ruby series, so 3.4.5 stopped setting up. #353 moved `lint` and `audit` to 3.4.12, and
  #354 the release's `test` and `publish` jobs, which read `.ruby-version`; that file stays 3.4.5 for
  local work. The demo moved `.ruby-version` and its Dockerfile to 3.4.12 in its #76, and its errors
  recorded Ruby 3.4.12 after the deploy.

## Next step
1. Build 1.0.0.rc1 from `.shipkit/specs/release-1-0-rc1/`, starting with the floors pull request. Its
   answers: Release-As 1.0.0-rc.1, after checking how release-please spells a prerelease; only a
   prerelease's demo deploy needs a dispatch; the prerelease flag lands after 0.18.1 (published); the
   upgrade matrix's from-apps use Rails 8.1 only; the stats partial is deleted in rc1.
2. Re-read `docs/PUBLIC_API.md` and `docs/VERSIONING.md` before the release steps, since rc1 freezes them,
   and settle the reversal clauses marked "Revisit at 1.0.0.rc1" below.

## Path to 1.0
| Release | Target |
|---|---|
| 0.18.0 | shipped 2026-10-31 |
| 1.0.0.rc1 | early December, then about two quiet weeks |
| 1.0.0 | by 2026-12-31 |

## Open questions
- **Does the benchmark gate change?** `Overhead benchmark` failed on main on `5ec8a3c`: health snapshot
  1.15 ms on a Xeon 8573C, against 1 ms. It isn't a regression, because that commit changed only the
  version and docs. The job wasn't re-run and the gate is unchanged. The Xeon has failed both times it
  was drawn. The shape benchmark runs on the same runners, so it won't settle this. On #349's branch, a
  Xeon 8370C read 1.30 ms on 2026-11-05, as one read 1.29 ms on #347's: PR runs, so the count stays 1.
- **The health snapshot misses 1 ms on arm64.** On #347's dispatch (run 41216679726, `a5e5c47`), all three
  arm64 rows read 1.23 to 1.27 ms on a Neoverse-N2, against the 1 ms budget, while every x64 row passed
  (0.51 to 0.69 ms). The gated job runs only on x64, so CI can't see it. The `medium-arm` shape will meet it.
  Is the budget per architecture?

## Do not forget
- **Reversal clauses that left the automatic scan.** `decision-check.sh` reads only
  `.shipkit/decisions/*.md` and `.shipkit/specs/*/design.md`. Archived specs drop out, so these
  executable clauses are no longer checked automatically:
  - `_shipped/small-fixes-0-18`: a third `PLATFORM = "` in the services (HOLDS on 2026-10-31).
  - `_shipped/webhook-v1`: a fourth file calling `WebhookDelivery.post` (HOLDS on 2026-10-31).
  - `_shipped/live-updates-hardening-0-17`, "Remove the stats broadcast, keep the stats partial":
    fires when a `v1.0.0*` tag exists. **Revisit at 1.0.0.rc1.**
  - Also in `_shipped/live-updates-hardening-0-17`: the actioncable gemspec dependency.
  - `_shipped/live-updates-client`: two clauses.
  - `_shipped/host-hygiene-0-17`: the CDN tag count.
  - `_shipped/test-gaps-0-17`: the PG/MySQL rows in `test.yml`.
  - Earlier: `_shipped/capture-source` (two) and `_shipped/occurrence-context-history` (one).
- **Manual clauses someone has to watch.** `decision-check.sh` can't measure these, and they've left its
  list too. Each is in its `design.md`. Most other 0.18 clauses wait on an issue being reported.
  - `_shipped/overhead-benchmark`, the gate: change it if the job fails on main three times by 2026-11-30
    with no capture-path change. **The count is 2**: `5ec8a3c`, and `657ea2a` (0.18.1's release, 2026-11-05),
    whose health snapshot read 1.10 ms on a Xeon 8573C. The change is already chosen: 1.5 ms on every CPU,
    in the rc1 spec.
  - `_shipped/overhead-benchmark`, the storm budget: raise it or pin the runner if a storm row fails on
    main on any CPU but the EPYC 7763 with no capture-path change.
  - `_shipped/overhead-benchmark`, the figures: go back to one figure per row if the job moves to a pinned
    runner, or if the health snapshot's spread between CPUs falls under 20%.
  - `_shipped/overhead-benchmark`, the timing: batch the capture rows if their round-to-round spread on
    the runner goes over 20% of the median.
  - `_shipped/webhook-v1`: revert the UTC `timestamp` if an issue reports a broken receiver by 2026-11-30.
  - `_shipped/migration-rollback`: fall back to a cheaper check if the round-trip spec adds over 60 s to an
    adapter row (24 to 35 s when it landed).
- **A new database must be prepared with RED on.** One of RED's migrations,
  `BackfillApplicationForExistingErrors`, reads RED's models, so `db:prepare` with `RED=off` fails on an
  empty database. `ComposeDriver#up` starts the stack with RED on for that, before the capacity search
  restarts it with RED off. Later boots have nothing to migrate. Keep it that way in T13.
- **k6 1.8, for the runner.** `traffic.js`'s `handleSummary` prints the summary as JSON on stdout, with
  each kind of request counted on its own. In it, `http_req_failed`'s `passes` is the number of failed
  requests, and `dropped_iterations` is left out entirely when none dropped. `--no-summary` is deprecated,
  and with it `--summary-export` writes nothing. A run of R requests a second for D seconds sends R×D+1,
  one at each end. Warm the app before a delayed run: a cold one opening its database connections
  through a 100 ms delay fell behind at 20 a second, and k6 dropped 23 requests.
- **What a run costs.** On a Mac's Docker Desktop with no limits, `bin/benchmark-load`'s search tried 11
  rates in 19 minutes: it held 800 a second with RED off and not 880, and chose 400. That isn't a shape's
  figure. A restart takes about 6 s. k6 peaked at 1.23 GiB with all 5,120 VUs of an overloaded 1,280 a
  second, about 0.24 MiB each, so its memory isn't a worry at these rates. At 10% over capacity, a 60 s
  probe dropped 3,320 requests, so the probe is long enough to see a small overload.
- **`RED=off` still defines `RailsErrorDashboard::VERSION`.** Bundler reads a path gem's gemspec at boot, and
  RED's requires `version.rb`. No RED class, middleware, error subscriber or route loads, so the design's
  "two images" clause, which watches for a RED class, hasn't fired.
- **Several 0.17 decisions reverse on benchmark numbers.** These are in
  `_shipped/capture-hardening-0-17` and `_shipped/functional-fixes-0-17`, and the benchmark now
  measures them. On the CI runner, all under their thresholds: message filtering 48 µs (reverses
  above 1 ms), params fitting 2.2 ms (above 5 ms), the reopen fallback 2.5 ms (above 5 ms).
- **Benchmark numbers:** compare only runs on the same CPU, and read the CPU line first. `ubuntu-latest`
  hands out at least four. The health snapshot's median is about 0.45 ms on an EPYC 9V45, 0.8 ms on a
  7763, 0.66 to 0.85 ms on a 9V74 and 1.15 to 1.24 ms on a Xeon 8573C, on identical code. A Mac can't
  test that row, because its procfs reads return nil there.
- **Commands:**
  - prefix bundle and commit with `env -u RAILS_VERSION mise exec ruby@3.4.5 --`;
  - doc-only commits use `LEFTHOOK_EXCLUDE=chaos-tests`;
  - the pre-commit `bundle-audit` reads the gitignored local `Gemfile.lock`, which CI never uses. When it
    blocks a commit, update the gems it names with `bundle update --conservative`;
  - the load test needs Docker: `bin/benchmark-load [--rate N]` runs it, and removes the stack after.
    By hand, `docker compose -f benchmark/load/compose.yml up --build --wait`, then `down --volumes`. `LOAD_APP_BOOT=1` adds the examples in `spec/benchmark/load_app_spec.rb` and `load_traffic_spec.rb` that boot
    the app and check it with RED on and off, about a minute on a built image;
  - push over HTTPS and merge with `gh api`;
  - main requires 18 checks and an up-to-date branch. CI shows 19 rows, because `Overhead benchmark`
    isn't required. `Upgrade Path` is required but runs only on a release PR or a change under
    `db/migrate/`; skipped, it counts as passing.
- **Commit and PR titles:** no `!` and no `BREAKING CHANGE` before 1.0, because either one proposes 1.0.0.
  Issue references say `Refs #N` with no colon, never `Closes`, `Fixes` or `Resolves`.
