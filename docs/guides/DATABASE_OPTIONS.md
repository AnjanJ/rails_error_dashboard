# Migrating to Separate Database for Error Logs

This guide helps you migrate existing error logs from your primary database to a separate database.

## Why Migrate to Separate Database?

### Benefits
- ✅ **Performance isolation** - Error logging doesn't impact main application queries
- ✅ **Independent scaling** - Different hardware/resources for error logs
- ✅ **Flexible retention** - Easily delete old errors without affecting main DB
- ✅ **Security isolation** - Separate access controls and backups
- ✅ **Easier maintenance** - Can drop/recreate error logs DB without affecting app

### When to Migrate
Consider migrating when:
- You have 10,000+ error logs in your database
- Error dashboard queries are slowing down your app
- You want different backup/retention policies for errors
- You're running high-traffic production applications

## Migration Process

### Overview
The migration involves 4 steps:
1. Set up separate database configuration
2. Copy existing error logs to new database
3. Verify data integrity
4. Clean up old data from primary database

---

## Step 1: Configure Separate Database

### 1.1 Update database.yml

Add the `error_logs` database configuration:

```yaml
# config/database.yml

production:
  primary:
    database: myapp_production
    # ... your existing primary DB config

  # NEW: Separate database for error logs
  error_logs:
    database: myapp_error_logs_production
    adapter: postgresql  # or mysql2, sqlite3
    encoding: utf8
    pool: <%= ENV.fetch("RAILS_MAX_THREADS", 5) %>
    username: <%= ENV['ERROR_LOGS_DATABASE_USER'] %>
    password: <%= ENV['ERROR_LOGS_DATABASE_PASSWORD'] %>
    host: <%= ENV['ERROR_LOGS_DATABASE_HOST'] %>
    migrations_paths: db/error_logs_migrate
```

### 1.2 Set Environment Variables

```bash
# .env or production environment
ERROR_LOGS_DATABASE_USER=error_logs_user
ERROR_LOGS_DATABASE_PASSWORD=secure_password_here
ERROR_LOGS_DATABASE_HOST=localhost  # or separate server
```

### 1.3 Create the Database

```bash
# Create the new database
rails db:create:error_logs

# Run migrations to create the table structure
rails db:migrate:error_logs
```

This creates the `rails_error_dashboard_error_logs` table in the new database.

---

## Step 2: Migrate Existing Data

### 2.1 Create Migration Task

Create a Rake task to copy data:

```ruby
# lib/tasks/migrate_error_logs.rake

namespace :error_logs do
  desc "Migrate error logs from primary database to separate database"
  task migrate_to_separate_db: :environment do
    puts "Starting error logs migration..."

    # Count records in primary DB
    ActiveRecord::Base.connected_to(role: :writing) do
      old_count = RailsErrorDashboard::ErrorLog.count
      puts "Found #{old_count} error logs in primary database"

      if old_count == 0
        puts "No error logs to migrate!"
        exit
      end
    end

    # Temporarily disable separate database to read from primary
    original_setting = RailsErrorDashboard.configuration.use_separate_database
    RailsErrorDashboard.configuration.use_separate_database = false

    # Get all error logs from primary database
    old_errors = RailsErrorDashboard::ErrorLog.all.to_a
    puts "Loaded #{old_errors.count} error logs"

    # Re-enable separate database
    RailsErrorDashboard.configuration.use_separate_database = true

    # Insert into separate database in batches
    batch_size = 1000
    migrated_count = 0
    failed_count = 0

    old_errors.each_slice(batch_size) do |batch|
      begin
        ActiveRecord::Base.connected_to(role: :writing, shard: :error_logs) do
          batch.each do |error|
            # Create new record in separate database
            new_error = RailsErrorDashboard::ErrorLog.new(
              error_type: error.error_type,
              message: error.message,
              backtrace: error.backtrace,
              user_id: error.user_id,
              request_url: error.request_url,
              request_params: error.request_params,
              user_agent: error.user_agent,
              ip_address: error.ip_address,
              environment: error.environment,
              platform: error.platform,
              resolved: error.resolved,
              resolution_comment: error.resolution_comment,
              resolution_reference: error.resolution_reference,
              resolved_by_name: error.resolved_by_name,
              resolved_at: error.resolved_at,
              occurred_at: error.occurred_at,
              created_at: error.created_at,
              updated_at: error.updated_at
            )

            if new_error.save
              migrated_count += 1
            else
              failed_count += 1
              puts "Failed to migrate error #{error.id}: #{new_error.errors.full_messages.join(', ')}"
            end
          end
        end

        print "."
      rescue => e
        puts "\nError in batch: #{e.message}"
        failed_count += batch.size
      end
    end

    puts "\n\nMigration complete!"
    puts "Successfully migrated: #{migrated_count}"
    puts "Failed: #{failed_count}"

    # Verify counts
    ActiveRecord::Base.connected_to(role: :reading, shard: :error_logs) do
      new_count = RailsErrorDashboard::ErrorLog.count
      puts "New database now has: #{new_count} error logs"
    end

    puts "\nIMPORTANT: Verify the data before running cleanup!"
    puts "Run: rake error_logs:verify_migration"
  end

  desc "Verify error logs migration"
  task verify_migration: :environment do
    puts "Verifying migration..."

    # Count in primary DB (with separate DB disabled)
    RailsErrorDashboard.configuration.use_separate_database = false
    old_count = RailsErrorDashboard::ErrorLog.count

    # Count in separate DB
    RailsErrorDashboard.configuration.use_separate_database = true
    new_count = RailsErrorDashboard::ErrorLog.count

    puts "Primary database: #{old_count} error logs"
    puts "Separate database: #{new_count} error logs"

    if old_count == new_count
      puts "✅ Counts match! Migration successful."
      puts "\nYou can now:"
      puts "1. Enable separate database in config/initializers/rails_error_dashboard.rb"
      puts "2. Run: rake error_logs:cleanup_primary_db"
    else
      puts "⚠️  Counts don't match! Review the migration."
      puts "Difference: #{(old_count - new_count).abs} records"
    end
  end

  desc "Clean up error logs from primary database (DESTRUCTIVE)"
  task cleanup_primary_db: :environment do
    print "This will DELETE all error logs from your primary database. Continue? (yes/no): "
    confirmation = STDIN.gets.chomp

    unless confirmation.downcase == 'yes'
      puts "Cleanup cancelled."
      exit
    end

    # Disable separate database to access primary
    RailsErrorDashboard.configuration.use_separate_database = false

    count = RailsErrorDashboard::ErrorLog.count
    puts "Deleting #{count} error logs from primary database..."

    # Delete in batches to avoid locking
    deleted = 0
    batch_size = 1000

    loop do
      batch_deleted = RailsErrorDashboard::ErrorLog.limit(batch_size).delete_all
      deleted += batch_deleted
      print "."
      break if batch_deleted < batch_size
    end

    puts "\n✅ Deleted #{deleted} error logs from primary database"

    # Re-enable separate database
    RailsErrorDashboard.configuration.use_separate_database = true

    puts "\nVerifying separate database still has data..."
    new_count = RailsErrorDashboard::ErrorLog.count
    puts "Separate database has #{new_count} error logs"
  end
end
```

