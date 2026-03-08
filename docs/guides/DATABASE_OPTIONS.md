---
layout: default
title: "Database Setup Guide"
permalink: /docs/guides/DATABASE_OPTIONS
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

### Step 1: Update initializer

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  config.use_separate_database = true
  config.database = :error_dashboard
end
```

### Step 2: Add database.yml entry

The key name (`error_dashboard:`) must match `config.database`:

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
                    (6 tables, all prefixed rails_error_dashboard_)
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
# Running migrate is safe — migrations that App 1 already applied will be skipped
# (they're tracked in the shared schema_migrations table).
rails db:migrate:error_dashboard

# Verify the connection:
rails error_dashboard:verify
```

### App 3 and beyond

Same pattern as App 2. Point `database.yml` to the same physical database. Set a unique `application_name` (or let it auto-detect from `Rails.application.class.module_parent_name`).

### What auto-detection produces

If you don't set `config.application_name`, the gem detects it from your Rails app:

| App class | Auto-detected name |
|-----------|-------------------|
| `BlogApi::Application` | `BlogApi` |
| `AdminPanel::Application` | `AdminPanel` |
| `MyApp::Application` | `MyApp` |

### Tables in the shared database

All 6 tables are shared. Errors are separated by `application_id`:

| Table | Purpose |
|-------|---------|
| `rails_error_dashboard_applications` | Registry of app names |
| `rails_error_dashboard_error_logs` | All errors (filtered by `application_id`) |
| `rails_error_dashboard_error_occurrences` | Per-occurrence tracking |
| `rails_error_dashboard_error_comments` | Comment threads |
| `rails_error_dashboard_error_baselines` | Anomaly detection data |
| `rails_error_dashboard_cascade_patterns` | Error cascade relationships |

### Dashboard app switcher

When 2+ applications exist, the dashboard shows an app switcher dropdown. You can view errors for a single app or "All Apps" combined.

---

## Migrating From Primary to Separate Database

If you started with Option 1 and want to move to Option 2 or 3:

### 1. Configure the separate database

Follow Option 2 or 3 above to set up `database.yml` and the initializer.

### 2. Create and migrate the new database

```bash
rails db:create:error_dashboard
rails db:migrate:error_dashboard
```

### 3. Copy existing data

Use SQL to copy data directly between databases. The gem's `connects_to` runs once at boot, so you can't switch connections at runtime via config toggles.

```bash
# PostgreSQL example: dump from primary, restore to separate DB
pg_dump -t 'rails_error_dashboard_*' myapp_development | psql myapp_errors_development

# Or use Rails dbconsole to export/import:
# 1. Export from primary
rails dbconsole -p < <(echo "COPY rails_error_dashboard_error_logs TO '/tmp/error_logs.csv' CSV HEADER;")

# 2. Import to separate DB
rails dbconsole --database=error_dashboard < <(echo "COPY rails_error_dashboard_error_logs FROM '/tmp/error_logs.csv' CSV HEADER;")
```

For SQLite, copy the tables using `.dump`:
```bash
sqlite3 db/development.sqlite3 ".dump rails_error_dashboard_error_logs" | sqlite3 db/myapp_errors_development.sqlite3
```

### 4. Verify and clean up

```bash
rails error_dashboard:verify
# Once verified, remove old data from primary database if desired
```

---

## Upgrading the Gem

When you upgrade `rails_error_dashboard` to a new version:

**Step 1: Update the gem and copy new migrations**
```bash
bundle update rails_error_dashboard
rails generate rails_error_dashboard:install
```

Re-running the installer is safe — it skips migrations you already have and only copies new ones from the updated gem. Your existing initializer and routes are not overwritten.

**Step 2: Run the new migrations**

Single database users:
```bash
rails db:migrate
```

Separate database users:
```bash
rails db:migrate:error_dashboard
```

**Multi-app users:** Only one app needs to run migrations. The shared database schema is updated once — all other apps will use the new schema automatically. However, all apps should re-run the installer to get the new migration files (in case they need to run migrations in the future).

---

## Using a Different Database Server

You can host the error database on a completely separate server:

```yaml
production:
  primary:
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

1. Verify `config.use_separate_database = true` in your initializer
2. Restart your Rails server
3. Run `rails error_dashboard:verify` to check the connection
4. If migrating, make sure you copied data to the new database

### Multi-app: App 2 doesn't see App 1's errors

Both apps must point to the **same physical database** in their `database.yml`. The database key name (`error_dashboard:`) must be the same, and the `database:` value must point to the same DB.
