# Handoff

> Written 2026-11-20 at commit `26be8d80` on spec/hardening-1-0-rc2.

## In flight
- **`hardening-1-0-rc2`** (`.shipkit/specs/hardening-1-0-rc2/`): spec, design and tasks are committed (`26be8d80`), and T1-T31 are all unstarted. It fixes the verified findings of the independent rc.1 review in 1.0.0-rc.2, due 2026-12-11. Anything late goes in an rc.3 by 2026-12-17, then 1.0.0 by 2026-12-31. `intake.md` holds the maintainer's eight answers.
- The branch `spec/hardening-1-0-rc2` isn't pushed and has no PR. Its 6 files are only under `.shipkit/`.
- **`release-1-0-rc1`** stays open. Its last release step now points 1.0.0 at rc.2.

## Done this session
- Re-verified all 34 review claims: 30 hold, 2 are wrong (the "issue per day" claim and the outside-contributor count), 2 are partly right. All six notification channels drop failed alerts.
- Reproduced on Rails 8.0.4 and SQLite only: absolute-path grouping, merged NameErrors, `<internal:` frames, captures lost to a rollback or `while_preventing_writes`, a 4.01 s block on a starved pool, and the 24 h rollover.
- Dotfiles `d94e328` (on main, not pushed) removed the global `RAILS_VERSION="8.0.4"`. The local bundle is now Rails 8.1.4.1 and Puma 8.1.2, `bundle-audit` is clean, and the full suite passes (7,148 examples, 0 failures).

## Next step
Start T1, spike S1 (`tasks.md` T1): probe rollback, prevented writes and a held pool on SQLite, PostgreSQL 16 and MySQL 8, under Rails 7.2, 8.0 and 8.1, in sync and async (Solid Queue) modes, and write `.shipkit/research/host-conditions-spike.md` by 2026-12-04.

## Open questions
- Ask before pushing `spec/hardening-1-0-rc2` and opening its PR.
- The maintainer picks S2's option before any change to `log_level`. Host safety comes first.
- Delete the merged dotfiles branch `fix/drop-stale-rails-version`? Ask first.

## Do not forget
- A shell started before `d94e328` still has `RAILS_VERSION=8.0.4`, and a `bundle` run there resets the lockfile to 8.0.4. Prefix with `env -u RAILS_VERSION` (git commits too) until the shell restarts.
- The copied test DB is stale: run `RailsErrorDashboard::TestSchema.build!` in a probe, or every capture fails silently at `log_level :silent`.
- `while_preventing_writes` fails on "Write query" on SQLite; PostgreSQL and MySQL should fail on "Lock query" (FOR UPDATE). Check both.
- Phase G exists, so the new chaos phase is `phase_q`. The PostgreSQL and MySQL adapter jobs run Rails 8.1 only (`test.yml:104`).
- Rules: commit with `LEFTHOOK_EXCLUDE=chaos-tests` only for docs-only commits; write "Refs #N"; one commit per task, staged by name; every merge, release, push or setting change needs a yes.
