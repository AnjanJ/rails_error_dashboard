---
layout: default
title: "Troubleshooting Guide"
permalink: /docs/TROUBLESHOOTING
---

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
- [Deep Debugging Issues](#deep-debugging-issues-v040)
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
   ```bash
   bin/rails middleware | grep ErrorCatcher
   # Should print: use RailsErrorDashboard::Middleware::ErrorCatcher
   ```

2. **Check if middleware is enabled**:
   ```ruby
   RailsErrorDashboard.configuration.enable_middleware
   # Should return: true
   ```

3. **Manually trigger an error to test**: open `/red/settings` and click **Send Test Error**. Or,
   from the console (an error raised at the console prompt is never captured):
   ```ruby
   # In rails console
   Rails.error.report(RuntimeError.new("Test error from console"), handled: false)
   ```
   With async logging on, keep the console open for a second or two so the job can run.

4. **Check Rails.error subscriber**:
   ```ruby
   RailsErrorDashboard.configuration.enable_error_subscriber
   # Should return: true
   ```

5. **Verify database tables exist**:
   ```bash
   bin/rails db:migrate:status | grep -i "rails error dashboard"
   # Should show RED's migrations as "up"
   ```

6. **Check a worker is running**: the installer turns on `config.async_logging`, so each error is
   saved by a background job on the `default` queue. Without a worker, errors never appear. Run
   one, or set `config.async_logging = false` (notifications still need a worker). See
   [Run a worker for RED's jobs](PRODUCTION.md#1-run-a-worker-for-reds-jobs).

---

### Migrations Failing

**Problem**: `rails db:migrate` fails with errors.

**Solutions**:

1. **Check for existing tables**:
   ```bash
   bin/rails db
   # Then (PostgreSQL): \dt rails_error_dashboard_*
   ```

2. **Fix the reported error and re-run**: `bin/rails db:migrate` picks up where it stopped. Don't
   roll back with `db:rollback STEP=N`: the count includes your app's own migrations, and four of
   RED's migrations can't be rolled back. If an install of 0.4.0 to 0.8.1 stopped with
   `duplicate column name: instance_variables`, see
   [Stuck at db:migrate](UPGRADING.md#stuck-at-dbmigrate-after-installing-040-to-081).

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

**Problem**: Visiting the dashboard returns 404.

The installer mounts the dashboard at `/red`. Apps first installed before 0.5.8 mount it at `/error_dashboard`, and an upgrade keeps that path (see [Upgrading](UPGRADING.md#old-mount-path-for-apps-installed-before-058)). Your path is the one in `config/routes.rb`.

**Solutions**:

1. **Verify the mount in routes**:
   ```bash
   bin/rails routes | grep RailsErrorDashboard::Engine
   # Should show: rails_error_dashboard  /red  RailsErrorDashboard::Engine
   ```

2. **Check config/routes.rb**:
   ```ruby
   # Should contain:
   mount RailsErrorDashboard::Engine => "/red"
   ```

3. **Restart the server after adding the mount**:
   ```bash
   bin/rails restart
   ```

4. **Check for route conflicts**: an earlier route matching the same path wins.
   ```bash
   bin/rails routes | grep /red
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
   # In rails console: read the options you changed, one by one
   RailsErrorDashboard.configuration.async_logging
   ```
   Don't print the whole `RailsErrorDashboard.configuration` object: it includes the dashboard
   password, webhook URLs and API keys.

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

1. **Use exact class names, as Strings**:
   ```ruby
   # CORRECT
   config.custom_severity_rules = {
     "ActiveRecord::RecordNotFound" => :low,
     "Stripe::CardError" => :critical
   }

   # INCORRECT (never matches)
   config.custom_severity_rules = {
     /ActiveRecord::RecordNotFound/ => :low,  # Regexp keys are not supported
     /Stripe::/ => :critical
   }
   ```

2. **Check how a type is classified**:
   ```ruby
   # In rails console
   RailsErrorDashboard::Services::SeverityClassifier.classify("ActiveRecord::RecordNotFound")
   # => :low with the rule above
   ```

3. **One rule per class**: a rule doesn't cover subclasses, so list each class you mean. The order
   of the rules doesn't matter.

---

## Error Logging Issues

### Errors Being Logged Multiple Times

**Problem**: Same error creates multiple entries.

**Solutions**:

1. **Check the fingerprints**:
   ```ruby
   # In rails console
   RailsErrorDashboard::ErrorLog.last(2).map(&:error_hash)
   # The same error gets the same 16-character fingerprint
   ```

2. **Know what counts as "the same error"**: the fingerprint covers the error class, the message
   with numbers, quoted strings and object addresses masked, the file of the first backtrace line
   outside your gems, and the controller and action. Two `RuntimeError`s raised in different files
   are two errors. A repeat increments the existing record's `occurrence_count` only while that
   record is unresolved, was first seen in the last 24 hours, and belongs to the same environment
   and application. Otherwise the repeat starts a new record, which notifies like a new error:
   ```ruby
   RailsErrorDashboard::ErrorLog.where(error_type: "RuntimeError").pluck(:id, :occurrence_count, :occurred_at)
   ```

3. **A resolved error that happens again** reopens the same record. One marked "Won't fix" stays
   closed and keeps counting.

---

### Background Job Errors Not Logged

**Problem**: Errors in Sidekiq/Solid Queue jobs don't appear.

**Solutions**:

1. **Ensure error subscriber is enabled**:
   ```ruby
   config.enable_error_subscriber = true
   ```

2. **Check for `retry_on`**: a job error is reported when it escapes the job. While `retry_on`
   still has attempts left, it catches the error and schedules a retry, so nothing is reported
   until the last attempt fails.

3. **Report errors you rescue yourself**: if you rescue an error and don't re-raise it, nothing
   reports it. Report it explicitly:
   ```ruby
   def perform
     # Code
   rescue => e
     Rails.error.report(e, severity: :error)
   end
   ```
   In a rescue that re-raises, you don't need it: the job error is reported when it escapes. (On
   Rails 7.0 it would be counted twice; 7.1 and later skip an exception that was already reported.)
   `Rails.error.report` with the default severity (`:warning`, for a handled error) is ignored by
   RED.

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
   # Set error as critical to bypass sampling (exact class names)
   config.custom_severity_rules = {
     "PaymentError" => :critical  # Always logged
   }
   ```

3. **Adjust rate based on volume**:
   ```ruby
   # Start high, tune down
   config.sampling_rate = 0.5  # 50%
   ```

4. **Know what sampling keeps**: below 1.0, the first occurrence of each error in each process is
   always logged, so sampling never hides that an error exists. There is no per-exception sampling
   hook: to keep every occurrence of a type, map it to `:critical` as in step 2.

---

## Dashboard Access Problems

### App Refuses to Boot: Default or Blank Credentials

**Problem**: Outside development and test, the app (or `db:migrate`, or a console) fails to start with:

```
RailsErrorDashboard::ConfigurationError: Rails Error Dashboard configuration is invalid:

  1. Default or blank credentials cannot be used in production: the dashboard password is the published default and was not set by ERROR_DASHBOARD_PASSWORD. ...
```

**Cause**: the dashboard would be protected by the published default password, or by a blank credential. Common reasons:

- `ERROR_DASHBOARD_PASSWORD` isn't set where the command runs, for example in a release phase or a migration job;
- only `ERROR_DASHBOARD_USER` is set;
- a variable is set but empty, for example a Compose file passing an unset variable through;
- the initializer overwrites the credentials, for example with a hardcoded value.

**Solution**: set `ERROR_DASHBOARD_USER` and `ERROR_DASHBOARD_PASSWORD` to real values in that environment, and remove any `dashboard_username` / `dashboard_password` lines from the initializer. Or configure an `authenticate_with` lambda. See [Dashboard Credentials](guides/CONFIGURATION.md#dashboard-credentials).

### Docker Build Fails During assets:precompile

**Problem**: `docker build` fails at `assets:precompile` with the `ConfigurationError` above.

**Cause**: precompiling boots the app in production, and the build has no secrets.

**Solution**: run the step with `SECRET_KEY_BASE_DUMMY=1`, as the Dockerfile Rails 7.1+ generates does:

```dockerfile
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile
```

Set it on that command only, never in the runtime environment: while it is set, RED captures no errors at all. The login still refuses the default credentials either way.

### Authentication Not Working

**Problem**: Can't access dashboard with correct credentials.

**Solutions**:

1. **Check credentials are set**:
   ```ruby
   # In rails console
   RailsErrorDashboard.configuration.dashboard_username
   RailsErrorDashboard.configuration.dashboard_password
   # Should return your values: not nil, not blank
   ```
   A blank or `nil` value denies every login, in development too. The usual cause is
   `config.dashboard_username = ENV["ERROR_DASHBOARD_USER"]` in the initializer with the variable
   unset. Remove that line: the gem reads the variable itself.

2. **Verify HTTP Basic Auth header**:
   ```bash
   # Test with curl
   curl -u admin:password http://localhost:3000/red
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

1. **Check every migration has run** (they add the indexes):
   ```bash
   bin/rails db:migrate:status | grep -i "rails error dashboard" | grep -v "^ *up"
   # Should print nothing
   ```

2. **Check for N+1 queries**:
   ```ruby
   # Enable query logging in development
   # config/environments/development.rb
   config.active_record.verbose_query_logs = true
   ```

3. **Reduce retention period**:
   ```ruby
   config.retention_days = 30  # Instead of 90
   ```
   Old errors are deleted only when `RailsErrorDashboard::RetentionCleanupJob` runs. See
   [Schedule the periodic jobs](PRODUCTION.md#2-schedule-the-periodic-jobs).

4. **Use separate database**:
   ```ruby
   config.use_separate_database = true
   config.database = :error_dashboard  # must match an entry in config/database.yml
   ```
   See the [Database Options Guide](guides/DATABASE_OPTIONS.md).

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

4. **Check a worker processes the `error_notifications` queue**: Slack and email jobs run there,
   not on `default`.
   ```bash
   # Sidekiq only processes "default" unless told otherwise
   bundle exec sidekiq -q default -q error_notifications

   # Solid Queue (process titles start with solid-queue)
   ps aux | grep solid-queue
   ```

5. **Check the log, not the failed jobs**: the Slack job catches its own errors, so a failed send
   never shows up as a failed job. Look in the Rails log for `Slack notification failed`,
   `Slack HTTP request failed` or `Failed to send Slack notification`.

6. **Check what holds notifications back**:
   - `config.notification_minimum_severity` (default `:low`): new and reopened errors below it
     don't notify. Milestone notifications ignore it.
   - RED notifies on an error's first occurrence, when a resolved error reopens, and when the
     occurrence count reaches one of `notification_threshold_alerts` (10, 50, 100, 500, 1000).
     Raising the same error again within 24 hours of its first occurrence doesn't send another
     notification.
   - Muted errors, errors marked "Won't fix", environments outside `notification_environments`,
     errors during an error storm, and new errors past `notification_burst_limit` don't notify.

7. **Send a test**: open `/red/settings` and click **Send Test Error**. Every click logs the same
   `TestError`, so only the first click notifies (or the first after you resolve it, or after 24
   hours). It is classified `:low`, so a higher `notification_minimum_severity` blocks it.

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
   # In rails console: sends the notification for the latest error, in this process
   RailsErrorDashboard::EmailErrorNotificationJob.perform_now(RailsErrorDashboard::ErrorLog.last.id)
   ```

5. **Check the sender address**: `notification_email_from` defaults to `errors@example.com`, which
   most mail providers reject. Set it to an address your provider allows to send.

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

3. **Check severity** (PagerDuty only receives critical errors, plus baseline alerts at the
   `:critical` level, and there is no setting to change that):
   ```ruby
   RailsErrorDashboard::ErrorLog.last.critical?
   ```

4. **Check the worker**: Discord, PagerDuty and webhook jobs run on the `default` queue.

---

## Performance Problems

### Database Growing Too Large

**Problem**: Error dashboard database is consuming too much space.

**Solutions**:

1. **Configure retention policy**:
   ```ruby
   config.retention_days = 30  # Delete errors not seen for 30 days
   ```
   Nothing is deleted until `RailsErrorDashboard::RetentionCleanupJob` runs, and the gem doesn't
   schedule it. See [Schedule the periodic jobs](PRODUCTION.md#2-schedule-the-periodic-jobs).

2. **Manually clean old errors**:
   ```bash
   # Delete errors not seen for retention_days (asks for confirmation)
   bin/rails error_dashboard:retention_cleanup

   # Delete resolved errors older than 30 days (asks for confirmation)
   bin/rails error_dashboard:cleanup_resolved DAYS=30

   # Unattended, e.g. from cron: no confirmation
   bin/rails runner 'RailsErrorDashboard::RetentionCleanupJob.perform_now'
   ```

3. **Limit backtrace lines**:
   ```ruby
   config.max_backtrace_lines = 20  # Instead of 100
   ```

4. **Enable sampling**:
   ```ruby
   config.sampling_rate = 0.1  # Log 10% of non-critical errors
   ```

5. **Use separate database**:
   ```ruby
   config.use_separate_database = true
   config.database = :error_dashboard  # must match an entry in config/database.yml
   ```

---

### Background Jobs Queuing Up

**Problem**: Error logging jobs piling up in queue.

**Solutions**:

1. **Check job processor is running, on both of RED's queues**:
   ```bash
   # Sidekiq
   bundle exec sidekiq -q default -q error_notifications

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
   Sidekiq::Queue.new("default").size
   Sidekiq::Queue.new("error_notifications").size

   # Solid Queue
   SolidQueue::ReadyExecution.count
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

2. **Check the baselines have been calculated**: nothing alerts until
   `RailsErrorDashboard::BaselineCalculationJob` has run, and the gem doesn't schedule it. Run it
   daily (see [Schedule the periodic jobs](PRODUCTION.md#2-schedule-the-periodic-jobs)), or once by hand:
   ```bash
   bin/rails runner 'RailsErrorDashboard::BaselineCalculationJob.perform_now'
   ```
   An error whose history is completely flat (the same count every period) never alerts.

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

5. **Verify the level filter**:
   ```ruby
   config.baseline_alert_severities
   # Default: [:critical, :high]
   ```
   These are anomaly levels, not error severities: `:high` starts 1 standard deviation above the
   threshold and `:critical` 2 above it. So with the defaults, alerts start at 3 standard deviations
   above the baseline. The lowest level, `:elevated`, can't be selected.

---

### Similar Errors Not Appearing

**Problem**: Fuzzy matching enabled but no similar errors shown.

**Solutions**:

1. **Check feature is enabled**:
   ```ruby
   RailsErrorDashboard.configuration.enable_similar_errors
   # Should return: true
   ```

2. **Verify there is something to compare**: similar errors are other errors on the same
   platform. The score is 0.7 × backtrace similarity (Jaccard) + 0.3 × message similarity, and the
   page lists errors scoring 0.6 or more.

3. **Manually trigger calculation**:
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
   # For example: ["iOS", "Android", "API"]
   ```

3. **Check platform detection**: the platform comes from the request's user agent: `iOS`,
   `Android`, `Mobile` for Expo clients that name neither, and `API` for everything else, browsers
   and other mobile clients included.
   With only one platform there is nothing to compare.

---

## Deep Debugging Issues (v0.4.0)

### Local Variables Not Showing on Error Detail Page

**Problem**: `enable_local_variables` is enabled but errors don't show variable data.

**Solutions**:

1. **Verify feature is enabled**:
   ```ruby
   RailsErrorDashboard.configuration.enable_local_variables
   # Should return: true
   ```

2. **Check that the error was captured AFTER enabling** — existing errors won't have variables. Only new errors get variable data.

3. **Some exceptions don't have local variables** — if the exception is raised in C code or a native extension, TracePoint may not capture locals.

### Swallowed Exceptions Page Empty

**Problem**: `/errors/swallowed_exceptions` shows no data.

**Solutions**:

1. **Check Ruby version** — requires Ruby 3.3+ for `TracePoint(:rescue)`. On Ruby < 3.3, the feature is auto-disabled.

2. **Verify feature is enabled**:
   ```ruby
   RailsErrorDashboard.configuration.detect_swallowed_exceptions
   # Should return: true
   ```

3. **Wait for flush interval** — data is flushed to the database every `swallowed_exception_flush_interval` seconds (default: 60). Check back after a minute.

4. **Check threshold** — only locations where the rescue ratio exceeds `swallowed_exception_threshold` (default: 0.95) are shown.

### Diagnostic Dump Button Not Working

**Problem**: "Capture Dump" button doesn't create a dump.

**Solutions**:

1. **Verify feature is enabled**:
   ```ruby
   RailsErrorDashboard.configuration.enable_diagnostic_dump
   # Should return: true
   ```

2. **Try the rake task** — `rails error_dashboard:diagnostic_dump` to verify the feature works outside the dashboard.

3. **Check browser console** — the button uses a `<form>` POST, not a JavaScript link. If Turbo is interfering, check for JS errors.

### Crash Capture Not Importing on Boot

**Problem**: Process crashed but no crash error appeared after restart.

**Solutions**:

1. **Check crash file path** — look for JSON files in `Dir.tmpdir` (or your custom `crash_capture_path`).

2. **Verify the crash was an unhandled exception** — `at_exit` only captures when `$!` is set (an exception terminated the process). Clean exits via `exit(0)` or `SIGTERM` don't trigger it.

3. **Check file permissions** — the process needs write permission to the crash capture path.

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
2. URL in SSH form (`git@github.com:...`)
3. Git branch strategy misconfigured

**Solutions**:
1. Set repository URL:
   ```ruby
   config.git_repository_url = "https://github.com/myorg/myapp"
   # A trailing .git is fine: it is removed automatically
   ```

2. Choose branch strategy:
   ```ruby
   config.git_branch_strategy = :current_branch  # or :commit_sha, :main
   ```

3. Verify URL format (HTTPS):
   ```ruby
   # ✅ Correct:
   "https://github.com/user/repo"
   "https://github.com/user/repo.git"  # .git is stripped
   "https://gitlab.com/user/repo"

   # ❌ Wrong:
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

3. Verify dark mode is active:
   ```javascript
   // In browser console
   document.documentElement.dataset.theme
   // Should return: "dark" when dark mode is active
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

Source code is cached for `source_code_cache_ttl` seconds (one hour by default), under keys
starting with `source_code/`; git blame under keys starting with `git_blame/`.

**Quick Fix**: wait for the cache to expire, or delete those keys:
```ruby
# In Rails console. Works on the memory, file and Redis stores. Solid Cache, the
# Rails 8 default, doesn't support delete_matched: there, wait for the TTL.
Rails.cache.delete_matched("source_code/*")
Rails.cache.delete_matched("git_blame/*")
```

Don't run `Rails.cache.clear` in production: it empties your whole app's cache.

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
   config.database = :error_dashboard
   ```

   ```yaml
   # config/database.yml: nested under every environment
   production:
     primary:
       <<: *default
       database: myapp_production
     error_dashboard:
       <<: *default
       database: myapp_errors_production
       migrations_paths: db/error_dashboard_migrate
       pool: 10
   ```
   See the [Database Options Guide](guides/DATABASE_OPTIONS.md).

3. **Check for connection leaks**:
   ```ruby
   # In rails console
   ActiveRecord::Base.connection_pool.stat
   # Shows: size, connections, busy, dead, idle, waiting

   # With a separate error database, check its pool too
   RailsErrorDashboard::ErrorLogsRecord.connection_pool.stat
   ```

---

### Slow Queries

**Problem**: Error dashboard queries taking >1 second.

**Solutions**:

1. **Verify indexes exist**:
   ```sql
   -- PostgreSQL (in bin/rails db)
   \d rails_error_dashboard_error_logs
   -- Should show multiple indexes
   ```

2. **Analyze slow queries**:
   ```sql
   -- PostgreSQL
   EXPLAIN ANALYZE
   SELECT * FROM rails_error_dashboard_error_logs
   WHERE occurred_at > NOW() - INTERVAL '7 days';
   ```

3. **Check every RED migration has run**: the indexes come from them, so don't add them by hand.
   ```bash
   bin/rails db:migrate:status | grep -i "rails error dashboard" | grep -v "^ *up"
   # Should print nothing
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

3. **Verify APPLICATION_NAME is set correctly**:
   ```bash
   # Each app should have a unique APPLICATION_NAME (or config.application_name)
   echo $APPLICATION_NAME
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
  config.log_level = :debug  # :debug, :info, :warn, :error, :fatal, :silent
end
```

Both lines are needed: `log_level` defaults to `:silent`, which logs nothing.

Restart server, then check logs:
```bash
tail -f log/development.log | grep -i "rails.\?error.\?dashboard"
```

---

### Test Error Logging Manually

```ruby
# In rails console
begin
  raise "Manual test error"
rescue => e
  RailsErrorDashboard::Commands::LogError.call(e, { platform: "test" })
end

# Check if logged
RailsErrorDashboard::ErrorLog.last
```

`LogError.call` takes the exception and a context Hash, both positional. With `async_logging` on,
it queues a job instead of saving, so the error appears once a worker runs it. The severity comes
from the error class (see
[Custom Severity Classification](guides/CONFIGURATION.md#custom-severity-classification)).

---

### Check Configuration Values

```ruby
# In rails console: read the options you need, one at a time
config = RailsErrorDashboard.configuration
config.async_logging
config.sampling_rate
config.notification_minimum_severity
```

Don't dump every setting: the configuration holds the dashboard password, webhook URLs and API
keys. The [Settings page](guides/SETTINGS.md) (`/red/settings`) shows the current values.

---

### Verify Middleware Stack

```bash
bin/rails middleware
# Look for: use RailsErrorDashboard::Middleware::ErrorCatcher
```

---

### Test Notifications Directly

```ruby
# In rails console: each job takes the error's id, positionally
id = RailsErrorDashboard::ErrorLog.last.id

# Slack
RailsErrorDashboard::SlackErrorNotificationJob.perform_now(id)

# Email
RailsErrorDashboard::EmailErrorNotificationJob.perform_now(id)

# Discord
RailsErrorDashboard::DiscordErrorNotificationJob.perform_now(id)
```

The jobs catch their own errors and log them, so check the log for the result. Or use the
Settings page's **Send Test Error** button.

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
   - The configuration options involved (not the whole configuration object: it holds secrets)
   - Steps to reproduce

4. **Security Issues**: See [SECURITY.md](../SECURITY.md) - DO NOT open public issue

---

## Related Documentation

- **[Configuration Guide](guides/CONFIGURATION.md)** - All configuration options
- **[Settings Dashboard](guides/SETTINGS.md)** - Verify current configuration
- **[API Reference](API_REFERENCE.md)** - API endpoints and Ruby API
- **[QUICKSTART](QUICKSTART.md)** - Installation and setup

---

**Pro Tip**: When debugging, set both `enable_internal_logging = true` and `log_level = :debug`. With the default `log_level` (`:silent`), internal logging shows nothing.
