# Design: Migrations that roll back what they add (issue #326)

## Approach
- **The 33 migrations change from `change` to `up`/`down`,** on the model of
  `20261015000002_add_capture_source_to_error_occurrences_and_error_logs.rb`, including its comment
  explaining why.
  - `up` keeps today's guard and body unchanged (REQ-3).
  - `down` removes only what exists:
    - `drop_table <t>, if_exists: true`;
    - `remove_index <t>, name: <n> if index_name_exists?(<t>, <n>)`. Not `index_exists?`: on Rails
      7.1 its column argument is required, so a call with only `name:` raises;
    - `remove_column <t>, <c>` after checking `table_exists?` and then `column_exists?`, and after
      removing any index on that column. `column_exists?` raises on a missing table on all three
      databases. SQLite and MySQL keep the index if it isn't removed first; PostgreSQL drops it.
- **The complete-schema migration is not touched** (REQ-5). It creates and drops the same 7 tables.
- **Two new specs in `spec/db/migrations/`:**
  - a round-trip spec that runs each guarded migration through down and up on a scratch database
    (REQ-4, REQ-6);
  - a static spec that parses every file in `db/migrate` with Prism and fails on a `change` that
    branches on an existence check (REQ-7).
- **The docs** (REQ-8): `docs/TROUBLESHOOTING.md:93-94` and `docs/GLOSSARY.md:408`, plus their
  Jekyll copies (`_reference/`), say:
  - what rolls back;
  - where `db:rollback` stops: `20260915000001`, the newest of the four irreversible migrations;
  - that installs from before 0.18.0 keep their old copies;
  - the SQL-free way to remove a leftover table or column by hand
    (`bin/rails runner` with `drop_table` / `remove_column`).

## Correction: 33 migrations, not 26 (2026-10-30)

The records below say 26, the issue's count, which is the migrations that return early from
`change`. The round-trip harness showed the same bug on seven more, whose guard is inside `change`:

```ruby
def change
  add_column :t, :c, :text unless column_exists?(:t, :c)
end
```

On revert the column exists, so `add_column` is skipped, nothing is recorded, and Rails prints
"reverted". The seven add 13 columns and no table, so they get the same fix and meet no foreign-key
refusal. The decisions below hold for all 33.

The harness also runs the 13 migrations that already had `up` and `down`, because REQ-6 says every
guarded `up`. Those never misreported: their `down` removes the object, or raises. Some raise on an
object that's already gone, which is a loud failure and not this bug, so they're unchanged.

One of the 13 had a real bug of its own. `20260106094318` called `remove_foreign_key` with only a
column, and on SQLite before Rails 8.1 that guesses the table from the column name, as `applications`,
and raises. So it could never roll back there. Only the CI matrix showed it: both adapter rows and
every local run are on 8.1. Naming the table fixes it on every version.

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

**Found at T3 (2026-10-30).**
- **On a fresh install, exactly two are refused,** on PostgreSQL and MySQL: `error_logs` and
  `applications`, the two parent tables, each with its version kept. SQLite refuses neither,
  because the dependents are empty. The spec requires those two refusals, so a `force: :cascade`
  fails it on PostgreSQL. On MySQL `CASCADE` does nothing, and the database still refuses.
- **`create_rails_error_dashboard_error_logs` isn't replay-safe while it's the newest.** Its guard
  also wants `application_id`, which a later migration adds, so a second `up` at that point raises
  "already exists", as it has since it shipped. REQ-3's "as today" and the out-of-scope line
  ("changing what any `up` does") both leave that alone, and the spec pins it.
- **`add_optimized_indexes` already had a `down`, which never ran:** with `change` defined, Rails
  reverses `change`. It runs now, so it tolerates what isn't there.
- **From a fully migrated database, found at review.** The harness took each migration down while
  it was the newest, but `db:migrate:down VERSION=` on a fully migrated database is a different
  state, and it's the one the issue reproduces. All 33 were run from there, on all three databases.
  None reported success with its object in place.
  - PostgreSQL and MySQL refuse only the two parents, as above.
  - SQLite also refuses `add_better_tracking_to_error_logs` and `add_environment_to_error_logs`,
    and on the upgrade history `add_workflow_fields_to_error_logs`, with `no such column`. It
    rebuilds the table to remove a column, and re-creating a later migration's index fails,
    because that index still names the column. The migration stays recorded and nothing changes.
  - **Refused, not forced.** The alternative is for `down` to drop that later index first. One of
    them is `index_error_logs_on_group_identity`, the unique index that stops duplicate groups,
    and it belongs to an irreversible migration, so nothing would put it back. A loud refusal is
    this decision's own rule, so REQ-1 now says "another table or an index a later migration added".
  - The spec pins this on SQLite and PostgreSQL by rolling each `down` back. MySQL can't roll DDL
    back and would need a rebuild per migration, so that result came from a run by hand.
- **A single-column index goes with its column on all three databases,** so `remove_index` before
  `remove_column` only changes the result for a composite index (SQLite and MySQL keep a narrower
  one). It stays for every index, as this design says.

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

**Measured at T1 (2026-10-30, M3 Max).**
- **The chain builds without the complete schema** on all three databases: 52 migrations, 15 tables.
  So the upgrade history found no upgrade bug.
- **A whole chain costs** about 0.3 s on SQLite, 0.5 s on PostgreSQL and 1 to 1.4 s on MySQL. A build
  per case averages half a chain, so 52 cases are about 30 seconds on MySQL here. That is an
  estimate of about 80 seconds on a CI runner, past this decision's limit, so the harness doesn't
  rebuild per case.
- **It walks each history once instead,** and takes a migration down and up while it's the newest.
  That's the same state a per-case build gives, because a round trip that doesn't restore the schema
  rebuilds it before the walk goes on.
- **It runs in its own process,** where `ActiveRecord::Base` is the scratch database. Several
  migrations reach for `ActiveRecord::Base` or RED's models, some to write, and in the suite's
  process those are the suite's database.
- **The spec file with one migration on both histories,** process boot included: 1.9 s on SQLite,
  4.1 s on PostgreSQL, 5.2 s on MySQL.
- **All 26 at T3:** a whole run of 5.4 s on SQLite, 11.4 s on PostgreSQL and 13.9 s on MySQL.
- **All 46 on CI, measured:** 36.9 seconds on the MySQL row and 15.6 on the PostgreSQL row, against
  the 60-second limit, so option 1 holds. The spec prints this into the job log. A row's total can't
  answer this: with the spec added, the same run saw MySQL's suite 39 seconds slower and PostgreSQL's
  24 seconds faster than a run without it, so noise between runs is about the size of the cost.
- **With the run from a fully migrated database added:** 37.8 seconds on MySQL, which skips it, and
  30.4 on PostgreSQL.
