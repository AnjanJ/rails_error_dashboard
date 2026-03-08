---
layout: default
title: "Uninstalling Rails Error Dashboard"
permalink: /docs/UNINSTALL
---

# Uninstalling Rails Error Dashboard

This guide explains how to completely remove Rails Error Dashboard from your application.

## Quick Start - Automated Uninstall (Recommended)

The fastest way to uninstall is using the automated uninstall generator:

```bash
rails generate rails_error_dashboard:uninstall
```

This will:
- Show you what will be removed
- Provide both manual and automated options
- Ask for confirmation before making changes
- Remove initializer, routes, and migrations
- Optionally drop database tables (with confirmation)

### Uninstall Options

```bash
# Keep error data in database (don't drop tables)
rails generate rails_error_dashboard:uninstall --keep-data

# Skip confirmation prompts (USE WITH CAUTION)
rails generate rails_error_dashboard:uninstall --skip-confirmation

# Show manual instructions only (don't perform automated removal)
rails generate rails_error_dashboard:uninstall --manual-only
```

---

## Manual Uninstall

If you prefer to uninstall manually or the automated uninstaller doesn't work, follow these steps:

### Step 1: Remove from Gemfile

Open your `Gemfile` and remove:

```ruby
gem 'rails_error_dashboard'
```

Then run:

```bash
bundle install
```

### Step 2: Remove Initializer

Delete the configuration file:

```bash
rm config/initializers/rails_error_dashboard.rb
```

### Step 3: Remove Route

Open `config/routes.rb` and remove:

```ruby
mount RailsErrorDashboard::Engine => '/error_dashboard'
```

### Step 4: Remove Migrations

Delete all Rails Error Dashboard migration files:

```bash
rm db/migrate/*rails_error_dashboard*.rb
```

Or manually delete these files from `db/migrate/`:
- `*_create_rails_error_dashboard_error_logs.rb`
- `*_add_better_tracking_to_error_logs.rb`
- `*_add_controller_action_to_error_logs.rb`
- `*_add_optimized_indexes_to_error_logs.rb`
- `*_remove_environment_from_error_logs.rb`
- `*_add_enhanced_metrics_to_error_logs.rb`
- `*_add_similarity_tracking_to_error_logs.rb`
- `*_create_error_occurrences.rb`
- `*_create_cascade_patterns.rb`
- `*_create_error_baselines.rb`
- `*_add_workflow_fields_to_error_logs.rb`
- `*_create_error_comments.rb`

### Step 5: Drop Database Tables (⚠️ DESTRUCTIVE)

**WARNING:** This will permanently delete all your error tracking data!

#### Option A: Using Rake Task (Recommended)

```bash
rails rails_error_dashboard:db:drop
```

This will:
- Show you how many records will be deleted
- Ask for confirmation
- Drop tables in the correct order (respects foreign keys)

#### Option B: Manual SQL

In Rails console or database client:

```ruby
# Rails console
ActiveRecord::Base.connection.execute('DROP TABLE IF EXISTS rails_error_dashboard_error_comments CASCADE')
ActiveRecord::Base.connection.execute('DROP TABLE IF EXISTS rails_error_dashboard_error_occurrences CASCADE')
ActiveRecord::Base.connection.execute('DROP TABLE IF EXISTS rails_error_dashboard_cascade_patterns CASCADE')
ActiveRecord::Base.connection.execute('DROP TABLE IF EXISTS rails_error_dashboard_error_baselines CASCADE')
ActiveRecord::Base.connection.execute('DROP TABLE IF EXISTS rails_error_dashboard_error_logs CASCADE')
```

Or using ActiveRecord::Migration:

```ruby
ActiveRecord::Migration.drop_table(:rails_error_dashboard_error_comments, if_exists: true)
ActiveRecord::Migration.drop_table(:rails_error_dashboard_error_occurrences, if_exists: true)
ActiveRecord::Migration.drop_table(:rails_error_dashboard_cascade_patterns, if_exists: true)
ActiveRecord::Migration.drop_table(:rails_error_dashboard_error_baselines, if_exists: true)
ActiveRecord::Migration.drop_table(:rails_error_dashboard_error_logs, if_exists: true)
```

### Step 6: Clean Up Environment Variables (Optional)

Remove these environment variables from `.env` or your environment configuration:

