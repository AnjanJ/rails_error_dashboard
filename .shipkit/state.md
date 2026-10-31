# Handoff

> Written 2026-10-31 at commit `5ec8a3c`, after 0.18.0 shipped.

## In flight
- Nothing is being built. `.shipkit/specs/` holds no live specs, and no release PR is open.
- **RED's overhead on real deploy hardware** is being planned. It needs paid servers, so it needs the
  maintainer's OK and a budget before any server exists. It comes before rc1 (decided 2026-10-31),
  because a code change for small boxes after rc1 would restart the quiet period.

## Done
- 0.18.0 shipped 2026-10-31, about three weeks ahead of its target. RubyGems, the GitHub Release, both
  tags and the demo all carry it. Its eight specs moved to `.shipkit/specs/_shipped/`, each marked
  "shipped in 0.18.0 (#N)".
- Issue #326 is closed. #341 fixed it on 33 migrations, not the 26 in its title.

## Next step
1. Get the deploy-hardware benchmark's plan and budget approved, then run it, before rc1.
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
  was drawn, so the deploy-hardware results should set the budget.

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
  - push over HTTPS and merge with `gh api`;
  - main requires 29 checks and an up-to-date branch. CI shows 30 rows, because `Overhead benchmark`
    isn't required.
- **Commit and PR titles:** no `!` and no `BREAKING CHANGE` before 1.0, because either one proposes 1.0.0.
  Issue references say `Refs #N` with no colon, never `Closes`, `Fixes` or `Resolves`.
