# Handoff

> Written 2026-10-30 on branch `test/benchmark-ci`.

## In flight
- **0.18.0, the 1.0 surface release.** Eight specs under `.shipkit/specs/`, all accepted, with
  `spec-check` at 0 gaps.
  - for the 0.18.0 release: `storm-gate-hot-path` (built, #335), `host-safety-0-18`,
    `migration-rollback` (issue #326), `webhook-v1`, `deprecations-0-18`, `small-fixes-0-18`;
  - their own PRs, with no gem release needed: `overhead-benchmark` (T1-T3 in #334, T4 in #336) and
    `public-api-and-policies`.
- **Four stacked PRs, all based on main; merge in order:** #333 (specs), #334 (benchmark), #335
  (storm check), #336 (the CI job). After each squash-merge, rebase the next one onto main.
- New project records: `0007` (versioning, deprecation and support policy) and `0008` (names frozen
  as they are; `rails_error_dashboard:` is the rake namespace).

## Done
- 0.17.0 shipped 2026-10-29. Its eight specs moved to `.shipkit/specs/_shipped/`, each marked
  "shipped in 0.17.0 (#N)".
- The five 1.0 questions this file used to list are decided: records `0002` to `0006` (#332).
- The storm budget is decided: 15 µs on the CI runner, recorded in `overhead-benchmark/design.md`.

## Next step
1. Merge #333, #334, #335 and #336, in that order.
2. `overhead-benchmark` T5: the README and docs quote the numbers from a green run on main.
3. `host-safety-0-18`, then `migration-rollback`, `webhook-v1`, `deprecations-0-18`,
   `small-fixes-0-18` and `public-api-and-policies`, one PR per spec.
4. The 0.18.0 release PR.

## Path to 1.0
| Release | Target |
|---|---|
| 0.18.0 | about 2026-11-20 |
| 1.0.0.rc1 | early December, then about two quiet weeks |
| 1.0.0 | by 2026-12-31 |

## Open questions
- None.

## Do not forget
- **Reversal clauses that left the automatic scan.** `decision-check.sh` reads only
  `.shipkit/specs/*/design.md`. Archived specs drop out, so these executable clauses from 0.17
  (all HOLDS on 2026-10-29) are no longer checked automatically:
  - `_shipped/live-updates-hardening-0-17`, "Remove the stats broadcast, keep the stats partial":
    fires when a `v1.0.0*` tag exists. **Revisit at 1.0.0.rc1.**
  - Also in `_shipped/live-updates-hardening-0-17`: the actioncable gemspec dependency.
  - `_shipped/live-updates-client`: two clauses.
  - `_shipped/host-hygiene-0-17`: the CDN tag count.
  - `_shipped/test-gaps-0-17`: the PG/MySQL rows in `test.yml`.
  - Earlier: `_shipped/capture-source` (two) and `_shipped/occurrence-context-history` (one).
- **Several 0.17 decisions reverse on benchmark numbers.** These are in
  `_shipped/capture-hardening-0-17` and `_shipped/functional-fixes-0-17`, and the benchmark now
  measures them. On the CI runner, all under their thresholds: message filtering 48 µs (reverses
  above 1 ms), params fitting 2.2 ms (above 5 ms), the reopen fallback 2.5 ms (above 5 ms).
- **Benchmark numbers:** compare runs from the CI job, not from a laptop. The two machines are
  about 2.7x apart. The health snapshot's Mac number means nothing, because its procfs reads return
  nil on macOS: it's about 800 µs on the runner, against 1 ms.
- **Commands:**
  - prefix bundle and commit with `env -u RAILS_VERSION mise exec ruby@3.4.5 --`;
  - doc-only commits use `LEFTHOOK_EXCLUDE=chaos-tests`;
  - push over HTTPS and merge with `gh api`;
  - main needs 29 green checks, and its branch must be up to date.
- **PR bodies for #326 say "Refs #326",** never "Closes".
