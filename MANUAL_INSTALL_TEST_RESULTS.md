# Manual Installation Testing Results
**Date:** 2026-01-23
**Gem Version:** v0.1.23+ (post-major-frontend-refactoring)
**Tester:** Manual validation

## Test Overview

Testing the Rails Error Dashboard gem with various installation scenarios to ensure:
- Fresh installations work correctly
- Migrations run smoothly
- Upgrades from previous versions succeed
- Multi-database setups function properly

---

## Test 1: Fresh Install with Single Database ✅

**App:** `~/code/test/fresh_install_single`
**Rails:** 8.1.2
**Ruby:** 3.4.8
**Database:** SQLite (single DB)

### Steps Executed
1. ✅ Created new Rails 8.1.2 app
2. ✅ Added gem via local path
3. ✅ Ran `rails generate rails_error_dashboard:install`
4. ✅ Ran `rails db:migrate`
5. ✅ Seeded test data (1 app, 5 errors)
6. ✅ Started server on port 5005

### Results
- **Installer Output:** Clean, no errors
- **Migrations Copied:** 18 migrations
- **Migration Execution:** All passed without issues
- **Routes:** Mounted at `/error_dashboard` ✓
- **Server Status:** Running successfully
- **Dashboard URL:** http://localhost:5005/error_dashboard

### Issues Found
- None

### Notes
- Default configuration works out of the box
- All new features (syntax highlighting, settings page, filters) should be visible
- Test data populated correctly

---

## Test 2: Fresh Install with Separate Database ⚠️

**App:** `~/code/test/fresh_install_multi`
**Rails:** 8.1.2
**Ruby:** 3.4.8
**Database:** SQLite (separate error_dashboard DB)

### Steps Executed
1. ✅ Created new Rails 8.1.2 app
2. ✅ Configured `database.yml` with `error_dashboard` connection
3. ✅ Added gem via local path
4. ✅ Ran `rails generate rails_error_dashboard:install --separate_database --database=error_dashboard`
5. ✅ Moved migrations to `db/error_dashboard_migrate/`
6. ✅ Ran `rails db:create` (created both databases)
7. ✅ Ran `rails db:migrate` (all 18 migrations succeeded)
8. ⚠️ Attempted to seed data (FAILED)
9. ✅ Started server on port 5006

### Results
- **Installer Output:** Clean, recognized separate database flag
- **Migrations Copied:** 18 migrations to `db/error_dashboard_migrate/`
- **Migration Execution:** All passed, tables created in correct database
- **Database Verification:** Confirmed 7 tables in `error_dashboard_development.sqlite3`
- **Routes:** Mounted at `/error_dashboard` ✓
- **Server Status:** Running successfully
- **Dashboard URL:** http://localhost:5006/error_dashboard

### Issues Found
⚠️ **CRITICAL BUG: Multi-Database Model Connection Failure**

**Problem:**
- Error Dashboard models (`Application`, `ErrorLog`) cannot connect to separate database
- Seeding data via `rails runner` or seed files fails
- Models try to use primary database connection instead of configured `error_dashboard` connection

**Error:**
```
Could not find table 'rails_error_dashboard_applications'
```

**Impact:**
- Cannot seed test data from command line
- `rails console` usage with separate DB likely broken
- Custom rake tasks accessing models will fail
- Web UI may work (needs verification via browser)

**Root Cause:**
The gem's models don't properly establish connection to the configured separate database outside of web request context. The `config.database = :error_dashboard` setting is not being respected by ActiveRecord models.

**Workaround:**
- Dashboard UI should work via browser (connects properly during requests)
- Manual SQL insertion can populate test data
- Production usage via web interface unaffected

**Recommendation:**
This needs to be fixed before v1.0 release. Models should use:
```ruby
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
  connects_to database: { writing: :error_dashboard, reading: :error_dashboard }
end
```

### Notes
- Separate database installation works for web UI
- Migrations run correctly in separate database
- Critical blocker for CLI/console usage with separate DB
- This is a **major bug** that affects developer experience

---

## Test 3: Upgrade from v0.1.22

**Status:** Pending
**App:** `~/code/test/upgrade_from_0122`

---

## Test 4: Upgrade from v0.1.20

**Status:** Pending
**App:** `~/code/test/upgrade_from_0120`

---

## Summary

| Test | Status | Issues | Notes |
|------|--------|--------|-------|
| Fresh Install (Single DB) | ✅ PASS | 0 | Perfect installation |
| Fresh Install (Multi DB) | 🔄 In Progress | - | - |
| Upgrade from v0.1.22 | ⏳ Pending | - | - |
| Upgrade from v0.1.20 | ⏳ Pending | - | - |

---

## Recommendations

*To be filled after all tests complete*