```bash
# Authentication
ERROR_DASHBOARD_USER
ERROR_DASHBOARD_PASSWORD

# Notifications
SLACK_WEBHOOK_URL
ERROR_NOTIFICATION_EMAILS
DISCORD_WEBHOOK_URL
PAGERDUTY_INTEGRATION_KEY
WEBHOOK_URLS

# Configuration
DASHBOARD_BASE_URL
USE_SEPARATE_ERROR_DB
```

### Step 7: Restart Your Application

```bash
# Development
rails restart

# Or kill and restart your server
kill -9 <pid>
rails server

# Production (depends on your setup)
systemctl restart myapp
# or
touch tmp/restart.txt  # For Passenger
```

---

## Partial Uninstall Options

### Keep Data, Remove Code

If you want to keep your error data but stop tracking new errors:

1. **Remove the gem** from Gemfile and run `bundle install`
2. **Keep migrations and database tables** - your data remains accessible
3. **Remove initializer and routes** - dashboard won't be accessible
4. **Restart your application**

Later, if you want to view historical data, reinstall the gem and run `rails db:migrate`.

### Keep Tracking, Remove Dashboard UI

If you want to keep error logging but remove the dashboard:

1. **Keep the gem** in Gemfile
2. **Remove the route** from `config/routes.rb`
3. **Disable middleware** in initializer:
   ```ruby
   config.enable_middleware = false
   config.enable_error_subscriber = false
   ```

---

## Verification

After uninstalling, verify everything is removed:

### Check Files

```bash
# Should return nothing
grep -r "rails_error_dashboard" config/
ls config/initializers/rails_error_dashboard.rb
ls db/migrate/*rails_error_dashboard*.rb

# Should not include the gem
grep "rails_error_dashboard" Gemfile
```

### Check Database

```bash
# Rails console
rails console

# Should return false or raise error
ActiveRecord::Base.connection.table_exists?('rails_error_dashboard_error_logs')
```

### Check Routes

```bash
# Should not include /error_dashboard
rails routes | grep error_dashboard
```

---

## Troubleshooting

### "Table doesn't exist" Errors After Uninstall

If you're seeing errors about missing tables after uninstalling:

1. Make sure you've removed the gem from Gemfile and run `bundle install`
2. Check if migrations are still present in `db/migrate/`
3. Restart your Rails server
4. Check your `schema.rb` or `structure.sql` - you may need to regenerate it:
   ```bash
   rails db:schema:dump
   ```

### Cannot Drop Tables Due to Foreign Key Constraints

Drop tables in this order:

1. `rails_error_dashboard_error_comments`
2. `rails_error_dashboard_error_occurrences`
3. `rails_error_dashboard_cascade_patterns`
4. `rails_error_dashboard_error_baselines`
5. `rails_error_dashboard_error_logs` (drop last)

Or use `CASCADE`:

```sql
DROP TABLE rails_error_dashboard_error_comments CASCADE;
DROP TABLE rails_error_dashboard_error_occurrences CASCADE;
DROP TABLE rails_error_dashboard_cascade_patterns CASCADE;
DROP TABLE rails_error_dashboard_error_baselines CASCADE;
DROP TABLE rails_error_dashboard_error_logs CASCADE;
```

### Migrations Still Running

If you deleted migration files but Rails is still trying to run them:

```bash
# Reset migration status
rails db:migrate:status

# If you see pending Rails Error Dashboard migrations, mark them as down
rails db:migrate:down VERSION=<version_number>
```

---

## Reinstalling Later

If you decide to reinstall Rails Error Dashboard later:

```bash
# Add to Gemfile
gem 'rails_error_dashboard'

# Install
bundle install
rails generate rails_error_dashboard:install
rails db:migrate

# Your previous data will still be there if you kept the database tables
```

---

## Need Help?

If you encounter issues during uninstall:

- **Issues**: [GitHub Issues](https://github.com/AnjanJ/rails_error_dashboard/issues)
- **Discussions**: [GitHub Discussions](https://github.com/AnjanJ/rails_error_dashboard/discussions)

---

## Feedback

We're sorry to see you go! If you have a moment, we'd love to know why you're uninstalling:

- **GitHub Discussions**: Share your feedback (optional but appreciated)
- **GitHub Issues**: Report bugs or missing features that led to uninstall

Your feedback helps us improve Rails Error Dashboard for everyone. Thank you! 🙏
