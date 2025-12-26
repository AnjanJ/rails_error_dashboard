# Quickstart Guide

Get Rails Error Dashboard up and running in 5 minutes!

## Prerequisites

- Rails 7.0 or later (supports 7.0, 7.1, 7.2, 8.0, 8.1)
- Ruby 3.2 or later (supports 3.2, 3.3, 3.4)
- SQLite, PostgreSQL, or MySQL database

## Installation

### 1. Add to Gemfile

```ruby
gem 'rails_error_dashboard'
```

### 2. Install with Interactive Setup

```bash
bundle install
rails generate rails_error_dashboard:install
rails db:migrate
```

### Interactive Feature Selection

The installer will guide you through **15 optional features** organized in 3 categories:

**📧 Notifications (5 features)**
- Slack - Real-time error notifications to Slack channels
- Email - Send error alerts via email
- Discord - Push errors to Discord channels
- PagerDuty - Critical error escalation for on-call teams
- Webhooks - Send errors to custom endpoints

**⚡ Performance & Scalability (3 features)**
- Async Logging - Non-blocking error capture via background jobs
- Error Sampling - Reduce volume by sampling non-critical errors
- Separate Database - Isolate error data in dedicated database

**📊 Advanced Analytics (7 features)**
- Baseline Anomaly Alerts - Detect unusual error patterns automatically
- Fuzzy Error Matching - Find similar errors across different hashes
- Co-occurring Errors - Identify errors that happen together
- Error Cascades - Track parent→child error relationships
- Error Correlation - Correlate errors with versions and users
- Platform Comparison - Compare iOS vs Android vs Web health
- Occurrence Patterns - Detect cyclical patterns and error bursts

**All features are opt-in** - you can say "no" to everything and just use the core dashboard, or enable specific features you need.

### Example Installation Flow

```bash
$ rails generate rails_error_dashboard:install

╔════════════════════════════════════════════════════════════════════╗
║        Rails Error Dashboard - Interactive Installation            ║
╚════════════════════════════════════════════════════════════════════╝

This installer will help you configure optional features.
Core features (error capture, dashboard UI, analytics) are always enabled.

Choose the features you want to enable:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📧  NOTIFICATIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[1/15] Slack Notifications
    Send real-time error notifications to Slack channels
    Enable? (y/N): y

[2/15] Email Notifications
    Send error alerts via email to your team
    Enable? (y/N): n

...

✓ Installation complete!

Enabled features:
  ✓ Slack Notifications
  ✓ Async Logging
  ✓ Baseline Anomaly Alerts

Next steps:
  1. Edit config/initializers/rails_error_dashboard.rb
  2. Set environment variables (if needed)
  3. Run: rails db:migrate
  4. Visit: http://localhost:3000/error_dashboard
```

That's it! The dashboard is now available at `/error_dashboard` in your Rails app.

## First Steps

### Access the Dashboard

Visit `http://localhost:3000/error_dashboard` to see the error dashboard.

Initially, you won't see any errors. Let's create one to test:

```ruby
# In rails console
raise "Test error from console"
```

Or create a controller error:

```ruby
# app/controllers/home_controller.rb
class HomeController < ApplicationController
  def index
    raise "Test error from controller"
  end
end
```

Visit the route and check `/errors` - you should see your test error!

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

  # Async Logging - ENABLED (if you selected it during install)
  config.async_logging = true
  config.async_adapter = :sidekiq  # Options: :sidekiq, :solid_queue, :async

  # Slack Notifications - ENABLED (if you selected it during install)
  config.enable_slack_notifications = true
  config.slack_webhook_url = ENV["SLACK_WEBHOOK_URL"]

  # Baseline Anomaly Alerts - ENABLED (if you selected it during install)
  config.enable_baseline_alerts = true
  config.baseline_alert_threshold_std_devs = 2.0

  # ... other features based on your selections
