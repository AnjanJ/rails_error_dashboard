# Migration Strategy: Squashed + Incremental

## Overview

Rails Error Dashboard uses a **hybrid migration strategy** that provides:
- **Fast installation** for new users (1 migration instead of 18)
- **Seamless upgrades** for existing users (incremental migrations)
- **Zero data loss** during upgrades
- **Automatic detection** of which path to take

---

## How It Works

### Detection Mechanism

Rails uses the `schema_migrations` table to track which migrations have run:

```ruby
# schema_migrations table stores migration timestamps
+----------------+
| version        |
+----------------+
| 20251224000001 |
| 20251224081522 |
| 20251224101217 |
+----------------+
```

Each migration checks if specific tables/columns exist to determine if it should run.

---

## Scenario 1: Brand New Installation

**User Action:**
```bash
rails rails_error_dashboard:install:migrations
rails db:migrate
```

**What Happens:**

### Step 1: Squashed Migration Runs First (20251223000000)
```ruby
# Migration timestamp: 20251223000000
def up
  return if table_exists?(:rails_error_dashboard_error_logs)  # ← Check fails, table doesn't exist

  # Creates ALL 5 tables with ALL columns:
  # - applications
  # - error_logs (with 20+ columns from all migrations)
  # - error_occurrences
  # - cascade_patterns
  # - error_baselines
  # - error_comments

  # Plus ALL indexes and foreign keys
end
```

**Result:**
- ✅ 1 migration creates complete schema
- ✅ Fast (no incremental overhead)
- ✅ All features available immediately

### Step 2: All Incremental Migrations Skip
```ruby
# Migration: 20251224000001
return if table_exists?(:rails_error_dashboard_error_logs) &&
          column_exists?(:rails_error_dashboard_error_logs, :application_id)  # ← Both exist!

# Migration: 20260106094220
return if table_exists?(:rails_error_dashboard_applications)  # ← Already exists!

# All subsequent migrations have similar guards
```

**Result:**
- ✅ Incremental migrations detect squashed ran
- ✅ All skip gracefully
- ✅ No duplicate work

---

## Scenario 2: Upgrading from v0.1.21 (2 versions ago)

**Current State:**
```ruby
# User has these migrations already run:
20251224000001  # error_logs table created
20251224081522  # error_hash added
20251224101217  # controller/action added
20251225071314  # composite indexes
20251225074653  # environment removed
20251225085859  # enhanced metrics
...
# Up to migration 20251225102500
```

**User Action:**
```bash
bundle update rails_error_dashboard
rails rails_error_dashboard:install:migrations
rails db:migrate
```

**What Happens:**

### Step 1: Squashed Migration Skips
```ruby
# Migration: 20251223000000
def up
  return if table_exists?(:rails_error_dashboard_error_logs)  # ← Table exists!
  # Entire migration skipped
end
```

**Result:**
- ✅ Squashed migration detects existing installation
- ✅ Skips gracefully

### Step 2: Incremental Migrations Continue
```ruby
# Already run (in schema_migrations):
✓ 20251224000001  # Skipped (already in schema_migrations)
✓ 20251224081522  # Skipped
✓ 20251224101217  # Skipped
✓ 20251225071314  # Skipped
✓ 20251225074653  # Skipped
✓ 20251225085859  # Skipped
✓ 20251225093603  # Skipped
✓ 20251225100236  # Skipped
✓ 20251225101920  # Skipped
✓ 20251225102500  # Skipped

# New migrations to run:
→ 20251226020000  # Add workflow fields
→ 20251226020100  # Create error_comments
→ 20251229111223  # Add performance indexes
→ 20251230075315  # Cleanup orphaned migrations
→ 20260106094220  # Create applications table
→ 20260106094233  # Add application_id to error_logs
→ 20260106094256  # Backfill application for existing errors
→ 20260106094318  # Finalize application foreign key
```

**Result:**
- ✅ Runs only new migrations (8 migrations)
- ✅ Zero data loss
- ✅ Existing data preserved
- ✅ Gradual schema evolution

