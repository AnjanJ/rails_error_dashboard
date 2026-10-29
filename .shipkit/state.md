# Handoff

> Written 2026-10-29 on branch `spec/0-18-0`, from main `6b1dfab`.

## In flight
- **0.18.0, the 1.0 surface release, is fully specced.** Seven specs under `.shipkit/specs/`. The
  requirements, designs and tasks were all accepted on 2026-10-29, and `spec-check` shows 0 gaps.
  No code yet.
  - for the 0.18.0 release: `deprecations-0-18`, `webhook-v1`, `host-safety-0-18`,
    `migration-rollback` (issue #326), `small-fixes-0-18`;
  - their own PRs, with no gem release needed: `overhead-benchmark` (goes first, for the 1.0
    launch story) and `public-api-and-policies`.
- The scope answers are in each spec's `intake.md`. Design-gate refinements are marked in the
  specs they changed:
  - `migration-rollback` REQ-1 (foreign-key refusals);
  - `public-api-and-policies` REQ-1 (names linked, not a second table);
  - `small-fixes-0-18` REQ-3 (all four badge views);
  - `host-safety-0-18` REQ-8 (the user count).
- New project records: `0007` (versioning, deprecation and support policy) and `0008` (names frozen
  as they are; `rails_error_dashboard:` is the rake namespace).

## Done
- 0.17.0 shipped 2026-10-29. Its eight specs moved to `.shipkit/specs/_shipped/`, each marked
  "shipped in 0.17.0 (#N)".
- The five 1.0 questions this file used to list are decided: records `0002` to `0006` (#332).

## Next step
Open the spec PR from `spec/0-18-0` (docs only), then implement in this order, one PR per spec:
1. `overhead-benchmark`;
2. `host-safety-0-18`;
3. `migration-rollback`;
4. `webhook-v1`;
5. `deprecations-0-18`;
6. `small-fixes-0-18`;
7. `public-api-and-policies`;
8. the 0.18.0 release PR.

## Path to 1.0
| Release | Target |
|---|---|
| 0.18.0 | about 2026-11-20 |
| 1.0.0.rc1 | early December, then about two quiet weeks |
| 1.0.0 | by 2026-12-31 |

## Open questions
- None. All seven specs' requirements were accepted on 2026-10-29. The design of each still needs
  approval.

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
  `_shipped/capture-hardening-0-17` and `_shipped/functional-fixes-0-17`: params fitting, message
  filtering, the reopen fallback. `overhead-benchmark` REQ-3 measures them; check the clauses once
  it runs.
- **Commands:**
  - prefix bundle and commit with `env -u RAILS_VERSION mise exec ruby@3.4.5 --`;
  - doc-only commits use `LEFTHOOK_EXCLUDE=chaos-tests`;
  - push over HTTPS and merge with `gh api`;
  - main needs 29 green checks, and its branch must be up to date.
- **PR bodies for #326 say "Refs #326",** never "Closes".