### 2.2 Run the Migration

```bash
# Step 1: Copy data to separate database
rake error_logs:migrate_to_separate_db

# Step 2: Verify the migration
rake error_logs:verify_migration

# Step 3: If verification passes, clean up primary database
rake error_logs:cleanup_primary_db
```

---

## Step 3: Enable Separate Database

### 3.1 Update Initializer

```ruby
# config/initializers/rails_error_dashboard.rb

RailsErrorDashboard.configure do |config|
  # Enable separate database
  config.use_separate_database = true  # Changed from false to true

  # ... other config
end
```

### 3.2 Restart Application

```bash
# Restart your Rails app to pick up the new configuration
```

---

## Step 4: Verify Everything Works

### 4.1 Test Error Logging

Create a test error to ensure new errors go to the separate database:

```bash
rails console
```

```ruby
# Create a test error
begin
  raise "Test error for separate database"
rescue => e
  Rails.error.report(e)
end

# Verify it was created in separate database
RailsErrorDashboard::ErrorLog.last
# Should show your test error
```

### 4.2 Test Dashboard

Visit your error dashboard:
```text
http://localhost:3000/error_dashboard
```

- ✅ All old errors should be visible
- ✅ New errors should be created
- ✅ Analytics should work
- ✅ Search and filtering should work

---

## Rollback Plan

If something goes wrong, you can rollback:

### Option 1: Disable Separate Database

```ruby
# config/initializers/rails_error_dashboard.rb
config.use_separate_database = false
```

This will immediately switch back to using the primary database. If you haven't run cleanup yet, all your data will still be there.

### Option 2: Restore from Backup

Always take a database backup before migration:

```bash
# PostgreSQL
pg_dump myapp_production > backup_before_migration.sql

# MySQL
mysqldump myapp_production > backup_before_migration.sql
```

Restore if needed:

```bash
# PostgreSQL
psql myapp_production < backup_before_migration.sql

# MySQL
mysql myapp_production < backup_before_migration.sql
```

---

## Advanced: Different Database Server

If you want to host error logs on a completely different server:

### 1. Update database.yml

```yaml
production:
  primary:
    database: myapp_production
    host: db1.example.com
    # ... main DB config

  error_logs:
    database: myapp_error_logs_production
    host: db2.example.com  # Different server!
    # ... separate server config
```

### 2. Benefits

- ✅ **True isolation** - Completely separate infrastructure
- ✅ **Independent scaling** - Different server specs for error logs
- ✅ **Zero impact** - Error logging has ZERO impact on main app
- ✅ **Flexible retention** - Can drop entire server without affecting app

---

## Troubleshooting

### Issue: Migration fails with "database doesn't exist"

