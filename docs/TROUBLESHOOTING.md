# Troubleshooting Guide

Comprehensive troubleshooting guide for Rails Error Dashboard. Solutions to common problems, error messages, and debugging techniques.

---

## Table of Contents

- [Installation & Setup Issues](#installation--setup-issues)
- [Configuration Problems](#configuration-problems)
- [Error Logging Issues](#error-logging-issues)
- [Dashboard Access Problems](#dashboard-access-problems)
- [Notification Issues](#notification-issues)
- [Performance Problems](#performance-problems)
- [Advanced Features Not Working](#advanced-features-not-working)
- [Source Code Integration Issues](#source-code-integration-issues)
- [Database Issues](#database-issues)
- [Multi-App Setup Problems](#multi-app-setup-problems)
- [Debugging Techniques](#debugging-techniques)

---

## Installation & Setup Issues

### Errors Not Being Logged After Installation

**Symptoms**: Dashboard is accessible but no errors appear.

**Solutions**:

1. **Verify middleware is installed**:
   ```ruby
   # In rails console
   Rails.application.config.middleware.to_a.grep(/ErrorCatcher/)
   # Should return: [RailsErrorDashboard::Middleware::ErrorCatcher]
   ```

2. **Check if middleware is enabled**:
   ```ruby
   RailsErrorDashboard.configuration.enable_middleware
   # Should return: true
   ```

3. **Manually trigger an error to test**:
   ```ruby
   # In rails console
   raise "Test error from console"
   ```

4. **Check Rails.error subscriber**:
   ```ruby
   RailsErrorDashboard.configuration.enable_error_subscriber
   # Should return: true
   ```

5. **Verify database tables exist**:
   ```bash
   rails db:migrate:status | grep error_dashboard
   # Should show multiple migrations as "up"
   ```

---

### Migrations Failing

**Problem**: `rails db:migrate` fails with errors.

**Solutions**:

1. **Check for existing tables**:
   ```bash
   rails db
   # Then: \dt error_dashboard*
   ```

2. **Rollback and re-run**:
   ```bash
   rails db:rollback STEP=5
   rails db:migrate
   ```

3. **Drop and recreate (DEVELOPMENT ONLY)**:
   ```bash
   rails db:drop db:create db:migrate
   ```

4. **Check database permissions**:
   ```sql
   -- PostgreSQL
   GRANT ALL PRIVILEGES ON DATABASE your_db TO your_user;
   ```

---

### Dashboard Not Mounted / 404 Error

**Problem**: Visiting `/error_dashboard` returns 404.

**Solutions**:

1. **Verify mount in routes**:
   ```bash
   rails routes | grep error_dashboard
   # Should show multiple routes
   ```

2. **Check config/routes.rb**:
   ```ruby
   # Should contain:
   mount RailsErrorDashboard::Engine => "/error_dashboard"
   ```

3. **Restart server after adding mount**:
   ```bash
   rails server
   ```

4. **Check for route conflicts**:
   ```bash
   # Look for conflicting /error_dashboard routes
   rails routes | grep /error
   ```

---

## Configuration Problems

### Configuration Not Taking Effect

**Problem**: Changes to `config/initializers/rails_error_dashboard.rb` don't work.

**Solutions**:

1. **Restart server** (required for initializer changes):
   ```bash
   rails server
   ```

2. **Check file location**:
   ```bash
   ls -la config/initializers/rails_error_dashboard.rb
   # File must exist in config/initializers/
   ```

3. **Check for syntax errors**:
   ```bash
   ruby -c config/initializers/rails_error_dashboard.rb
   # Should return: Syntax OK
   ```

4. **Verify configuration is loaded**:
   ```ruby
   # In rails console
   RailsErrorDashboard.configuration.inspect
   # Shows all current settings
   ```

---

### Environment Variables Not Working

**Problem**: `ENV['VARIABLE']` returns `nil` in configuration.

**Solutions**:

1. **Verify variable is set**:
   ```bash
   echo $SLACK_WEBHOOK_URL
   # Should output the URL
   ```

2. **Use dotenv-rails in development**:
   ```ruby
   # Gemfile
   gem 'dotenv-rails', groups: [:development, :test]
   ```

   ```bash
   # .env file
   SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...
   ```

3. **Provide defaults in config**:
   ```ruby
   config.slack_webhook_url = ENV.fetch('SLACK_WEBHOOK_URL', nil)
   ```

4. **Check ENV vars are loaded before Rails**:
   ```ruby
   # config/application.rb (top of file)
   require 'dotenv/rails-now' if defined?(Dotenv)
   ```

---

### Custom Severity Rules Not Working

**Problem**: Custom severity rules aren't being applied.

**Solutions**:

1. **Use regex, not strings**:
   ```ruby
   # CORRECT
   config.custom_severity_rules = {
     /ActiveRecord::RecordNotFound/ => :low,
     /Stripe::/ => :critical
   }

   # INCORRECT (won't match)
   config.custom_severity_rules = {
     "ActiveRecord::RecordNotFound" => :low  # String won't match!
   }
   ```

2. **Test regex patterns**:
   ```ruby
   # In rails console
   error_class = "ActiveRecord::RecordNotFound"
   /ActiveRecord::RecordNotFound/.match?(error_class)
   # Should return: true
   ```

3. **Check rule order** (first match wins):
   ```ruby
   # More specific first
   config.custom_severity_rules = {
     /ActiveRecord::RecordNotFound.*User/ => :high,   # Specific
     /ActiveRecord::RecordNotFound/ => :low           # General
   }
   ```

---

## Error Logging Issues

### Errors Being Logged Multiple Times

**Problem**: Same error creates multiple entries.

**Solutions**:

1. **Check hash signature generation**:
   ```ruby
   # In rails console
   error = RailsErrorDashboard::ErrorLog.last
   error.hash_signature
   # Should be consistent SHA-256 hash
   ```

2. **Verify deduplication is working**:
   ```ruby
   # Same error type should increment occurrence_count, not create new record
   error = RailsErrorDashboard::ErrorLog.find_by(error_type: "RuntimeError")
   error.occurrence_count
   # Should be > 1 if error happened multiple times
   ```

3. **Check for race conditions**:
   - Ensure pessimistic locking is working
   - Check database transaction log for conflicts

---

### Background Job Errors Not Logged

**Problem**: Errors in Sidekiq/Solid Queue jobs don't appear.

**Solutions**:

1. **Ensure error subscriber is enabled**:
   ```ruby
   config.enable_error_subscriber = true
   ```

2. **Check job adapter error handling**:
   ```ruby
   # Sidekiq example
   class YourJob < ApplicationJob
     retry_on StandardError, wait: :exponentially_longer

     def perform
       # Your code
     end
   end
   ```

3. **Manually log in job rescue blocks**:
   ```ruby
   def perform
     # Code
   rescue => e
     RailsErrorDashboard::Commands::LogError.call(exception: e)
     raise # Re-raise to let job adapter handle retry
   end
   ```

---

### Sampling Too Aggressive

**Problem**: Too many errors being filtered out.

**Solutions**:

1. **Check sampling rate**:
   ```ruby
   RailsErrorDashboard.configuration.sampling_rate
   # 0.1 = 10%, 1.0 = 100%
   ```

2. **Critical errors always logged** (bypass sampling):
   ```ruby
   # Set error as critical to bypass sampling
   config.custom_severity_rules = {
     /Payment/ => :critical  # Always logged
   }
   ```

3. **Adjust rate based on volume**:
   ```ruby
   # Start high, tune down
   config.sampling_rate = 0.5  # 50%
   ```

4. **Use conditional sampling**:
   ```ruby
   config.before_log_callback = lambda do |exception, context|
     # Always log payment errors
     return true if exception.message.include?("Stripe")

     # Sample others
     Rails.env.production? ? rand < 0.1 : true
   end
   ```

---

## Dashboard Access Problems

### Authentication Not Working

**Problem**: Can't access dashboard with correct credentials.

**Solutions**:

1. **Check credentials are set**:
   ```ruby
   # In rails console
   RailsErrorDashboard.configuration.dashboard_username
   RailsErrorDashboard.configuration.dashboard_password
   # Should return configured values (not nil)
   ```

2. **Verify HTTP Basic Auth header**:
   ```bash
   # Test with curl
   curl -u admin:password http://localhost:3000/error_dashboard
   # Should return 200, not 401
   ```

3. **Clear browser cache** (old credentials may be cached):
   - Chrome: Cmd+Shift+Delete → Clear browsing data
   - Or use incognito window

4. **Check for proxy/load balancer stripping Authorization header**:
   ```nginx
   # Nginx example - ensure proxy passes auth header
   proxy_set_header Authorization $http_authorization;
   proxy_pass_header Authorization;
   ```

---

### Dashboard Slow to Load

**Problem**: Dashboard pages take >5 seconds to load.

**Solutions**:

1. **Enable async logging**:
   ```ruby
   config.async_logging = true
   ```

2. **Add database indexes** (should be automatic):
   ```bash
   rails db:migrate:status | grep add_indexes
   # Should show "up"
   ```

3. **Check for N+1 queries**:
   ```ruby
   # Enable query logging in development
   # config/environments/development.rb
   config.active_record.verbose_query_logs = true
   ```

4. **Reduce retention period**:
   ```ruby
   config.retention_days = 30  # Instead of 90
   ```

5. **Use separate database**:
   ```ruby
   config.use_separate_database = true
   config.database = :errors
   ```

---

## Notification Issues

### Slack Notifications Not Sending

**Problem**: Slack notifications configured but not arriving.

**Solutions**:

1. **Verify notifications are enabled**:
   ```ruby
   # In rails console
   RailsErrorDashboard.configuration.enable_slack_notifications
   # Should return: true
   ```

2. **Check webhook URL is set**:
   ```ruby
   RailsErrorDashboard.configuration.slack_webhook_url
   # Should return your webhook URL
   ```

3. **Test webhook manually**:
   ```bash
   curl -X POST YOUR_WEBHOOK_URL \
     -H 'Content-Type: application/json' \
     -d '{"text": "Test message from Rails Error Dashboard"}'
   # Should receive message in Slack
   ```

4. **Check background jobs are running**:
   ```bash
   # Sidekiq
   ps aux | grep sidekiq

   # Solid Queue
   ps aux | grep solid_queue
   ```

5. **Check failed jobs**:
   ```ruby
   # Sidekiq
   require 'sidekiq/api'
   Sidekiq::RetrySet.new.size  # Failed jobs
   Sidekiq::DeadSet.new.size   # Dead jobs

   # Solid Queue
   SolidQueue::Job.failed.count
   ```

6. **Verify notification thresholds**:
   ```ruby
   # Check if error severity matches notification threshold
   config.severity_thresholds[:slack]
   # Returns minimum severity for Slack notifications
   ```

---

### Email Notifications Not Sending

**Problem**: Email notifications configured but not arriving.

**Solutions**:

1. **Check ActionMailer configuration**:
   ```ruby
   # config/environments/production.rb
   config.action_mailer.delivery_method = :smtp
   config.action_mailer.smtp_settings = {
     address: "smtp.gmail.com",
     port: 587,
     # ...
   }
   ```

2. **Verify email recipients are set**:
   ```ruby
   RailsErrorDashboard.configuration.notification_email_recipients
   # Should return: ["team@example.com"]
   ```

3. **Check email is enabled**:
   ```ruby
   RailsErrorDashboard.configuration.enable_email_notifications
   # Should return: true
   ```

4. **Test email delivery**:
   ```ruby
   # In rails console
   TestMailer.test_email.deliver_now
   ```

---

### Discord/PagerDuty Notifications Failing

**Problem**: Discord or PagerDuty webhooks not working.

**Solutions**:

1. **Check webhook URL format**:
   ```ruby
   # Discord
   config.discord_webhook_url
   # Should start with: https://discord.com/api/webhooks/

   # PagerDuty
   config.pagerduty_integration_key
   # Should be valid integration key
   ```

2. **Test webhook manually**:
   ```bash
   # Discord
   curl -X POST "https://discord.com/api/webhooks/YOUR_WEBHOOK" \
     -H "Content-Type: application/json" \
     -d '{"content": "Test message"}'

   # PagerDuty
   curl -X POST "https://events.pagerduty.com/v2/enqueue" \
     -H "Content-Type: application/json" \
     -d '{
       "routing_key": "YOUR_KEY",
       "event_action": "trigger",
       "payload": {
         "summary": "Test",
         "severity": "critical",
         "source": "test"
       }
     }'
   ```

3. **Check severity filtering** (PagerDuty only sends critical):
   ```ruby
   # PagerDuty only receives critical errors by default
   config.severity_thresholds[:pagerduty]
   # Should return: :critical
   ```

---

## Performance Problems

### Database Growing Too Large

**Problem**: Error dashboard database is consuming too much space.

**Solutions**:

1. **Configure retention policy**:
   ```ruby
   config.retention_days = 30  # Auto-delete after 30 days
   ```

2. **Manually clean old errors**:
   ```bash
   rails rails_error_dashboard:cleanup_old_errors
   ```

3. **Limit backtrace lines**:
   ```ruby
   config.max_backtrace_lines = 20  # Instead of 50
   ```

4. **Enable sampling**:
   ```ruby
   config.sampling_rate = 0.1  # Log 10% of non-critical errors
   ```

5. **Use separate database**:
   ```ruby
   config.use_separate_database = true
   config.database = :errors
   ```

---

### Background Jobs Queuing Up

**Problem**: Error logging jobs piling up in queue.

**Solutions**:

1. **Check job processor is running**:
   ```bash
   # Sidekiq
   bundle exec sidekiq

   # Solid Queue
   bin/jobs
   ```

2. **Increase job concurrency**:
   ```yaml
   # config/sidekiq.yml
   :concurrency: 10  # Instead of 5
   ```

3. **Monitor queue size**:
   ```ruby
   # Sidekiq
   require 'sidekiq/api'
   Sidekiq::Queue.new.size

   # Solid Queue
   SolidQueue::Job.pending.count
   ```

4. **Consider sync logging temporarily**:
   ```ruby
   config.async_logging = false  # For debugging
   ```

---

## Advanced Features Not Working

### Baseline Alerts Not Triggering

**Problem**: Baseline monitoring enabled but no alerts.

**Solutions**:

1. **Check feature is enabled**:
   ```ruby
   RailsErrorDashboard.configuration.enable_baseline_alerts
   # Should return: true
   ```

2. **Verify minimum data exists**:
   - Need at least 7 days of error history
   - Need at least 10 occurrences of an error type

3. **Check threshold settings**:
   ```ruby
   config.baseline_alert_threshold_std_devs
   # Default: 2.0 (2 standard deviations)
   # Lower = more sensitive, Higher = less sensitive
   ```

4. **Check cooldown period**:
   ```ruby
   config.baseline_alert_cooldown_minutes
   # Default: 120 (2 hours between alerts for same error)
   ```

5. **Verify severity filter**:
   ```ruby
   config.baseline_alert_severities
   # Default: [:critical, :high]
   # Only these severities trigger baseline alerts
   ```

---

### Similar Errors Not Appearing

**Problem**: Fuzzy matching enabled but no similar errors shown.

**Solutions**:

1. **Check feature is enabled**:
   ```ruby
   RailsErrorDashboard.configuration.enable_similar_errors
   # Should return: true
   ```

2. **Verify enough errors exist**:
   - Need at least 10 different error types
   - Similarity requires variation in messages/backtraces

3. **Check similarity thresholds**:
   - Jaccard similarity: 70% match required
   - Levenshtein distance: Calculated proportionally

4. **Manually trigger calculation**:
   ```ruby
   # In rails console
   error = RailsErrorDashboard::ErrorLog.last
   similar = RailsErrorDashboard::Queries::SimilarErrors.call(error.id)
   similar.inspect
   ```

---

### Platform Comparison Shows No Data

**Problem**: Platform comparison enabled but shows empty.

**Solutions**:

1. **Check feature is enabled**:
   ```ruby
   RailsErrorDashboard.configuration.enable_platform_comparison
   # Should return: true
   ```

2. **Verify platform data exists**:
   ```ruby
   # In rails console
   RailsErrorDashboard::ErrorLog.pluck(:platform).uniq
   # Should return: ["iOS", "Android", "Web", etc.]
   ```

3. **Check platform detection**:
   - Ensure errors are tagged with platform
   - Mobile apps should send platform parameter
   - Browser gem detects web platforms

---

## Source Code Integration Issues

### Source Code Not Showing

**Problem**: "View Source" button not appearing on error details.

**Quick Check**:
```ruby
# In Rails console
RailsErrorDashboard.configuration.enable_source_code_integration
# Should return: true
```

**Common Causes**:
1. Feature not enabled in configuration
2. File path is outside Rails.root
3. Frame category is not `:app` (gem frames don't show source)
4. File doesn't exist or isn't readable

**Solutions**:
1. Enable in initializer:
   ```ruby
   config.enable_source_code_integration = true
   ```

2. Restart Rails server (required for initializer changes)

3. Verify file exists and is readable:
   ```bash
   ls -la app/controllers/users_controller.rb
   ```

4. Check Rails.root is correct:
   ```ruby
   Rails.root
   # => /Users/you/myapp
   ```

**Detailed Troubleshooting**: See [Source Code Integration Documentation](SOURCE_CODE_INTEGRATION.md#troubleshooting) for 10+ specific scenarios and solutions.

---

### Git Blame Not Working

**Problem**: Source code shows but no git blame information.

**Quick Check**:
```bash
git --version
# Should output: git version 2.x.x
```

**Common Causes**:
1. Git not installed or not in PATH
2. Not a git repository
3. File not committed to git
4. Git blame not enabled in config

**Solutions**:
1. Enable git blame:
   ```ruby
   config.enable_git_blame = true
   ```

2. Verify git repository:
   ```bash
   git rev-parse --git-dir
   # Should output: .git
   ```

3. Check file is committed:
   ```bash
   git log -- app/controllers/users_controller.rb
   # Should show commit history
   ```

4. Test git blame manually:
   ```bash
   git blame -L 42,42 --porcelain app/controllers/users_controller.rb
   ```

**Detailed Troubleshooting**: See [Source Code Integration Documentation](SOURCE_CODE_INTEGRATION.md#git-blame-not-working)

---

### Repository Links Not Generating

**Problem**: No "View on GitHub" button appearing.

**Quick Check**:
```ruby
RailsErrorDashboard.configuration.git_repository_url
# Should return your repository URL
```

**Common Causes**:
1. Repository URL not configured
2. URL format incorrect (has .git suffix)
3. Git branch strategy misconfigured

**Solutions**:
1. Set repository URL:
   ```ruby
   config.git_repository_url = "https://github.com/myorg/myapp"
   # Remove .git suffix if present!
   ```

2. Choose branch strategy:
   ```ruby
   config.git_branch_strategy = :current_branch  # or :commit_sha, :main
   ```

3. Verify URL format (no .git):
   ```ruby
   # ✅ Correct:
   "https://github.com/user/repo"
   "https://gitlab.com/user/repo"

   # ❌ Wrong:
   "https://github.com/user/repo.git"  # Remove .git!
   "git@github.com:user/repo.git"      # Use HTTPS format
   ```

**Detailed Troubleshooting**: See [Source Code Integration Documentation](SOURCE_CODE_INTEGRATION.md#repository-links-not-generating)

---

### Permission Denied Errors

**Problem**: Getting "Permission denied" when reading source files.

**Check Permissions**:
```bash
ls -la app/controllers/users_controller.rb
# Should show: -rw-r--r-- or similar readable permissions
```

**Solutions**:
1. Fix file permissions:
   ```bash
   chmod 644 app/controllers/**/*.rb
   ```

2. Check Rails server user:
   ```bash
   ps aux | grep rails
   # Note which user is running Rails
   ```

3. Ensure that user can read files:
   ```bash
   sudo -u rails-user cat app/controllers/users_controller.rb
   ```

4. Docker users - check volume permissions:
   ```dockerfile
   RUN chown -R app:app /app
   USER app
   ```

---

### Dark Mode Styling Issues

**Problem**: Source code viewer not styled correctly in dark mode.

**Solutions**:
1. Ensure you're on v0.1.30+:
   ```bash
   bundle update rails_error_dashboard
   ```

2. Clear browser cache:
   - Chrome/Firefox: Cmd+Shift+R (Mac) or Ctrl+F5 (Windows)

3. Verify dark mode CSS loaded:
   ```javascript
   // In browser console
   document.body.classList.contains('dark-mode')
   // Should return: true when dark mode is active
   ```

---

### Performance Issues with Source Code

**Problem**: Error details page loads slowly with source code integration.

**Quick Fixes**:
1. Reduce context lines:
   ```ruby
   config.source_code_context_lines = 3  # Default: 5
   ```

2. Increase cache TTL:
   ```ruby
   config.source_code_cache_ttl = 7200  # 2 hours
   ```

3. Disable git blame in production:
   ```ruby
   if Rails.env.production?
     config.enable_git_blame = false  # Faster without git commands
   end
   ```

4. Use Redis cache for better performance:
   ```ruby
   # config/application.rb
   config.cache_store = :redis_cache_store, { url: ENV["REDIS_URL"] }
   ```

---

### Caching Issues (Stale Code)

**Problem**: Seeing old/stale source code after making changes.

**Quick Fix**:
```ruby
# In Rails console
Rails.cache.clear
# Or specifically:
Rails.cache.delete_matched("source_code/*")
```

**Development Setup**:
```ruby
# Shorter cache in development
if Rails.env.development?
  config.source_code_cache_ttl = 60  # 1 minute instead of 1 hour
end
```

---

### Complete Troubleshooting Guide

For comprehensive troubleshooting with 10+ scenarios, solutions, and examples, see:
**[Source Code Integration Documentation - Troubleshooting Section](SOURCE_CODE_INTEGRATION.md#troubleshooting)**

Includes solutions for:
- File not found errors
- Symlink issues
- Docker volume problems
- SELinux/AppArmor restrictions
- Git blame showing wrong author
- Configuration mistakes
- And more...

---

## Database Issues

### Connection Pool Exhausted

**Problem**: "Could not obtain a connection from the pool" errors.

**Solutions**:

1. **Increase pool size**:
   ```yaml
   # config/database.yml
   production:
     pool: 20  # Instead of 5
   ```

2. **Use separate database with dedicated pool**:
   ```ruby
   config.use_separate_database = true
   config.database = :errors
   ```

   ```yaml
   # config/database.yml
   errors:
     <<: *default
     database: errors_production
     pool: 10
   ```

3. **Check for connection leaks**:
   ```ruby
   # In rails console
   ActiveRecord::Base.connection_pool.stat
   # Shows: size, connections, busy, dead, idle, waiting
   ```

---

### Slow Queries

**Problem**: Error dashboard queries taking >1 second.

**Solutions**:

1. **Verify indexes exist**:
   ```sql
   -- PostgreSQL
   \d error_dashboard_error_logs
   # Should show multiple indexes
   ```

2. **Analyze slow queries**:
   ```sql
   -- PostgreSQL
   EXPLAIN ANALYZE
   SELECT * FROM error_dashboard_error_logs
   WHERE occurred_at > NOW() - INTERVAL '7 days';
   ```

3. **Add composite indexes if missing**:
   ```ruby
   # Should already exist from migrations
   add_index :error_dashboard_error_logs, [:application_id, :occurred_at]
   add_index :error_dashboard_error_logs, [:hash_signature]
   ```

---

## Multi-App Setup Problems

### Errors from Wrong Application Appearing

**Problem**: Seeing errors from different apps in filtered view.

**Solutions**:

1. **Verify application names are unique**:
   ```ruby
   # In rails console
   RailsErrorDashboard::Application.pluck(:name)
   # Each should be unique
   ```

2. **Check application filter in UI**:
   - Look for application dropdown in dashboard
   - Ensure correct app is selected

3. **Verify APP_NAME is set correctly**:
   ```bash
   # Each app should have unique APP_NAME
   echo $APP_NAME
   # Should output: my-api, my-admin, etc.
   ```

4. **Check error application_id**:
   ```ruby
   error = RailsErrorDashboard::ErrorLog.last
   error.application.name
   # Should match expected app
   ```

---

### Application Not Auto-Created

**Problem**: New application not appearing in dashboard.

**Solutions**:

1. **Check application_name configuration**:
   ```ruby
   RailsErrorDashboard.configuration.application_name
   # Should return app name
   ```

2. **Manually create application**:
   ```ruby
   # In rails console
   RailsErrorDashboard::Application.find_or_create_by_name("my-app")
   ```

3. **Verify auto-detection fallback**:
   ```ruby
   # Should use Rails.application name if not set
   Rails.application.class.module_parent_name
   ```

---

## Debugging Techniques

### Enable Internal Logging

See what Rails Error Dashboard is doing internally:

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  config.enable_internal_logging = true
  config.log_level = :debug  # :debug, :info, :warn, :error, :silent
end
```

Restart server, then check logs:
```bash
tail -f log/development.log | grep "RailsErrorDashboard"
```

---

### Test Error Logging Manually

```ruby
# In rails console
begin
  raise "Manual test error"
rescue => e
  RailsErrorDashboard::Commands::LogError.call(
    exception: e,
    occurred_at: Time.current,
    platform: "test",
    severity: :high
  )
end

# Check if logged
RailsErrorDashboard::ErrorLog.last
```

---

### Check Configuration Values

```ruby
# In rails console
config = RailsErrorDashboard.configuration

# View all settings
config.instance_variables.each do |var|
  puts "#{var}: #{config.instance_variable_get(var).inspect}"
end
```

---

### Verify Middleware Stack

```ruby
# In rails console
Rails.application.config.middleware.to_a.each do |middleware|
  puts middleware.inspect
end

# Look for: RailsErrorDashboard::Middleware::ErrorCatcher
```

---

### Test Notifications Directly

```ruby
# Slack
RailsErrorDashboard::SlackNotificationJob.perform_now(error_log_id: 123)

# Email
RailsErrorDashboard::EmailNotificationJob.perform_now(error_log_id: 123)

# Discord
RailsErrorDashboard::DiscordNotificationJob.perform_now(error_log_id: 123)
```

---

## Getting Help

If you've tried the solutions above and still have issues:

1. **Check GitHub Issues**: [Rails Error Dashboard Issues](https://github.com/AnjanJ/rails_error_dashboard/issues)
2. **Search Discussions**: [GitHub Discussions](https://github.com/AnjanJ/rails_error_dashboard/discussions)
3. **Open New Issue**: Include:
   - Rails version
   - Ruby version
   - Gem version
   - Error message (full backtrace)
   - Configuration (sanitize secrets!)
   - Steps to reproduce

4. **Security Issues**: See [SECURITY.md](../SECURITY.md) - DO NOT open public issue

---

## Related Documentation

- **[Configuration Guide](guides/CONFIGURATION.md)** - All configuration options
- **[Settings Dashboard](guides/SETTINGS.md)** - Verify current configuration
- **[API Reference](API_REFERENCE.md)** - API endpoints and Ruby API
- **[QUICKSTART](QUICKSTART.md)** - Installation and setup

---

**Pro Tip**: Enable internal logging (`enable_internal_logging = true`) when debugging issues. It reveals exactly what Rails Error Dashboard is doing internally.
