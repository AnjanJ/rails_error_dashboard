---
layout: default
title: "Quickstart Guide"
order: 2
---

# Quickstart Guide

Get Rails Error Dashboard up and running in 5 minutes!

## Prerequisites

- Rails 7.0 or later (supports 7.0, 7.1, 7.2, 8.0, 8.1)
- Ruby 3.2 or later (supports 3.2, 3.3, 3.4, 4.0)
- SQLite, PostgreSQL, or MySQL database
- `pagy ~> 43` and `groupdate ~> 6`. If your app pins an older Pagy or groupdate, upgrade it first, or `bundle install` fails.
- **Rails before 8.1.4 or 7.2.4** (every 8.0, 7.1 and 7.0 release): add `gem "json", "< 3"` to your Gemfile. json 3 breaks those Rails versions, and the dashboard returns 500. See [the json pin](/rails_error_dashboard/docs/upgrading/#rails-before-814-or-724-pin-json-below-3).
- **MySQL**: load the time-zone tables, or the charts fail: `mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql -u root mysql`.

## Installation

### 1. Add to Gemfile

```ruby
gem 'rails_error_dashboard'
```

### 2. Install with Interactive Setup

```bash
bundle install
bin/rails generate rails_error_dashboard:install
bin/rails db:migrate
```

**Chose a separate or shared database?** Add the `config/database.yml` entry the installer prints, for every environment, then run `bin/rails db:create` before `db:migrate`. See [Database Options](/rails_error_dashboard/docs/guides/database-options/).

### What the Installer Asks

Three groups of questions, then where to store errors:

1. **[1/3] Notifications** (default: no). Yes asks about each channel: Slack, email, Discord, PagerDuty and webhooks.
2. **[2/3] Advanced Analytics** (default: yes). All seven together: baseline anomaly alerts, fuzzy error matching, co-occurring errors, error cascades, error correlation, platform comparison and occurrence patterns.
3. **[3/3] Advanced Options**: listed, but currently not asked. Async logging stays on, and error sampling, breadcrumbs, system health snapshots, the source code viewer, git blame, swallowed exception detection (Ruby 3.3+), crash capture and diagnostic dumps stay off. Turn them on with flags (`--breadcrumbs`, `--system-health` and so on) or later in the initializer.
4. **Database Setup**: 1) your app's database (the default), 2) a separate database, or 3) a database shared with your other apps. For 2 and 3 the installer prints the `config/database.yml` entry to add.

The installer doesn't offer local variable capture, instance variable capture or Rack::Attack tracking. To use them, add `config.enable_local_variables = true`, `config.enable_instance_variables = true` or `config.enable_rack_attack_tracking = true` to the initializer.

**Without a terminal** (CI, Docker, a script) the installer asks nothing. Async logging is on, every other optional feature is off, and errors go to your app's database. Pass `--quick` instead to turn on the analytics, breadcrumbs, system health snapshots and 50% sampling of non-critical errors without any questions. Flags such as `--slack` or `--separate-database` also skip their question; `bin/rails generate rails_error_dashboard:install --help` lists them all.

That's it! The dashboard is now available at `/red` in your Rails app.

## First Steps

### Access the Dashboard

Visit `http://localhost:3000/red` to see the error dashboard.

Initially, you won't see any errors. The quickest test: open `/red/settings` and click **Send Test Error**. It sends a `RailsErrorDashboard::TestError` through capture and through any notifications you've set up.

Errors raised at the Rails console prompt are not captured. To report one from the console:

```ruby
Rails.error.report(RuntimeError.new("Test error from console"), handled: false)
```

With async logging on (the default), leave the console open for a second or two so the background job can write it.

Or raise one in a controller:

```ruby
# app/controllers/home_controller.rb
class HomeController < ApplicationController
  def index
    raise "Test error from controller"
  end
end
```

Visit the route, then check `/red`: you should see your test error.

### Configure Basic Settings

The installer creates `config/initializers/rails_error_dashboard.rb` with your selected features already configured:

```ruby
RailsErrorDashboard.configure do |config|
  # ============================================================================
  # AUTHENTICATION (Always Required)
  # ============================================================================
  config.dashboard_username = ENV.fetch("ERROR_DASHBOARD_USER", "gandalf")
  config.dashboard_password = ENV.fetch("ERROR_DASHBOARD_PASSWORD", "youshallnotpass")

  # ============================================================================
  # CORE FEATURES (Always Enabled)
  # ============================================================================
  config.enable_middleware = true
  config.enable_error_subscriber = true
  config.user_model = "User"
  config.retention_days = 90

  # ============================================================================
  # OPTIONAL FEATURES (Based on your selections during install)
  # ============================================================================

  # Async Logging - ENABLED by default. Jobs run on your app's Active Job adapter.
  config.async_logging = true

  # Slack Notifications - ENABLED (if you selected it during install)
  config.enable_slack_notifications = true
  config.slack_webhook_url = ENV["SLACK_WEBHOOK_URL"]

  # Baseline Anomaly Alerts - ENABLED (if you selected it during install)
  config.enable_baseline_alerts = true
  config.baseline_alert_threshold_std_devs = 2.0

  # ... other features based on your selections
end
```

