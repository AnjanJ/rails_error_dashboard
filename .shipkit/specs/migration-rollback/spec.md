# Spec: Migrations that roll back what they add (issue #326)

> Spec accepted at commit `6b1dfab` on spec/0-18-0 (2026-10-29).
> Status: open
> Paths: db/migrate/,spec/db/,spec/support/migration_round_trip.rb,spec/docs/rollback_docs_spec.rb,docs/TROUBLESHOOTING.md,docs/GLOSSARY.md,_reference/,_guides/

## Purpose
33 of RED's migrations print "reverted" and drop nothing. That leaves the database's schema newer
than the version `schema_migrations` reports. Every migration RED ships should do what it says in
both directions, and the docs should say exactly what can and can't be rolled back.

## User stories
- As a developer rolling back after a bad deploy, I want "reverted" to mean the table or column is
  gone, so that my schema matches the version Rails reports.
- As a developer on a shared or re-run database, I want every migration to stay safe to run twice,
  so that the fix doesn't break deploys.

## Requirements (EARS)

### Down undoes up
- **REQ-1.** When any of the 33 guarded migrations is migrated down, it shall leave the database
  without the table, column or index that migration adds. If the database refuses because something
  still depends on it, another table or an index a later migration added, the migration shall fail
  with that error rather than report success.
  (Refined at the design gate, 2026-10-29: RED's foreign keys make the database refuse on a fresh
  install, where the complete schema created parent and dependent tables together; see
  `design.md`.)
  (Corrected during the build, 2026-10-30: the issue listed 26, the migrations that return early
  from `change`. Seven more guard with `unless` and have the same bug; see `design.md`.)
  (Widened at review, 2026-10-30: "another table" became "another table or a later index", after a
  run from a fully migrated database; see `design.md`.)
- **REQ-2.** When a guarded migration is migrated down and its object doesn't exist, the migration
  shall succeed and change nothing.
- **REQ-3.** Each guarded migration's `up` shall stay replay-safe. When its object already exists,
  `up` does nothing and succeeds, as today.
- **REQ-4.** Each of the 33 shall survive up, down, up and end with its object present. This holds
  on SQLite in the main suite, and on PostgreSQL and MySQL in the CI rows that run them.
- **REQ-5.** The complete-schema migration's `down` shall keep dropping the 7 tables it creates. No
  change.

### It stays fixed
- **REQ-6.** A spec shall run every migration in `db/migrate` that has a guarded `up` through up,
  down and up against a scratch database, and fail if `down` leaves the object in place. The
  complete schema has REQ-5 instead, and a migration that raises `IrreversibleMigration` on any
  database can't round-trip on all three, so it's left out and REQ-8 documents it. (Carve-out
  written down at review, 2026-10-30.)
- **REQ-7.** A spec shall fail when a migration in `db/migrate` defines `change` and branches on an
  existence check, by an early return or a modifier. (Widened 2026-10-30: "returns early" would
  have missed the seven.)

### The docs
- **REQ-8.** The rollback docs (`docs/TROUBLESHOOTING.md` and `docs/GLOSSARY.md`, plus their
  Jekyll copies) shall say:
  - which four migrations can't be rolled back, and that `db:rollback` stops at the newest of them
    (`20260915000001`);
  - that apps installed before 0.18.0 keep their old migration copies, whose `down` does nothing
    for these 33;
  - how to remove a leftover table or column by hand.

## Out of scope
- Making the four `IrreversibleMigration` migrations reversible.
- Changing what any `up` does.