**Solution:**
```bash
rails db:create:error_logs
rails db:migrate:error_logs
```

### Issue: "No such table: rails_error_dashboard_error_logs"

**Solution:**
```bash
# Run migrations on the separate database
rails db:migrate:error_logs
```

### Issue: Counts don't match after migration

**Solution:**
1. Check for errors in the migration output
2. Look for failed records
3. Re-run migration for failed records only
4. Verify database connections are working

### Issue: Dashboard shows no errors after migration

**Checklist:**
1. Is `use_separate_database = true` in initializer?
2. Did you restart the Rails app?
3. Is the error_logs database configured correctly?
4. Can you connect to the error_logs database?

```bash
# Test connection
rails dbconsole -d error_logs
```

### Issue: New errors still going to primary database

**Solution:**
1. Verify `config.use_separate_database = true`
2. Restart Rails application
3. Check Rails logs for connection errors

---

## Performance Considerations

### Before Migration

- Take database backup
- Run during low-traffic period
- Monitor database performance during migration
- Consider using read replicas if available

### During Migration

- Migration runs in batches of 1000 to avoid memory issues
- Uses transactions per batch for safety
- Progress indicator (dots) shows migration is running
- Failed records are logged for review

### After Migration

- Monitor separate database performance
- Set up separate backup schedule
- Configure retention policies
- Consider different hardware for error logs DB

---

## FAQ

### Q: Can I migrate back from separate DB to primary DB?

**A:** Yes, reverse the rake tasks:
1. Set `use_separate_database = false`
2. Read from separate DB
3. Write to primary DB
4. Verify counts match
5. Drop separate database if desired

### Q: Will this cause downtime?

**A:** No downtime required! The migration can run while your app is running. Just:
1. Run migration task (reads from primary, writes to separate)
2. Verify data
3. Enable separate DB in config
4. Restart app
5. Clean up primary DB

### Q: What about disk space?

**A:** During migration, data exists in BOTH databases. After cleanup, only the separate database has error logs. Plan for:
- 2x disk space during migration
- Normal disk space after cleanup

### Q: Can I use this with Heroku/AWS RDS/Google Cloud SQL?

**A:** Yes! Just configure the `error_logs` database to point to your hosted database. Works with:
- Heroku Postgres (use different DATABASE_URL)
- AWS RDS (different endpoint)
- Google Cloud SQL (different connection string)
- Any PostgreSQL/MySQL/SQLite database

### Q: What if I have millions of error logs?

**A:** For very large datasets:
1. Consider filtering old errors before migration
2. Increase batch size (change `batch_size = 1000` to higher value)
3. Run migration during maintenance window
4. Use database replication if available
5. Consider parallel migration with multiple workers

---

## Best Practices

### 1. Always Backup First

```bash
# Before migration
pg_dump myapp_production > pre_migration_backup.sql
```

### 2. Test in Staging First

Run the entire migration process in your staging environment before production.

### 3. Monitor Database Performance

```bash
# During migration, monitor:
# - Connection counts
# - Query performance
# - Disk I/O
# - Memory usage
```

### 4. Gradual Cleanup

Instead of deleting all at once:
```ruby
# Delete old errors first (already in separate DB)
RailsErrorDashboard::ErrorLog.where('created_at < ?', 30.days.ago).delete_all

# Then delete recent errors
RailsErrorDashboard::ErrorLog.delete_all
```

### 5. Set Up Separate Backups

```bash
# Separate backup schedule for error logs
# Can have different retention policies
0 2 * * * pg_dump myapp_error_logs_production > /backups/error_logs.sql
```

---

## Example: Complete Migration Session

```bash
# 1. Backup
pg_dump myapp_production > backup_$(date +%Y%m%d).sql

# 2. Configure database.yml (add error_logs database)

# 3. Create separate database
rails db:create:error_logs
rails db:migrate:error_logs

# 4. Run migration
rake error_logs:migrate_to_separate_db
# Output:
# Starting error logs migration...
# Found 15432 error logs in primary database
# Loaded 15432 error logs
# ................
# Migration complete!
# Successfully migrated: 15432
# Failed: 0

# 5. Verify
rake error_logs:verify_migration
# Output:
# Primary database: 15432 error logs
# Separate database: 15432 error logs
# ✅ Counts match! Migration successful.

# 6. Enable in initializer
# config.use_separate_database = true

# 7. Restart app
systemctl restart myapp  # or however you restart

# 8. Verify dashboard works
curl http://localhost:3000/error_dashboard

# 9. Clean up primary DB
rake error_logs:cleanup_primary_db
# Output:
# This will DELETE all error logs from your primary database. Continue? (yes/no): yes
# Deleting 15432 error logs from primary database...
# ................
# ✅ Deleted 15432 error logs from primary database
# Separate database has 15432 error logs

# 10. Verify everything still works
# Visit dashboard, create test error, check analytics
```

---

**Made with ❤️  by Anjan for the Rails community**