**Before you deploy.** `gandalf` / `youshallnotpass` work in development and test only. In every other environment (production, staging, or any other name) the app refuses to boot on them. Set `ERROR_DASHBOARD_USER` and `ERROR_DASHBOARD_PASSWORD` where the app runs. You don't need to edit the initializer, because the gem reads both variables itself. See [Dashboard Credentials](/rails_error_dashboard/docs/guides/configuration/#dashboard-credentials) for details, including Docker builds and Rails credentials.

**Using Devise or another auth system?** Replace HTTP Basic Auth with a lambda:

```ruby
config.authenticate_with = -> { warden.authenticated? }
```

> **Note:** Devise helpers like `current_user` are not available in the engine controller context. Use `warden` directly instead. See the [Configuration Guide](/rails_error_dashboard/docs/guides/configuration/#custom-authentication) for details and examples.

You can enable or disable any feature at any time by editing this file. Just change `true` to `false` (or vice versa) and restart your Rails server.

## Enabling Features After Installation

All features can be toggled on/off at any time by editing `config/initializers/rails_error_dashboard.rb`:

### Enable a Feature

To enable a feature that was disabled during installation:

```ruby
RailsErrorDashboard.configure do |config|
  # Change from false to true
  config.enable_slack_notifications = true
  config.slack_webhook_url = ENV['SLACK_WEBHOOK_URL']
end
```

### Disable a Feature

To disable a feature that was enabled during installation:

```ruby
RailsErrorDashboard.configure do |config|
  # Change from true to false
  config.enable_baseline_alerts = false
end
```

### Feature Examples

**Slack Notifications:**
```ruby
config.enable_slack_notifications = true
config.slack_webhook_url = ENV['SLACK_WEBHOOK_URL']
```

**Async Logging (Better Performance):**
```ruby
config.async_logging = true  # jobs run on your app's Active Job adapter; production needs a worker
```

**Error Sampling (High-Traffic Apps):**
```ruby
config.sampling_rate = 0.1  # Log 10% of non-critical errors (critical always logged)
```

**Baseline Anomaly Alerts:**
```ruby
config.enable_baseline_alerts = true
config.baseline_alert_threshold_std_devs = 2.0
```

**Fuzzy Error Matching:**
```ruby
config.enable_similar_errors = true
```

**Platform Comparison:**
```ruby
config.enable_platform_comparison = true
```

See the [Complete Configuration Guide](/rails_error_dashboard/docs/guides/configuration/) for all configuration options.

## Common Tasks

### Resolve an Error

1. Go to `/red`
2. Click on an error
3. Click "Mark as Resolved"
4. Add resolution notes (optional)

### Batch Delete Errors

1. Go to `/red`
2. Select errors using checkboxes
3. Click "Delete"

### Filter Errors

Use the sidebar filters:
- **Platform**: iOS, Android, API (and any platform you report manually)
- **Unresolved**: Show only unresolved errors
- **Search**: Search by error message

## Next Steps

Now that you have the basics working:

1. **Set up notifications**: [Notifications Guide](/rails_error_dashboard/docs/guides/notifications/)
2. **Customize severity**: [Customization Guide](/rails_error_dashboard/docs/guides/customization/)
3. **Enable advanced features**: [Baseline Monitoring](/rails_error_dashboard/docs/features/baseline-monitoring/)
4. **Build integrations**: [Plugin System](/rails_error_dashboard/docs/features/plugin-system/)

## Troubleshooting

### "No errors showing up"

**Check**:
1. Send a test error: `/red/settings` → **Send Test Error**. Errors raised at the console prompt are never captured, so don't test with `raise` there.
2. Check the setup: `bin/rails error_dashboard:verify` checks the configuration, the database connection and RED's tables.
3. Check the middleware is loaded: `bin/rails middleware | grep RailsErrorDashboard` should print `use RailsErrorDashboard::Middleware::ErrorCatcher`.
4. With async logging on (the default), a background job writes each error. In production that needs a worker running your app's job backend.

**Fix** missing tables or migrations:
```bash
# Re-run the installer to copy any missing migrations, then migrate
bin/rails generate rails_error_dashboard:install --no-interactive
bin/rails db:migrate
```

### "Dashboard returns 404"

**Check routes**:
```bash
bin/rails routes | grep RailsErrorDashboard::Engine
```

**Should see**:
```
rails_error_dashboard      /red          RailsErrorDashboard::Engine
```

If not, add the mount to `config/routes.rb`:
```ruby
Rails.application.routes.draw do
  mount RailsErrorDashboard::Engine => "/red"
end
```

Apps first installed before 0.5.8 mount the dashboard at `/error_dashboard`. See [Upgrading](/rails_error_dashboard/docs/upgrading/#old-mount-path-for-apps-installed-before-058).

### "Authentication not working"

**Using HTTP Basic Auth?** Check the values the app actually uses, in a Rails console:
```ruby
RailsErrorDashboard.configuration.dashboard_username
RailsErrorDashboard.configuration.dashboard_password
```
A blank value denies every login, in development too. If the app refuses to boot outside development and test, see [Dashboard Credentials](/rails_error_dashboard/docs/guides/configuration/#dashboard-credentials).

**Using custom auth (Devise/Warden)?** Verify your lambda works:
```ruby
config.authenticate_with = -> { warden.authenticated? }
```
**Common mistake:** Using `current_user` — this will raise `NameError` because Devise helpers aren't available in the engine controller. Use `warden` directly instead.

Check `log/production.log` for `[RailsErrorDashboard] authenticate_with lambda raised` messages — these indicate your lambda is raising an error (which results in 403 denied).

**Restart server** after changing configuration:
```bash
rails server
```

### "Errors not capturing automatically"

The middleware and error subscriber are installed automatically by the engine. Check that they're enabled in your initializer:

```ruby
# config/initializers/rails_error_dashboard.rb
config.enable_middleware = true
config.enable_error_subscriber = true
```

Then run `bin/rails error_dashboard:verify`.

## Performance Tips

### Use Async Logging

Async logging is on by default. RED enqueues each capture on your app's own Active Job adapter (`config.active_job.queue_adapter`), so whatever runs your other jobs runs RED's: Sidekiq, Solid Queue, GoodJob or Rails' in-process `:async`. `config.async_adapter` doesn't choose the backend.

- In production, run a worker for the `default` and `error_notifications` queues. With Solid Queue, see [Solid Queue Setup](/rails_error_dashboard/docs/guides/solid-queue-setup/).
- Rails' in-process `:async` adapter needs no worker, but captures still queued when the process restarts are lost.
- With no worker at all, set `config.async_logging = false` to write each error during the request instead. Notifications still need a worker.

### Limit Backtrace Size

Large backtraces slow down the database:

```ruby
config.max_backtrace_lines = 100  # Default
config.max_backtrace_lines = 50   # Smaller for high-volume apps
```

### Sample Errors

For apps with >1000 errors/day:

```ruby
config.sampling_rate = 0.1  # Log 10% of non-critical errors
```

## Production Checklist

Before deploying to production (each item is explained in [Running in Production](/rails_error_dashboard/docs/production/)):

- [ ] Set `ERROR_DASHBOARD_USER` and `ERROR_DASHBOARD_PASSWORD` (outside development and test, the app won't boot on the defaults)
- [ ] Run a worker for the `default` and `error_notifications` queues. Without one, set `async_logging = false` (notifications still need a worker)
- [ ] Run migrations on every deploy. With a separate database, add its `config/database.yml` entry for production too
- [ ] Set up notifications (Slack, Email, PagerDuty)
- [ ] Configure custom severity rules
- [ ] Set backtrace limit (`max_backtrace_lines`, default: 100)
- [ ] Consider sampling for high-traffic apps
- [ ] Test error notifications (`/red/settings` → **Send Test Error**)
- [ ] Set up database backups
- [ ] Schedule the periodic jobs: `retention_days` (90 in the generated initializer) deletes nothing until `RailsErrorDashboard::RetentionCleanupJob` runs, and baseline alerts need `RailsErrorDashboard::BaselineCalculationJob`. See [Schedule the periodic jobs](/rails_error_dashboard/docs/production/#2-schedule-the-periodic-jobs)

## Getting Help

- **Documentation**: [docs/README.md](/rails_error_dashboard/docs/documentation/)
- **Issues**: [GitHub Issues](https://github.com/AnjanJ/rails_error_dashboard/issues)
- **Configuration**: [Configuration Guide](/rails_error_dashboard/docs/guides/configuration/)

## What's Next?

Explore advanced features:

- **[Baseline Monitoring](/rails_error_dashboard/docs/features/baseline-monitoring/)** - Proactive anomaly detection
- **[Platform Comparison](/rails_error_dashboard/docs/features/platform-comparison/)** - iOS vs Android health
- **[Error Correlation](/rails_error_dashboard/docs/features/error-correlation/)** - Track errors by version
- **[Plugin System](/rails_error_dashboard/docs/features/plugin-system/)** - Build custom integrations

---

**Congratulations!** Your error dashboard is now running. Start catching and resolving errors! 🎉
