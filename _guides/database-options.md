---
layout: default
title: "Database Setup Guide"
order: 2
---

# Database Setup Guide

This guide covers all database configurations for Rails Error Dashboard: single-app, separate database, and multi-app setups.

> **Quick verification:** Run `rails error_dashboard:verify` at any time to check your setup.

---

## Option 1: Same Database (Default)

No extra configuration needed. Error data is stored in your app's primary database.

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  config.use_separate_database = false  # default
end
```

```bash
rails db:migrate
```

**Best for:** Small apps, development, getting started quickly.

---

## Option 2: Separate Database (Single App)

Isolate error data in its own database. Recommended for production.

On a new install, let the installer set it up:

```bash
bin/rails generate rails_error_dashboard:install --separate-database
```

It writes the initializer below, copies RED's migrations to `db/error_dashboard_migrate/`, and
prints the `config/database.yml` entry to add. An app that already stores RED's errors in its main
database needs [Moving to a separate database](#moving-from-the-main-database-to-a-separate-one)
instead.

### Step 1: Update initializer

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  config.use_separate_database = true
  config.database = :error_dashboard
end
```

### Step 2: Add database.yml entry

The key name (`error_dashboard:`) must match `config.database`. Add it to **every environment the
app boots in**, test included. In an environment without it, RED logs a warning at boot and falls
back to the main database, which has no RED tables, so that environment's errors are not recorded
anywhere.

```yaml
# config/database.yml

development:
  primary:
    <<: *default
    database: myapp_development
  error_dashboard:
    <<: *default
    database: myapp_errors_development
    migrations_paths: db/error_dashboard_migrate

test:
  primary:
    <<: *default
    database: myapp_test
  error_dashboard:
    <<: *default
    database: myapp_errors_test
    migrations_paths: db/error_dashboard_migrate

production:
  primary:
    <<: *default
    database: myapp_production
  error_dashboard:
    <<: *default
    database: myapp_errors_production
    migrations_paths: db/error_dashboard_migrate
    pool: <%= ENV.fetch("RAILS_MAX_THREADS", 5) %>
```

### Step 3: Create and migrate

```bash
rails db:create:error_dashboard
rails db:migrate:error_dashboard
```

### Step 4: Verify

```bash
rails error_dashboard:verify
```

**Best for:** Production apps that want error data isolated from application data.

---

## Option 3: Shared Database (Multi-App)

Multiple Rails apps write errors to one shared database. One dashboard to monitor all apps.

### How it works

```
  App 1 (BlogAPI)          App 2 (AdminPanel)       App 3 (MobileAPI)
  config.database =        config.database =        config.database =
    :error_dashboard         :error_dashboard         :error_dashboard
         |                        |                        |
         +------------------------+------------------------+
                                  |
                    Shared error_dashboard database
                    (13 tables, all prefixed rails_error_dashboard_)
                                  |
                    Dashboard shows app switcher:
                    [All Apps] [BlogAPI] [AdminPanel] [MobileAPI]
```

### App 1 setup (first install)

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  config.use_separate_database = true
  config.database = :error_dashboard
  config.application_name = "BlogAPI"  # optional, auto-detected from Rails.application
end
```

```yaml
# config/database.yml
production:
  primary:
    <<: *default
    database: blog_api_production

  error_dashboard:
    <<: *default
    database: shared_errors_production     # <-- the shared database
    host: errors-db.example.com
    migrations_paths: db/error_dashboard_migrate
```

```bash
rails db:create:error_dashboard
rails db:migrate:error_dashboard     # <-- only App 1 needs to run migrations
```

### App 2 setup (joining existing)

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  config.use_separate_database = true
  config.database = :error_dashboard
  config.application_name = "AdminPanel"
end
```

```yaml
# config/database.yml — point to the SAME physical database as App 1
production:
  primary:
    <<: *default
    database: admin_panel_production

  error_dashboard:
    <<: *default
    database: shared_errors_production     # <-- same DB as App 1
    host: errors-db.example.com
    migrations_paths: db/error_dashboard_migrate
```

```bash
# The database already exists (App 1 created it).
# If you ran the installer, you'll have migrations in db/error_dashboard_migrate/.
# Running migrate is safe. The installer gives App 2's copies their own version
# numbers, so they run, find the tables and columns already there, and change nothing.
rails db:migrate:error_dashboard

# Verify the connection:
rails error_dashboard:verify
```