---

## Scenario 3: Upgrading from v0.1.19 (4 versions ago)

**Current State:**
```ruby
# User has these migrations already run:
20251224000001  # error_logs table created
20251224081522  # error_hash added
20251224101217  # controller/action added
20251225071314  # composite indexes
# That's it - stopped here
```

**User Action:**
```bash
bundle update rails_error_dashboard
rails rails_error_dashboard:install:migrations
rails db:migrate
```

**What Happens:**

### Step 1: Squashed Migration Skips
```ruby
# Migration: 20251223000000
def up
  return if table_exists?(:rails_error_dashboard_error_logs)  # ← Table exists!
  # Skipped
end
```

### Step 2: Incremental Migrations Fill the Gap
```ruby
# Already run:
✓ 20251224000001
✓ 20251224081522
✓ 20251224101217
✓ 20251225071314

# New migrations to run:
→ 20251225074653  # Remove environment column
→ 20251225085859  # Add enhanced metrics
→ 20251225093603  # Add similarity tracking
→ 20251225100236  # Create error_occurrences
→ 20251225101920  # Create cascade_patterns
→ 20251225102500  # Create error_baselines
→ 20251226020000  # Add workflow fields
→ 20251226020100  # Create error_comments
→ 20251229111223  # Add performance indexes
→ 20251230075315  # Cleanup orphaned migrations
→ 20260106094220  # Create applications table
→ 20260106094233  # Add application_id to error_logs
→ 20260106094256  # Backfill application for existing errors
→ 20260106094318  # Finalize application foreign key
```

**Result:**
- ✅ Runs 14 incremental migrations
- ✅ Brings schema up to date
- ✅ All features enabled
- ✅ Data preserved and migrated

---

## Scenario 4: Upgrading from v0.1.10 (9 versions ago)

**Current State:**
```ruby
# User has only:
20251224000001  # error_logs table created (basic schema)
```

**User Action:**
```bash
bundle update rails_error_dashboard
rails rails_error_dashboard:install:migrations
rails db:migrate
```

**What Happens:**

### Step 1: Squashed Migration Skips
```ruby
# Migration: 20251223000000
def up
  return if table_exists?(:rails_error_dashboard_error_logs)  # ← Table exists!
  # Skipped
end
```

### Step 2: All Incremental Migrations After v0.1.10 Run
```ruby
# Already run:
✓ 20251224000001

# New migrations to run (17 migrations):
→ 20251224081522  # error_hash, first_seen_at, last_seen_at, occurrence_count
→ 20251224101217  # controller_name, action_name
→ 20251225071314  # Composite indexes for performance
→ 20251225074653  # Remove environment column
→ 20251225085859  # app_version, git_sha, priority_score
→ 20251225093603  # similarity_score, backtrace_signature
→ 20251225100236  # Create error_occurrences table
→ 20251225101920  # Create cascade_patterns table
→ 20251225102500  # Create error_baselines table
→ 20251226020000  # status, assigned_to, snoozed_until, priority_level
→ 20251226020100  # Create error_comments table
→ 20251229111223  # Additional performance indexes
→ 20251230075315  # Cleanup orphaned migrations
→ 20260106094220  # Create applications table
→ 20260106094233  # Add application_id to error_logs
→ 20260106094256  # Backfill application for existing errors
→ 20260106094318  # Finalize application foreign key
```

**Result:**
- ✅ Runs 17 incremental migrations
- ✅ Complete schema evolution
- ✅ All data preserved
- ✅ Features enabled incrementally

---

## Key Detection Checks

### 1. Squashed Migration (20251223000000)
```ruby
return if table_exists?(:rails_error_dashboard_error_logs)
```
**Logic:** If error_logs table exists, this is an upgrade (not new install)

### 2. First Incremental Migration (20251224000001)
```ruby
return if table_exists?(:rails_error_dashboard_error_logs) &&
          column_exists?(:rails_error_dashboard_error_logs, :application_id)
```
**Logic:** If error_logs exists AND has application_id column, squashed migration ran