end
```

**Important**: Change the default username and password before deploying to production!

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
config.async_logging = true
config.async_adapter = :sidekiq  # or :solid_queue, :async
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

See the [Complete Configuration Guide](guides/CONFIGURATION.md) for all 16+ configuration options.

## Common Tasks

### Resolve an Error

1. Go to `/errors`
2. Click on an error
3. Click "Mark as Resolved"
4. Add a resolution comment (optional)

### Batch Delete Errors

1. Go to `/errors`
2. Select errors using checkboxes
3. Click "Bulk Actions" → "Delete Selected"

### Filter Errors

Use the sidebar filters:
- **Platform**: iOS, Android, API, Web
- **Unresolved**: Show only unresolved errors
- **Search**: Search by error message

## Next Steps

Now that you have the basics working:

1. **Set up notifications**: [Notifications Guide](guides/NOTIFICATIONS.md)
2. **Customize severity**: [Customization Guide](CUSTOMIZATION.md)
3. **Enable advanced features**: [Baseline Monitoring](features/BASELINE_MONITORING.md)
4. **Build integrations**: [Plugin System](PLUGIN_SYSTEM.md)

## Troubleshooting

### "No errors showing up"

**Check**:
1. Errors are being logged: `rails console` → `raise "test"`
2. Database migration ran: `rails db:migrate:status | grep error_dashboard`
3. Middleware is active: Check `config/application.rb`

**Fix**:
```bash
# Re-run migrations
rails rails_error_dashboard:install:migrations
rails db:migrate
```

### "Dashboard returns 404"

**Check routes**:
```bash
rails routes | grep error
```

**Should see**:
```
Rails.application.routes.draw do
  mount RailsErrorDashboard::Engine => "/error_dashboard"
end
```

### "Authentication not working"

**Verify credentials** in `config/initializers/rails_error_dashboard.rb`:
```ruby
config.dashboard_username = "admin"
config.dashboard_password = "your_password"
```

**Restart server** after changing configuration:
```bash
rails server
```

### "Errors not capturing automatically"

**Check middleware is installed**:

```ruby
# config/application.rb
config.middleware.use RailsErrorDashboard::Middleware::ErrorCatcher
```

**Or install manually**:
```bash
rails generate rails_error_dashboard:install
```

## Performance Tips

### Use Async Logging

For production apps, enable async logging:

```ruby
config.async_logging = true
config.async_adapter = :sidekiq
```

**With Sidekiq**:
```ruby
# Gemfile
gem 'sidekiq'

# config/initializers/rails_error_dashboard.rb
config.async_adapter = :sidekiq
```

**With SolidQueue**:
```ruby
# Gemfile
gem 'solid_queue'

# config/initializers/rails_error_dashboard.rb
config.async_adapter = :solid_queue
```

### Limit Backtrace Size

Large backtraces slow down the database:

```ruby
config.max_backtrace_lines = 50  # Default, good for most cases
config.max_backtrace_lines = 20  # Smaller for high-volume apps
```

### Sample Errors

For apps with >1000 errors/day:

```ruby
config.sampling_rate = 0.1  # Log 10% of errors
```

## Production Checklist

Before deploying to production:

- [ ] Change default username and password
- [ ] Enable async logging (`async_logging = true`)
- [ ] Set up notifications (Slack, Email, PagerDuty)
- [ ] Configure custom severity rules
- [ ] Set backtrace limit (`max_backtrace_lines`)
- [ ] Consider sampling for high-traffic apps
- [ ] Test error notifications
- [ ] Set up database backups
- [ ] Configure data retention (delete old errors)

## Getting Help

- **Documentation**: [docs/README.md](README.md)
- **Issues**: [GitHub Issues](https://github.com/AnjanJ/rails_error_dashboard/issues)
- **Configuration**: [Configuration Guide](guides/CONFIGURATION.md)

## What's Next?

Explore advanced features:

- **[Baseline Monitoring](features/BASELINE_MONITORING.md)** - Proactive anomaly detection
- **[Platform Comparison](features/PLATFORM_COMPARISON.md)** - iOS vs Android health
- **[Error Correlation](features/ERROR_CORRELATION.md)** - Track errors by version
- **[Plugin System](PLUGIN_SYSTEM.md)** - Build custom integrations

---

**Congratulations!** Your error dashboard is now running. Start catching and resolving errors! 🎉