### App 3 and beyond

Same pattern as App 2. Point `database.yml` to the same physical database. Set a unique `application_name` (or let it auto-detect from `Rails.application.class.module_parent_name`).

### What auto-detection produces

The name comes from `config.application_name`, then the `APPLICATION_NAME` environment variable,
then your Rails app's module name:

| App class | Auto-detected name |
|-----------|-------------------|
| `BlogApi::Application` | `BlogApi` |
| `AdminPanel::Application` | `AdminPanel` |
| `MyApp::Application` | `MyApp` |

### Tables in the shared database

All 13 tables are shared. Errors are separated by `application_id`:

| Table | Purpose |
|-------|---------|
| `rails_error_dashboard_applications` | Registry of app names |
| `rails_error_dashboard_error_logs` | All errors (filtered by `application_id`) |
| `rails_error_dashboard_error_occurrences` | Per-occurrence tracking |
| `rails_error_dashboard_error_comments` | Comment threads |
| `rails_error_dashboard_error_baselines` | Anomaly detection data |
| `rails_error_dashboard_cascade_patterns` | Error cascade relationships |
| `rails_error_dashboard_diagnostic_dumps` | On-demand diagnostic dumps |
| `rails_error_dashboard_event_counts` | Hourly counts of events storm protection didn't store one by one |
| `rails_error_dashboard_event_timing_gaps` | Periods whose per-event timestamps were lost |
| `rails_error_dashboard_rack_attack_events` | Rack::Attack events |
| `rails_error_dashboard_storm_events` | Error storm episodes |
| `rails_error_dashboard_storm_flush_batches` | Storm-protection count batches already applied |
| `rails_error_dashboard_swallowed_exceptions` | Swallowed-exception statistics |

### Dashboard app switcher

When 2+ applications exist, the dashboard shows an app switcher dropdown. You can view errors for a single app or "All Apps" combined.

---

## Moving From the Main Database to a Separate One

If RED already stores its errors in your app's main database (Option 1) and you want them in a
database of their own (Option 2 or 3). The examples use PostgreSQL database names; adjust them to
yours.

### 1. Configure the separate database