### 3. Applications Table Migration (20260106094220)
```ruby
return if table_exists?(:rails_error_dashboard_applications)
```
**Logic:** If applications table exists, skip (either squashed or already ran)

### 4. Other Migrations
Rails automatically skips migrations in `schema_migrations` table

---

## Visual Flow Diagram

```
User runs: rails db:migrate
           |
           v
[20251223000000 Squashed Migration]
           |
    Does error_logs table exist?
           |
    +------+------+
    |             |
   YES           NO
    |             |
    v             v
  SKIP      CREATE COMPLETE SCHEMA
    |        (5 tables, all columns,
    |         all indexes, all FKs)
    |             |
    +------+------+
           |
           v
[20251224000001 First Incremental]
           |
    Does error_logs exist with application_id?
           |
    +------+------+
    |             |
   YES           NO
    |             |
    v             v
  SKIP      CREATE ERROR_LOGS TABLE
    |        (basic schema only)
    |             |
    +------+------+
           |
           v
[All Other Incremental Migrations]
           |
    Is this migration in schema_migrations?
           |
    +------+------+
    |             |
   YES           NO
    |             |
    v             v
  SKIP        RUN MIGRATION
    |        (add columns, indexes, etc.)
    |             |
    +------+------+
           |
           v
    MIGRATION COMPLETE
```

---

## Benefits of This Strategy

### For New Users
- ✅ **Fast installation**: 1 migration instead of 18
- ✅ **Clean schema**: No migration artifacts
- ✅ **All features**: Everything enabled immediately
- ✅ **No confusion**: Simple, straightforward

### For Existing Users
- ✅ **Seamless upgrades**: Just `bundle update` and `rails db:migrate`
- ✅ **Zero downtime**: Migrations are backward-compatible
- ✅ **Data preservation**: All existing data kept
- ✅ **Incremental**: Only run what's needed
- ✅ **No manual intervention**: Automatic detection

### For Developers
- ✅ **Maintainable**: Clear separation of concerns
- ✅ **Testable**: Can test both paths
- ✅ **Safe**: Guard clauses prevent double-running
- ✅ **Flexible**: Easy to add new migrations

---

## Migration Timeline

```
v0.1.10 (Old)
  └─ 20251224000001  ← Basic error_logs table

v0.1.15
  ├─ 20251224081522  ← Error deduplication
  ├─ 20251224101217  ← Controller/action
  └─ 20251225071314  ← Performance indexes

v0.1.18
  ├─ 20251225074653  ← Remove environment
  ├─ 20251225085859  ← Enhanced metrics
  └─ 20251225093603  ← Similarity tracking

v0.1.19
  ├─ 20251225100236  ← Error occurrences
  ├─ 20251225101920  ← Cascade patterns
  └─ 20251225102500  ← Error baselines

v0.1.21
  ├─ 20251226020000  ← Workflow fields
  └─ 20251226020100  ← Error comments

v0.1.23
  ├─ 20251229111223  ← Performance indexes
  └─ 20251230075315  ← Cleanup

v0.1.29
  ├─ 20251223000000  ← SQUASHED MIGRATION
  ├─ 20260106094220  ← Applications table
  ├─ 20260106094233  ← Add application_id
  ├─ 20260106094256  ← Backfill application
  └─ 20260106094318  ← Finalize foreign key

v0.2.0
  ├─ 20260220000001  ← Exception cause chain (cause_class, cause_message, exception_chain)
  ├─ 20260220000002  ← Enriched context (http_method, hostname, content_type, etc.)
  ├─ 20260220000003  ← Time-series indexes (BRIN + functional, PostgreSQL only)
  ├─ 20260221000001  ← Environment info (ruby_version, rails_version, gem_version)
  └─ 20260221000002  ← Reopened tracking (reopened_at)

v0.3.0
  ├─ 20260303000001  ← Breadcrumbs (text column on error_logs)
  └─ 20260304000001  ← System health (JSON column on error_logs)

v0.4.0 (Current)
  ├─ 20260306000001  ← Local variables (text column on error_logs)
  ├─ 20260306000002  ← Instance variables (text column on error_logs)
  ├─ 20260306000003  ← Swallowed exceptions table (new table)
  └─ 20260307000001  ← Diagnostic dumps table (new table)
```

