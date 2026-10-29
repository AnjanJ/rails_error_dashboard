# Design: Migrations that roll back what they add (issue #326)

## Approach
- **The 26 migrations change from `change` to `up`/`down`,** on the model of
  `20261015000002_add_capture_source_to_error_occurrences_and_error_logs.rb`, including its comment
  explaining why.
  - `up` keeps today's guard and body unchanged (REQ-3).
  - `down` removes only what exists:
    - `drop_table <t>, if_exists: true`;
    - `remove_index <t>, name: <n> if index_exists?(<t>, name: <n>)`;
    - `remove_column <t>, <c> if column_exists?(<t>, <c>)`, after removing any index on that
      column.
- **The complete-schema migration is not touched** (REQ-5). It creates and drops the same 7 tables.
- **Two new specs in `spec/db/migrations/`:**
  - a round-trip spec that runs each guarded migration through down and up on a scratch database
    (REQ-4, REQ-6);
  - a static spec that parses every file in `db/migrate` with Prism and fails on a `change` that
    returns early on an existence check (REQ-7). This is the same parse used to find the 26.
- **The docs** (REQ-8): `docs/TROUBLESHOOTING.md:93-94` and `docs/GLOSSARY.md:408`, plus their
  Jekyll copies (`_reference/`), say:
  - what rolls back;
  - where `db:rollback` stops: `20260915000001`, the newest of the four irreversible migrations;
  - that installs from before 0.18.0 keep their old copies;
  - the SQL-free way to remove a leftover table or column by hand
    (`bin/rails runner` with `drop_table` / `remove_column`).

## Decision: Each `down` removes the object if it exists; the database's own refusals surface as errors   (→ REQ-1, REQ-2, REQ-3)

**Context.** The maintainer chose, at the requirements gate, that all 26 behave alike: `down`
removes what the migration adds. Two facts, verified at `6b1dfab`, shape how:
1. **The complete schema shadows 15 of the 26 on a fresh install.** `20251223000000` creates those
   15 objects first, so their own `up` did nothing there.
2. **RED's tables have real foreign keys** (`spec/dummy/db/schema.rb:303-308`):
   - occurrences, comments and cascade patterns reference `error_logs`;
   - `error_logs` and diagnostic dumps reference `applications`.

On an upgraded install, each dependent table was created by a migration later than its parent,
so a rollback in order drops the dependents first. On a fresh install, the complete schema created
parent and dependents together, earlier than either migration. So a `db:migrate:down` of one parent
migration, such as `20251224000001` (create error_logs), meets the dependents still in place.
PostgreSQL and MySQL then refuse to drop the table. SQLite allows it only when the dependents are
empty.

**Alternatives.**
1. `down` drops the object if it exists. Where the database refuses because of a foreign key, the
   migration fails with the database's error, and `schema_migrations` keeps the version (PostgreSQL
   and SQLite DDL run in the migration's transaction).
2. The same, but with `force: :cascade` on `drop_table`, so dependents' constraints go too.
3. `down` drops the object only when no other table depends on it, and otherwise skips it with a
   warning.

**Case for 1.** "Reverted" means the object is gone, or the migration says plainly why it couldn't
be, which is what #326 asks for. A database refusal is correct: removing a parent while children
exist would break the schema at that version. It's the same behavior the user would get from a
hand-written migration. On upgraded installs, rollbacks in order never meet the refusal.

**Case against 1.** On a fresh PostgreSQL or MySQL install, an explicit `db:migrate:down` of one
of the shadowed parent migrations now fails where it used to "succeed". MySQL DDL isn't
transactional, so a multi-step `down` there can stop part-way, the same as any Rails migration on
MySQL. And REQ-1 as worded ("shall leave the database without the object") can't hold in that
state; the database won't allow it. The refinement below records that. Option 2 always succeeds,
but it silently strips foreign keys from tables the complete schema made. Option 3 brings back a
"reverted" that left something in place, the very bug the issue reports.

**Decision.** We chose option 1. **REQ-1 is refined** (wording to confirm at the design gate):
"When any of the 26 guarded migrations is migrated down, it shall leave the database without the
table, column or index that migration adds. If the database refuses because another table still
depends on it, the migration shall fail with that error rather than report success."
**Falsifiability.** We would revisit this if an issue reports a rollback that failed on a foreign
key in a sequence of rollbacks done in order (not an explicit single `migrate:down`).
**Fired-if.** manual

## Decision: The round-trip spec builds a scratch database along both install histories   (→ REQ-4, REQ-6)

**Context.** The existing migration spec (`spec/db/migrations/add_last_notified_at_spec.rb`) runs
one migration against a throwaway table by stubbing its `TABLE` constant. It does so because
dropping a column from the real `error_logs` on SQLite rebuilds the table inside the suite's
schema. The 26 migrations hardcode their table names, so stubbing doesn't carry over. CI's
`adapter-test` job runs every non-system spec on SQLite, PostgreSQL and MySQL
(`.github/workflows/test.yml:135`), so `spec/db/` runs on all three there.

**Alternatives.**
1. For each guarded migration M, a scratch database (a temp file on SQLite; a `CREATE DATABASE`'d
   one on PostgreSQL and MySQL), built two ways:
   - the upgrade history: every migration up to and including M, with the complete schema
     skipped;
   - the fresh history: the complete schema, then every migration up to M.

   Then M down, assert the object is gone (or, on the fresh history, that the migration raised);
   M up, assert it's back.
2. One scratch database at the current schema. Each M goes down and up in place.
3. Refactor all 26 migrations to use `TABLE` constants, and stub them as the existing spec does.

**Case for 1.** It tests the two histories real installs have, in the state each one is in when M
is the newest migration. That's exactly the state where an in-order rollback reverts M. The suite's
own schema is never touched. On the fresh history it pins the refusal behavior from the first
decision, instead of hiding it.

**Case against 1.** Running up to about 50 migrations per case, twice, 26 times, costs time: an
estimate of a few seconds on SQLite, more on the PostgreSQL and MySQL rows. Task T1 measures it.
It needs `CREATE DATABASE` rights on CI (the service containers run as superuser). Locally on
MySQL it hits the known setup gaps (time zone tables, the patched dummy schema). The upgrade
history assumes the incremental chain still builds the schema from empty without the complete
schema, which nothing tests today. If T1 finds it doesn't, this spec found a real upgrade bug.
Option 2 is cheaper, but parents can't be dropped there at all while their children exist, so it
tests little. Option 3 rewrites 26 shipped files twice over.

**Decision.** We chose option 1.
**Falsifiability.** We would fall back to option 2 for the PostgreSQL and MySQL rows if the
round-trip spec adds more than 60 seconds to an `adapter-test` row.
**Fired-if.** manual
