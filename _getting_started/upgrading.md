---
layout: default
title: "Upgrading Rails Error Dashboard"
order: 4
---

# Upgrading Rails Error Dashboard

Every upgrade uses the same three commands. Some releases also need a step of their own, so check
[the list below](#releases-that-need-a-step) for every version between yours and the new one.

## The upgrade

```sh
bundle update rails_error_dashboard
bin/rails generate rails_error_dashboard:install --no-interactive
bin/rails db:migrate
```

Then commit the new migration files along with `Gemfile.lock`, and deploy. To check the result,
run `bin/rails error_dashboard:verify`.

On an app that already has RED, the installer:

- keeps `config/initializers/rails_error_dashboard.rb` as it is, so options added since you
  installed use their defaults until you set them;
- leaves the route in `config/routes.rb` alone;
- copies only the migrations your app doesn't have yet. With a separate error database
  (`config.use_separate_database = true` in the initializer) they go to `db/error_dashboard_migrate/`,
  and otherwise to `db/migrate/`.

`--no-interactive` skips the setup questions. The answers can't change your existing initializer.
On an app that shares its main database, a different answer to the database question would copy
the new migrations into a folder that no database migrates.

`bin/rails db:migrate` migrates every database in `config/database.yml`, the error database
included. To migrate only that one, run `bin/rails db:migrate:error_dashboard`.

### With a separate database, don't use `install:migrations`

The release notes for 0.11.0, 0.12.0 and 0.13.0 say to run
`bin/rails rails_error_dashboard:install:migrations`. That is Rails' generic task for engines, and
it always copies into `db/migrate/`. On an app with a separate error database it copies every RED
migration there, and the next `db:migrate` builds all of RED's tables in your main database. Use
the installer, as above. On an app without a separate database, the two copy the same files.

### Deploying

- Run the migrations in the deploy that ships the new version: `bin/rails db:migrate`, or
  `bin/rails db:prepare`, which is what the Docker entrypoint of a new Rails app runs.
- With a separate database, every environment in `config/database.yml` needs the
  `error_dashboard` entry, with `migrations_paths: db/error_dashboard_migrate`. If an environment
  has no entry, RED logs a warning at boot and writes its errors to the main database instead.

## Releases that need a step

Upgrading across several versions? Do every row between your version and the new one. Each version
links to its full notes in the [CHANGELOG](https://github.com/AnjanJ/rails_error_dashboard/blob/main/CHANGELOG.md).

| Release | What to do |
|---|---|
| [0.8.2](https://github.com/AnjanJ/rails_error_dashboard/blob/main/CHANGELOG.md#082-2026-06-22) | Only if a fresh install of 0.4.0 to 0.8.1 stopped at `db:migrate`: see [Stuck at db:migrate](#stuck-at-dbmigrate-after-installing-040-to-081). |
| [0.9.1](https://github.com/AnjanJ/rails_error_dashboard/blob/main/CHANGELOG.md#091-2026-08-24) | **Can stop your app booting.** Outside `development` and `test`, RED refuses to boot on the default credentials (`gandalf` / `youshallnotpass`). Set `ERROR_DASHBOARD_USER` and `ERROR_DASHBOARD_PASSWORD` in every other environment. See [Dashboard Credentials](/rails_error_dashboard/docs/guides/configuration/#dashboard-credentials). |
| [0.11.0](https://github.com/AnjanJ/rails_error_dashboard/blob/main/CHANGELOG.md#0110-2026-08-26) | Optional. Errors captured before 0.11.0 have no environment. `bin/rails rails_error_dashboard:backfill_environments` fills it in from the snapshot each error already stores. |
| [0.11.6](https://github.com/AnjanJ/rails_error_dashboard/blob/main/CHANGELOG.md#0116-2026-09-07) | No action. Errors with messages longer than 500 characters start a new group once. See [Behaviour changes in 0.11.6](#behaviour-changes-in-0116). |
| [0.12.0](https://github.com/AnjanJ/rails_error_dashboard/blob/main/CHANGELOG.md#0120-2026-09-15) | No action. An unresolved error that recurs after the upgrade opens a new group, once. One migration merges any duplicate groups you already have. |
| [0.13.0](https://github.com/AnjanJ/rails_error_dashboard/blob/main/CHANGELOG.md#0130-2026-09-18) | Run three one-off tasks, in any order: `bin/rails error_dashboard:scrub_invalid_encoding` (SQLite and MySQL only), `bin/rails error_dashboard:backfill_resolved_at` (MTTR rises to its true value afterwards) and `bin/rails error_dashboard:digest_session_ids` (one-way). Also, "Won't fix" no longer reopens, and retention deletes errors by when they were last seen. |
| [0.14.0](https://github.com/AnjanJ/rails_error_dashboard/blob/main/CHANGELOG.md#0140-2026-09-20), [0.14.1](https://github.com/AnjanJ/rails_error_dashboard/blob/main/CHANGELOG.md#0141-2026-09-25) | No action. Overview, Analytics and several other pages now count events by when they happened, so some figures change. |
| [0.14.2](https://github.com/AnjanJ/rails_error_dashboard/blob/main/CHANGELOG.md#0142-2026-09-27) | **Can stop your app booting.** Outside `development` and `test`, RED also refuses a blank credential, a password that falls back to the default, and `authenticate_with = false`. The error names the problem. Set both variables to real values, or use an `authenticate_with` lambda. |
| [0.14.3](https://github.com/AnjanJ/rails_error_dashboard/blob/main/CHANGELOG.md#0143-2026-09-29) | If you ever ran `rails generate rails_error_dashboard:solid_queue`, replace the `config/queue.yml` it wrote: until you do, Solid Queue runs none of your app's delayed jobs. See [Solid Queue Setup](/rails_error_dashboard/docs/guides/solid-queue-setup/). On Rails before 8.1.4 or 7.2.4, [pin json below 3](#rails-before-814-or-724-pin-json-below-3). |

## Rails before 8.1.4 or 7.2.4: pin json below 3

json 3.0, released in September 2026, rejects options that older Rails versions still pass. On an
affected app, dashboard pages return 500 and errors can fail to be captured, without any message.
The bug is in Rails, not RED, so other JSON code in your app can fail the same way.

Affected: every Rails 8.0, 7.1 and 7.0 release, 7.2.3 and older, and 8.1 before 8.1.4. Rails 8.1.4
and 7.2.4 carry the fix. Until you can move to one of those, add this to your `Gemfile`:

```ruby
gem "json", "< 3"
```

Then run `bundle update json`. Remove the pin once you're on Rails 8.1.4, 7.2.4 or newer.

## Stuck at db:migrate after installing 0.4.0 to 0.8.1

A fresh install of any version from 0.4.0 to 0.8.1 stops at `db:migrate` with an error such as
`duplicate column name: instance_variables`: two of RED's migrations in those versions add the same column.
0.8.2 fixed the migration, but an app installed on one of those versions still has the broken copy,
and every later `db:migrate` stops at it. To recover:

1. Update the gem: `bundle update rails_error_dashboard`.
2. List RED's migration files that never ran:

   ```sh
   bin/rails runner 'ran = RailsErrorDashboard::ErrorLogsRecord.connection.select_values("SELECT version FROM schema_migrations").map(&:to_s); puts Dir["db/{migrate,error_dashboard_migrate}/*rails_error_dashboard*.rb"].reject { |f| ran.include?(File.basename(f)[/\A\d+/]) }'
   ```

3. Delete the files it lists. None of them ever ran, so nothing in your database depends on them.
4. Run [the upgrade](#the-upgrade): the installer copies fixed versions of those migrations, and
   `db:migrate` runs them.

## Old mount path for apps installed before 0.5.8

Before 0.5.8 the installer mounted the dashboard at `/error_dashboard`. Since then it mounts it at
`/red`. An upgrade never changes your route, so those apps keep `/error_dashboard`, and wherever
these docs say `/red` you should use your own path. Your mount line is in `config/routes.rb`:

```ruby
mount RailsErrorDashboard::Engine => "/error_dashboard"
```

To move the dashboard to `/red`, change the path in that line.

## Behaviour changes in 0.11.6

0.11.6 changed how two kinds of data are stored. Neither needs any action.

**Fingerprints for messages longer than 500 characters.** The error fingerprint now hashes only the
first 500 characters of the message, on the normal capture path and on the storm-protection path
alike. Before 0.11.6 the two paths hashed different lengths, so a long-message error could split
across two groups. After the upgrade, an error whose message runs past 500 characters gets a new
group on its next occurrence. The old group keeps its status and history and stops receiving
counts. Errors with shorter messages, and errors with a custom fingerprint, are unaffected.

**String metadata is fitted to its columns.** Before 0.11.6 an over-long string value (a
300-character `app_version`, say) made the insert fail on MySQL in strict mode, and the error was
lost. String columns are now truncated to their limit before writing, on every adapter, using 255
characters where the adapter declares none. On PostgreSQL and SQLite, which used to store such
values in full, `app_version`, `git_sha`, `error_type`, `controller_name`, `action_name` and the
other string columns are now capped at 255 characters. Grouping is unaffected: the fingerprint is
computed before truncation.