---

## Testing the Strategy

You can verify the strategy works with these commands:

### Test New Installation
```bash
cd /tmp
rails new test_app
cd test_app
echo "gem 'rails_error_dashboard', path: '/Users/aj/code/rails_error_dashboard'" >> Gemfile
bundle install
rails rails_error_dashboard:install:migrations
rails db:migrate

# Verify: Should show only 1 migration ran (20251223000000)
rails db:migrate:status | grep rails_error_dashboard
```

### Test Upgrade Simulation
```bash
# Simulate v0.1.19 user by only running migrations up to that point
cd /tmp
rails new upgrade_test
cd upgrade_test
echo "gem 'rails_error_dashboard', path: '/Users/aj/code/rails_error_dashboard'" >> Gemfile
bundle install
rails rails_error_dashboard:install:migrations

# Run only migrations up to v0.1.19
rails db:migrate VERSION=20251225102500

# Now "upgrade" by running remaining migrations
rails db:migrate

# Verify: Should show incremental migrations ran
rails db:migrate:status | grep rails_error_dashboard
```

---

## Common Questions

### Q: What if a user has a really old version?
**A:** The incremental migrations will run in order, bringing the schema up to date step by step. All data is preserved.

### Q: What if someone manually deleted a table?
**A:** The guard clauses will detect the missing table and allow the appropriate migration to recreate it.

### Q: Can I remove old incremental migrations?
**A:** No, not yet. Users on old versions still need them. After Rails Error Dashboard v1.0, we can deprecate pre-v1.0 upgrade paths.

### Q: What if squashed migration and incremental migrations conflict?
**A:** They can't - guard clauses ensure only one path runs. Either squashed (new install) or incremental (upgrade).

### Q: How do I know which path a user took?
**A:** Check `schema_migrations` table:
- If `20251223000000` exists → Used squashed migration (new install)
- If `20251224000001` exists but not `20251223000000` → Used incremental (upgrade)

---

## Maintenance Notes

### Adding New Migrations
When adding new features, create incremental migrations as normal:

```bash
rails g migration AddNewFeatureToErrorLogs new_column:string
```

The migration will automatically:
1. Be skipped for squashed users (guard clause)
2. Run for upgrade users (normal Rails behavior)

### Updating Squashed Migration
When releasing a new major version, update the squashed migration to include all new columns/tables. This ensures new users get everything in one migration.

---

## Upgrading to v0.2.0

v0.2.0 adds 5 new migrations. The upgrade path depends on your database setup.

### Shared Database (default)

```bash
bundle update rails_error_dashboard
rails rails_error_dashboard:install:migrations
rails db:migrate
```

Rails will only copy and run migrations that haven't been applied yet. All 5 new migrations have `column_exists?` guards, so they're safe to re-run.

### Separate Database (`use_separate_database = true`)

```bash
bundle update rails_error_dashboard

# Copy new migrations (Rails skips already-copied ones by class name)
rails rails_error_dashboard:install:migrations

# Move new migrations to your error dashboard migrate directory
# (adjust the directory name to match your database.yml key)
mv db/migrate/*_add_exception_cause_to_error_logs.rb db/error_dashboard_migrate/
mv db/migrate/*_add_enriched_context_to_error_logs.rb db/error_dashboard_migrate/
mv db/migrate/*_add_time_series_indexes_to_error_logs.rb db/error_dashboard_migrate/
mv db/migrate/*_add_environment_info_to_error_logs.rb db/error_dashboard_migrate/
mv db/migrate/*_add_reopened_at_to_error_logs.rb db/error_dashboard_migrate/

# Run migrations against the error dashboard database
rails db:migrate:error_dashboard
```

### New v0.2.0 Columns

