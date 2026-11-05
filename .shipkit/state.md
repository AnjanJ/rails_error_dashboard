# Handoff

> Written 2026-11-05 at commit `515418e`, with T9 to T15 of the deploy shape benchmark built on a branch.

## In flight
- **`deploy-shape-benchmark`** is the one open spec. It measures what RED adds on the shape of a deploy
  target, in GitHub CI, by hand. The maintainer chose CI only on 2026-10-31: no servers, accounts or spend.
  It comes before rc1, because a code change for small boxes after rc1 would restart the quiet period.
  - T1 merged in #346, and T2-T8 in #347 (`37ceb3f`): the rows run on PostgreSQL with Solid Queue or
    Sidekiq, and report the CPU, its limits and the time stolen.
  - T9 to T15 are committed on `test/benchmark-load-app`, and go up as one pull request. T9 is the load test's app in
    `benchmark/load/`, a new Rails 8.1 app with RED added by its installer: it booted in compose, and a
    failing request reached RED's table through Solid Queue. T10 runs the same image without RED when
    `RED=off`: the same request then left RED's table empty. T11 is `benchmark/load/traffic.js`, k6 at a
    fixed arrival rate in three mixes, with compose's `k6` service pinned by digest. T12 is
    `bin/benchmark-load`: with no rate given, it finds the most the app holds with RED off and uses half,
    and `--rate N` skips that search. The search lives in `benchmark/load/runner.rb`, and its specs drive
    it with a fake. `compose_driver.rb` runs it in Docker, and is checked against the stack with
    `LOAD_APP_BOOT=1`. T13 runs the windows: for each mix, five pairs of RED off and on in ABBA order,
    each a restart, 60 s of warm-up thrown away and 120 s measured, all at the one rate. Run for real with
    5 s windows at 10 a second, all 30 held, and RED recorded only in its on windows.
  - T14 is the report, printed by `bin/benchmark-load` in Markdown, with `--json` and `--summary`. For
    each mix, p50, p95 and p99 with RED off and on, each the median of that side's windows, and what RED
    added: the median of each pair's on minus off, every pair's beside it, negatives as they are. Then
    every window, with the CPU time stolen during it. Its environment block is `bin/benchmark`'s, read
    inside the app's container.
  - T15 judges each window as a probe is judged. One that dropped requests, got a status its kind doesn't
    expect, or didn't finish is invalid: it's listed with its reason, it leaves its side's median, and
    its pair leaves what RED added.
  - **The delay check, T14's "Done when".** At 20 a second with 3 s warm-ups and 8 s windows, RED added
    +0.24, +0.04 and +0.19 ms at p50 (healthy, failing, storm). With `sleep 0.02` at the top of
    `ErrorCatcher#call` it read +27.19, +26.94 and +27.50 ms, every pair between 25.8 and 28.2. Most of
    the 7 ms over 20 is the sleep itself: 500 timed `sleep 0.02` calls took 23.9 ms at p50 (p95 25.1) in
    the app's image, and 24.9 ms on the Mac outside Docker. That leaves about 3 ms unexplained, which the
    maintainer has to accept or ask to have chased down.
- **PR #349, `fix/keep-module-name`,** is open with every check green, and waits for the maintainer's
  merge. Merging it makes release-please propose 0.18.1, and releasing that needs the maintainer's yes.
- No release PR is open.

## Done
- 0.18.0 shipped 2026-10-31, about three weeks ahead of its target. RubyGems, the GitHub Release, both
  tags and the demo all carry it. Its eight specs moved to `.shipkit/specs/_shipped/`, each marked
  "shipped in 0.18.0 (#N)".
- Issue #326 is closed. #341 fixed it on 33 migrations, not the 26 in its title.

## Next step
1. Get the load test's pull request (T9-T15) through CI and the maintainer's merge. Then T16-T18, the
   shapes, and T19-T20, the compare tool and the research file, all before rc1.
2. Plan and spec 1.0.0.rc1:
   - raise the floors to Rails 7.2 and Ruby 3.3, and CI from 20 rows to 9 (decision `0003`);
   - a tested 0.x to 1.0 upgrade;
   - how the version gets set: release-please has no `bump-minor-pre-major`, and `Release-As:` survives
     a squash, but check how it spells a prerelease first;
   - the demo: its `~> 0.9` pin excludes 1.0.0, and its update workflow won't deploy a release candidate;
   - the reversal clauses marked "Revisit at 1.0.0.rc1" below;
   - re-read `docs/PUBLIC_API.md` and `docs/VERSIONING.md`, which are the freeze.

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
  was drawn. The shape benchmark runs on the same runners, so it won't settle this.
- **The health snapshot misses 1 ms on arm64.** On #347's dispatch (run 41216679726, `a5e5c47`), all three
  arm64 rows read 1.23 to 1.27 ms on a Neoverse-N2, against the 1 ms budget, while every x64 row passed
  (0.51 to 0.69 ms). The gated job runs only on x64, so CI can't see it. The `medium-arm` shape will meet it.
  Is the budget per architecture?
- **`AiAgentClassifier.name(user_agent)` replaces `Class#name` for that class.** A host app's code that calls
  `name` on every class, as `ObjectSpace.each_object(Class).map(&:name)` does, raises ArgumentError once RED
  is loaded. Found 2026-11-04, and fixed in PR #349: spec `keep-module-name`, the lookup renamed to
  `agent_name`, and a check over every RED class. Its review passed, and so did its 29 checks. It's a
  `fix:`, so merging it makes release-please propose 0.18.1.

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
    with no capture-path change. **The count is 1** (`5ec8a3c`).
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
- **Two Dependabot alerts stay open until rc1.** Both are sqlite3 in the development Gemfile
  (GHSA-mwm8-39rw-8826 and GHSA-28hh-pr2h-2w89), from its Rails 7.0 branch, `~> 1.4`, because no 1.x
  release fixes them (#331). Raising the floor to Rails 7.2 at rc1 removes that branch.
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
  - main requires 29 checks and an up-to-date branch. CI shows 30 rows, because `Overhead benchmark`
    isn't required.
- **Commit and PR titles:** no `!` and no `BREAKING CHANGE` before 1.0, because either one proposes 1.0.0.
  Issue references say `Refs #N` with no colon, never `Closes`, `Fixes` or `Resolves`.
