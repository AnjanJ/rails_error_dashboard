---
layout: default
title: "Migration Strategy: Squashed + Incremental"
order: 5
---

# Migration Strategy: Squashed + Incremental

> **Upgrading an app?** Follow [Upgrading](/rails_error_dashboard/docs/upgrading/). This page explains how RED's migrations
> are built, for contributors.

## How Migrations Reach an App

RED's migrations live in the gem's `db/migrate/`. The engine doesn't add that folder to the app's
migration paths, so a migration runs in an app only once it has been copied there:

- **The installer** (`bin/rails generate rails_error_dashboard:install`) copies every migration the
  app doesn't have yet. They go into `db/migrate/`, or into `db/error_dashboard_migrate/` when the
  initializer sets `config.use_separate_database = true`. Each copy is named
  `<timestamp>_<name>.rails_error_dashboard.rb`. The timestamps start at the current time, or just
  after the newest migration already in either folder if that is later, so a re-run never reuses a
  version.
- **`bin/rails rails_error_dashboard:install:migrations`**, Rails' generic task for engines, also
  copies the missing migrations under new timestamps, but by default into `db/migrate/`. That's wrong
  for an app with a separate database (see [Upgrading](/rails_error_dashboard/docs/upgrading/#with-a-separate-database-dont-use-installmigrations)).

Either way, the versions in an app's `schema_migrations` are the timestamps of its copies, not the
gem's filenames. So instructions must never name a gem migration's version, as in
`db:migrate VERSION=20251225102500`: no app has that version.

## A Complete Schema, Then Guarded Steps

The first migration by filename, `20251223000000_create_rails_error_dashboard_complete_schema.rb`,
creates RED's core tables in one step, with the columns and indexes they had when it was last
updated: `applications`, `error_logs`, `error_occurrences`, `cascade_patterns`, `error_baselines`,
`error_comments` and `swallowed_exceptions`. It does nothing when
`rails_error_dashboard_error_logs` already exists.

Every later migration checks before it changes anything (`table_exists?`, `column_exists?`,
`index_exists?`) and skips what is already there. The copies keep the gem's order, so:

- **On a fresh install,** the complete schema runs first. The older steps it already covers find
  their table or column and skip. Steps added after its last update run normally, including the
  tables that have their own migrations, such as `storm_events`, `rack_attack_events` and
  `event_counts`.
- **On an upgrade,** only the steps that are new to the app run. The complete schema skips,
  because `error_logs` exists.

## Rules for a New Migration

1. **Guard every change.** Check that a table, column or index is missing before creating it, and
   present before removing it. The migration must succeed on a fresh install (after the complete
   schema), on an upgrade, and when it runs a second time.
2. **If you fold a change into the complete schema, keep its own migration guarded.** A fresh
   install runs both. In 0.4.0 to 0.8.1 the complete schema created `instance_variables`, and
   `add_instance_variables_to_error_logs` added it again with no guard, so every fresh install of
   those versions stopped at `db:migrate` until 0.8.2 fixed it (see
   [Upgrading](/rails_error_dashboard/docs/upgrading/#stuck-at-dbmigrate-after-installing-040-to-081)).

## Testing

- `bin/pre-release-test full_upgrade` installs the newest published release in a fresh app, then
  upgrades it to your working copy the documented way: the installer with `--no-interactive`, then
  `db:migrate`. It needs network access to rubygems.org.
- `bin/pre-release-test all` runs fresh installs in production mode, one of them on a separate
  database.