| Migration | Columns Added | Purpose |
|-----------|---------------|---------|
| `add_exception_cause` | `cause_class`, `cause_message`, `exception_chain` | Root cause analysis |
| `add_enriched_context` | `http_method`, `hostname`, `content_type`, `request_duration`, `custom_fingerprint` | Richer error context |
| `add_time_series_indexes` | *(indexes only, PostgreSQL)* | BRIN + functional indexes for analytics |
| `add_environment_info` | `ruby_version`, `rails_version`, `gem_version` | Environment snapshots |
| `add_reopened_at` | `reopened_at` | Auto-reopen tracking |

### New Configuration Options

After upgrading, review the new options in your initializer:

```ruby
# Sensitive data filtering (enabled by default)
config.filter_sensitive_data = true

# Auto-reopen resolved errors on recurrence
config.auto_reopen_resolved_errors = true

# Notification throttling
config.notification_cooldown_minutes = 60

# Custom fingerprint for error grouping
# config.custom_fingerprint = ->(exception, context) { "custom-key" }
```

Run `rails generate rails_error_dashboard:install` to see the full initializer template with all new options.

---

## Upgrading to v0.3.0

v0.3.0 adds 2 new migrations for breadcrumbs and system health snapshots.

### Shared Database (default)

```bash
bundle update rails_error_dashboard
rails rails_error_dashboard:install:migrations
rails db:migrate
```

### Separate Database

```bash
bundle update rails_error_dashboard
rails rails_error_dashboard:install:migrations
mv db/migrate/*_add_breadcrumbs_to_error_logs.rb db/error_dashboard_migrate/
mv db/migrate/*_add_system_health_to_error_logs.rb db/error_dashboard_migrate/
rails db:migrate:error_dashboard
```

### New v0.3.0 Columns

| Migration | Columns Added | Purpose |
|-----------|---------------|---------|
| `add_breadcrumbs` | `breadcrumbs` (text) | Request activity trail (SQL, controller, cache events) |
| `add_system_health` | `system_health` (text) | GC, memory, threads, connection pool snapshot |

---

## Upgrading to v0.4.0

v0.4.0 adds 4 new migrations: 2 columns on error_logs and 2 new tables.

### Shared Database (default)

```bash
bundle update rails_error_dashboard
rails rails_error_dashboard:install:migrations
rails db:migrate
```

### Separate Database

```bash
bundle update rails_error_dashboard
rails rails_error_dashboard:install:migrations
mv db/migrate/*_add_local_variables_to_error_logs.rb db/error_dashboard_migrate/
mv db/migrate/*_add_instance_variables_to_error_logs.rb db/error_dashboard_migrate/
mv db/migrate/*_create_rails_error_dashboard_swallowed_exceptions.rb db/error_dashboard_migrate/
mv db/migrate/*_create_rails_error_dashboard_diagnostic_dumps.rb db/error_dashboard_migrate/
rails db:migrate:error_dashboard
```

### New v0.4.0 Schema Changes

| Migration | Type | Purpose |
|-----------|------|---------|
| `add_local_variables` | Column (text) on error_logs | Local variable values at exception point |
| `add_instance_variables` | Column (text) on error_logs | Instance variable values from raising object |
| `create_swallowed_exceptions` | New table | Tracks raise/rescue counts per location, hourly bucketing |
| `create_diagnostic_dumps` | New table | Stores system state snapshots with full JSON details |

### New Configuration Options

After upgrading, these options are available (all disabled by default):

```ruby
config.enable_local_variables = true
config.enable_instance_variables = true
config.detect_swallowed_exceptions = true    # Requires Ruby 3.3+
config.enable_diagnostic_dump = true
config.enable_rack_attack_tracking = true    # Requires breadcrumbs
config.enable_crash_capture = true
```

---

## Conclusion

The hybrid squashed + incremental strategy provides the best of both worlds:
- **New users**: Fast, clean installation
- **Existing users**: Smooth, automatic upgrades
- **Developers**: Maintainable, testable code

No manual intervention required - just `rails db:migrate` and it works! 🎉