Set `config.use_separate_database = true` and `config.database = :error_dashboard` in the
initializer, and add the `error_dashboard` entry to every environment in `config/database.yml`, as
in [Option 2](#option-2-separate-database-single-app) (or [Option 3](#option-3-shared-database-multi-app)).

### 2. Move RED's migrations

Re-running the installer doesn't move them: it skips every migration your app already has. Move
them yourself:

```bash
mkdir -p db/error_dashboard_migrate && git mv db/migrate/*.rails_error_dashboard.rb db/error_dashboard_migrate/
```

### 3. Create the new database, and don't migrate it yet

```bash
bin/rails db:create:error_dashboard
```

### 4. Copy RED's tables and their data

Copy the tables as they are, structure included, into the empty database. If you don't need the
errors you already have, skip this step: the next one builds empty tables.

PostgreSQL:

```bash
pg_dump --no-owner -t 'rails_error_dashboard_*' myapp_production | psql -v ON_ERROR_STOP=1 myapp_errors_production
```

MySQL (on MariaDB, leave out `--set-gtid-purged=OFF`):

```bash
mysqldump --no-tablespaces --single-transaction --set-gtid-purged=OFF myapp_production $(mysql -N -e "SHOW TABLES LIKE 'rails\_error\_dashboard\_%'" myapp_production) | mysql myapp_errors_production
```

SQLite:

```bash
sqlite3 storage/production.sqlite3 ".dump 'rails_error_dashboard_%'" | sqlite3 storage/error_dashboard_production.sqlite3
```

### 5. Migrate the new database

```bash
bin/rails db:migrate:error_dashboard
```

The tables are already there, so RED's migrations find them in place and change nothing; this
records them as run, so later upgrades migrate this database.

### 6. Restart, then check

```bash
bin/rails error_dashboard:verify
```

It should report the separate database and all 13 tables. In production, steps 3 to 5 need the new
configuration, and must finish before the app restarts with it: run them in your release step, or
stop the app while they run. Errors captured after the copy and before the restart stay in the old
tables.

### 7. Remove the old tables from the main database

Once the new database checks out, drop RED's tables from the main database in
`bin/rails console`. This drops every `rails_error_dashboard_*` table on the main connection, each
one after the tables that reference it:

```ruby
connection = ActiveRecord::Base.connection
tables = connection.tables.grep(/\Arails_error_dashboard_/)
until tables.empty?
  # A table can go once no other remaining RED table has a foreign key to it.
  droppable = tables.reject do |table|
    (tables - [table]).any? { |other| connection.foreign_keys(other).any? { |fk| fk.to_table == table } }
  end
  raise "foreign-key cycle among #{tables.join(', ')}" if droppable.empty?
  droppable.each { |table| connection.drop_table(table) }
  tables -= droppable
end
```

Don't use `bin/rails rails_error_dashboard:db:drop` for this: it drops RED's tables on RED's
current connection, which is now the new database. Then update the schema files:

```bash
bin/rails db:schema:dump
```

---

## Upgrading the Gem

Follow [Upgrading](/rails_error_dashboard/docs/upgrading/#the-upgrade): `bundle update rails_error_dashboard`, then
`bin/rails generate rails_error_dashboard:install --no-interactive`, then `bin/rails db:migrate`,
which migrates the error database too. With a separate database the installer copies the new
migrations to `db/error_dashboard_migrate/`.

**Multi-app users:** run the upgrade in every app, so each one has the new migration files. The
first app to migrate updates the shared database; the other apps' copies of the same migrations
then find the change already made and do nothing.

---

## MySQL: time zone tables are required

The dashboard buckets time series (charts, baselines) with
[groupdate](https://github.com/ankane/groupdate), which on MySQL converts
timestamps with `CONVERT_TZ(..., '+00:00', '<zone name>')`. That function
returns `NULL` for a named zone until the server's time zone tables are loaded,
and groupdate then raises `Groupdate::Error: Database missing time zone
support`. Load them once on the server:

```bash
mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql -u root mysql
```

Managed MySQL (RDS, Cloud SQL, PlanetScale) ships with the tables loaded.
`rails error_dashboard:verify` checks the conversion against your app's
configured time zone and prints the fix when it is missing.

## Using a Different Database Server

You can host the error database on a completely separate server:

```yaml
production:
  primary:
    <<: *default
    database: myapp_production
    host: app-db.example.com

  error_dashboard:
    database: myapp_errors_production
    host: errors-db.example.com    # different server
    adapter: postgresql
    encoding: utf8
    pool: <%= ENV.fetch("RAILS_MAX_THREADS", 5) %>
    username: <%= ENV['ERROR_DASHBOARD_DB_USER'] %>
    password: <%= ENV['ERROR_DASHBOARD_DB_PASSWORD'] %>
    migrations_paths: db/error_dashboard_migrate
```

**Trade-offs of separate server:**
- No foreign keys between error tables and app tables (e.g., users)
- No cross-database joins (the gem handles this with separate queries)
- Need to manage backup/maintenance for an additional database

---

## Troubleshooting

Run `rails error_dashboard:verify` first — it checks everything automatically.

### "database configuration is required when use_separate_database is true"

You set `config.use_separate_database = true` but forgot `config.database`:

```ruby
config.use_separate_database = true
config.database = :error_dashboard  # <-- add this
```

### "No such table: rails_error_dashboard_error_logs"

Tables haven't been created yet:

```bash
# Separate database:
rails db:create:error_dashboard
rails db:migrate:error_dashboard

# Primary database:
rails db:migrate
```

### Dashboard shows no errors after switching to separate database

1. Verify `config.use_separate_database = true` and `config.database = :error_dashboard` in your initializer
2. Check `config/database.yml` has the `error_dashboard` entry for the environment you're running.
   Without it, RED logs `Separate database 'error_dashboard' is not configured in database.yml`
   at boot and records no errors
3. Restart your Rails server
4. Run `rails error_dashboard:verify` to check the connection
5. If moving from the main database, make sure you [copied the data](#4-copy-reds-tables-and-their-data)

### Multi-app: App 2 doesn't see App 1's errors

Both apps must point to the **same physical database** in their `database.yml`: the same `host` and `database:` values. The key name only has to match each app's own `config.database`.
