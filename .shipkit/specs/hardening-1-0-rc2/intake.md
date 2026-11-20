# Intake: 1.0 hardening (1.0.0-rc.2)

> Intake taken on 2026-11-20.

## Request
Verify every finding of the independent 1.0.0-rc.1 review and plan a sprint that fixes each one. After
the verification (34 claims: 30 hold, 2 wrong, 2 partly right), the maintainer decided:

1. The vehicle is 1.0.0-rc.2, due 2026-12-11.
2. Fingerprint v2: the first app frame's path relative to `Rails.root`, its method name, and
   `NameError#name`; no line numbers. Rows already grouped under v1 keep their occurrences.
3. Host conditions (a capture inside a host transaction that rolls back, inside a write-prevented block,
   or with a starved connection pool): spike first, on SQLite, PostgreSQL and MySQL, across Rails 7.2,
   8.0 and 8.1, then implement from the evidence.
4. The `rubygems` environment requires the maintainer's approval ("keep a human check for now, revisit if
   it becomes a bottleneck"). No pull-request review rule. `rubygems_mfa_required` only after checking it
   works with trusted publishing.
5. An opt-in `occurrence_retention_days`, off by default, before 1.0.
6. Notifications become at-least-once, and webhook posts carry a delivery id that stays the same across
   retries.
7. The audit trail records the logged-in user from a new setting, before 1.0.
8. The `log_level` default changes only after a spike shows the host-safety implications: "we don't want
   to do anything against our core rules for the host app safety".

## Serves goal
Ship 1.0 — metric: v1.0.0 published on RubyGems with config and public API frozen; target: released; by:
2026-12-31

## Conflicts found
- **Decision 0002** (`.shipkit/decisions/0002-1-0-is-a-stability-release.md`): 1.0 is stability-only,
  nothing new. Items 5 and 7 add two settings before 1.0. Its reversal condition (the Full Context Error
  Report needing a breaking change) has not fired. **Decided:** amend 0002 with a dated scope note
  allowing these two opt-in settings, off by default, so their names are frozen deliberately.
- **Open spec `release-1-0-rc1`** (`tasks.md:104`) goes from rc.1's quiet weeks straight to 1.0.0.
  **Decided by the request:** rc.2 comes first; that spec gets a note pointing here.
- No conflict with decision 0005 (webhook contract v1): new fields and headers may be added in 1.x
  (`0005-webhook-contract-v1.md:62`).

## Answers
1. Amend decision 0002 for the two settings? — **Yes, both** (occurrence retention and the audit actor).
2. Which release gets the host-condition fixes if the spike succeeds? — **rc.2, if the spike and the fix
   pass on all three databases by 2026-12-04**; otherwise they follow the cutoff rule below.
3. What happens to a workstream not ready by 2026-12-11? — **It ships in an rc.3 by 2026-12-17**, which
   leaves about two quiet weeks before 2026-12-31.

## Assumptions made
- An opt-in, off-by-default retention setting is not a quota RED imposes, so it does not break the
  non-goal "no quotas on the user's own data" (`.shipkit/product.md`, Non-goals).
- Any new write path for host conditions sits on the request path, so it must be possible to switch off
  by config (`.shipkit/product.md`, Non-goals: "no feature on the request path that cannot be switched off
  by config").
- Every migration in this sprint is replay-safe and runs inside the host's deploy (`.shipkit/product.md`,
  Constraints; decision 0007, "migrations: in a minor, additive and replay-safe").
- Every capture-path change re-runs `bin/benchmark` against the budgets (capture < 5 ms before the
  response, storm check < 15 µs), as `.shipkit/product.md` requires.
- The earlier review's "issue per day" and "three outside PRs" claims were wrong and get no work.

## Out of scope
- Roles and permissions (a feature; not in 1.x's plan).
- Rewriting the 513 inline `style` attributes into classes.
- Editing migrations already shipped (hosts have run them); only new migrations and a repair migration.
  One exception: REQ-16 changes the `user_id` type default in the complete-schema migration, which only a
  fresh install runs.
- The MySQL gap in the group-identity unique index (documented in its migration as deliberate).
- GitHub stars and contributor counts.
- `ErrorHashGenerator.from_attributes`, the fallback recipe for rows created without a hash.
