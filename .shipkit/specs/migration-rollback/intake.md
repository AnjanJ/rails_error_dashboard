# Intake: migrations that say "reverted" and drop nothing (issue #326)

> Intake taken on 2026-10-29.

## Request
Issue #326: 26 of the 52 migrations start `change` with `return if table_exists?`, `column_exists?`
or `index_exists?`. On revert, Rails replays `change` under a recorder, the guard sees the object
and returns, and Rails prints "reverted" having dropped nothing. Fix them on the model of
`20261015000002_add_capture_source_…` (`up`/`down`, with its comment), add a spec, and fix the docs.

## Serves goal
"Ship 1.0" (`.shipkit/product.md`): the research's policy that migrations in a minor are additive
and replay-safe also needs their `down` to be truthful.

## Verified at 6b1dfab (by parsing every migration with Prism)
- The 26 are exactly the issue's list: 15 table guards, 9 column guards, 2 index guards.
- **15 of the 26 add an object that the complete-schema migration (`20251223000000`) also creates on
  a fresh install.** These are the first 14 by timestamp, through `20260306000003`, plus
  `20260323000001` (`muted`). On a fresh install their `up` did nothing.
- **11 own their object outright:** the tables `diagnostic_dumps`, `storm_events`,
  `rack_attack_events`, `storm_flush_batches`, `event_counts`, `event_timing_gaps`,
  `missing_translations`, `error_occurrence_contexts`, and the columns `rack_attack_events.user_agent`,
  `error_logs.environment` and `storm_events.buckets_incomplete`.
- **Correction to the issue and the handoff:** the complete-schema `down` does not "miss 8 tables".
  It creates 7 tables and drops those 7. The other 8 are created by their own migrations, and those
  migrations' broken `down` is why a full rollback leaves them in place.
- **`db:rollback` can reach only 6 of the 26.** Four migrations raise `IrreversibleMigration`; the
  newest is `20260915000001`, so `db:rollback` stops there. The other 20 are reachable only with an
  explicit `db:migrate:down VERSION=…`, which is how the issue reproduces them.

## Conflicts found
- **Paramount: migrations run inside the host app's deploy and must stay replay-safe.** Each `up`
  keeps its guard, so a shared database and a re-run still work.
- **Decision 0001:** not affected.
- **Data loss on a rollback is what a rollback does.** But on a fresh install, reverting one of the
  15 would drop an object that the complete schema made, while the complete-schema migration still
  counts as run. That's the design question this spec settles. The design step records it.

## Answers
None asked. The issue's direction is accepted, and the design records the fresh-install subtlety.

## Assumptions made
- **Existing installs keep their copied migrations** (the installer skips names it already copied).
  Only the docs reach them.
- **The PR body says "Refs #326"**, never "Closes"; the maintainer closes the issue.

## Out of scope
- Making the four `IrreversibleMigration` migrations reversible.
- Rewriting the complete-schema migration.
