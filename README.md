# Rails Error Dashboard

[![Gem Version](https://badge.fury.io/rb/rails_error_dashboard.svg)](https://badge.fury.io/rb/rails_error_dashboard)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Tests](https://github.com/AnjanJ/rails_error_dashboard/workflows/Tests/badge.svg)](https://github.com/AnjanJ/rails_error_dashboard/actions)

## Self-hosted Rails error monitoring — free, forever.

**Own your errors. Own your stack. Zero monthly fees.**

A fully open-source, self-hosted error dashboard for solo founders, indie hackers, and small teams who want complete control without the SaaS bills.

```ruby
gem 'rails_error_dashboard'
```

**5-minute setup** · **Works out-of-the-box** · **100% Rails + Postgres** · **No vendor lock-in**

📖 **[Full Documentation](https://anjanj.github.io/rails_error_dashboard/)** · 🎮 **[Live Demo](https://rails-error-dashboard.anjan.dev)** · 💎 **[RubyGems](https://rubygems.org/gems/rails_error_dashboard)**

### 🎮 Try the Live Demo

**See it in action:** [https://rails-error-dashboard.anjan.dev](https://rails-error-dashboard.anjan.dev)

Username: `gandalf` · Password: `youshallnotpass`

Experience the full dashboard with 480+ realistic Rails errors, LOTR-themed demo data, cause chains, enriched context, auto-reopened errors, and all features enabled.

---

### ⚠️ BETA SOFTWARE
This Rails Engine is in beta and under active development. While functional and tested (1,800+ tests passing, including browser-based system tests), the API may change before v1.0.0. Use in production at your own discretion.

**Supports**: Rails 7.0 - 8.1 | Ruby 3.2 - 4.0

---

## 🎯 Who This Is For

✓ **Solo bootstrappers** who need professional error tracking without recurring costs

✓ **Indie SaaS founders** building profitable apps on tight budgets

✓ **Small dev teams** (2-5 people) who hate SaaS bloat

✓ **Privacy-conscious apps** that need to keep error data on their own servers

✓ **Side projects** that might become real businesses

---

## 💰 What It Replaces

| Before | After |
|--------|-------|
| Pay $29-99/month for error monitoring | $0/month - runs on your existing Rails server |
| Send sensitive error data to third parties | Keep all data on your infrastructure |
| Fight with SaaS pricing tiers and limits | Unlimited errors, unlimited projects |
| Vendor lock-in with proprietary APIs | 100% open source, fully portable |
| Complex setup with SDKs and external services | 5-minute Rails Engine installation |

---

## 🚀 Why Choose Rails Error Dashboard

**"Install once, own it forever"**

- ✅ **Zero recurring costs** - One-time setup, runs on your existing infrastructure
- ✅ **5-minute installation** - Mount the Rails Engine, run migrations, done
- ✅ **Works immediately** - Automatic error capture from Rails controllers, jobs, models
- ✅ **Beautiful UI** - Professional dashboard you can show to clients
- ✅ **Full control** - Your data stays on your server, modify anything you want
- ✅ **No surprises** - Open source MIT license, no hidden fees or limits

**Built for developers who:**
- Want professional error monitoring without the SaaS tax
- Need to debug production issues without paying per error
- Value data privacy and server ownership
- Prefer simple, Rails-native solutions

---

## ✨ Features

### Core Features (Always Enabled)

#### 🎯 Complete Error Tracking
Automatic error capture from Rails controllers, jobs, and middleware. Frontend & mobile support for React, React Native, Vue, Angular, Flutter. Platform detection (iOS/Android/Web/API), user context tracking, full stack traces.

#### 📊 Beautiful Dashboard
Modern Bootstrap 5 UI with dark/light mode, responsive design, real-time statistics, search and filtering, fast pagination. Overview dashboard with critical alerts, error trend charts, and platform health summary.

#### 📈 Analytics & Insights
7-day trend charts, severity breakdown, spike detection, resolution rate tracking, user impact analysis. Comprehensive analytics page with hourly patterns, mobile vs API breakdowns, and top affected users.

#### 🔧 Workflow Management
Error assignment and status tracking, priority levels (critical/high/medium/low), snooze functionality, comment threads, batch operations (bulk resolve/delete), resolution tracking with references.

#### 🔒 Security & Privacy
HTTP Basic Auth, environment-based settings, optional separate database for isolation. Your data stays on your server - no third-party access.

### Optional Features (Choose During Install)

#### 🚨 Multi-Channel Notifications

- **Slack** - Rich formatted messages with error context and direct dashboard links
- **Email** - HTML formatted alerts with full error details
- **Discord** - Embedded messages with severity color coding
- **PagerDuty** - Critical error escalation with incident management
- **Webhooks** - Custom integrations with any service (JSON payloads)

#### ⚡ Performance Optimizations

- **Async Logging** - Non-blocking error capture using ActiveJob (Sidekiq/SolidQueue/Async)
- **Error Sampling** - Reduce storage by sampling high-frequency errors
- **Backtrace Limiting** - Save 70-90% storage with smart truncation
- **Separate Database** - Isolate error data for better performance
- **Database Indexes** - Composite indexes and PostgreSQL GIN full-text search

#### 🧠 Advanced Analytics (7 Powerful Features)

**1. Baseline Anomaly Alerts** 🔔
Automatically detect unusual error rate spikes using statistical analysis (mean + std dev). Get proactive notifications when errors exceed expected baselines with intelligent cooldown to avoid alert fatigue.

**2. Fuzzy Error Matching** 🔍
Find similar errors across different error hashes using Jaccard similarity (70%) and Levenshtein distance (30%). Discover related errors that share common root causes even when they manifest differently.

**3. Co-occurring Errors** 🔗
Detect errors that happen together within configurable time windows (default: 5 minutes). Identify patterns where one error frequently triggers another, helping you prioritize fixes.

**4. Error Cascade Detection** ⛓️
Identify error chains (A causes B causes C) with probability calculations and average delays. Visualize parent→child relationships to understand cascading failures and fix root causes.

**5. Error Correlation Analysis** 📊
Correlate errors with app versions, git commits, and users. Find problematic releases, identify users affected by multiple error types, and detect time-based patterns.

**6. Platform Comparison** 📱
Compare iOS vs Android vs Web health metrics side-by-side. Platform-specific error rates, severity distributions, resolution times, and stability scores (0-100).

**7. Occurrence Pattern Detection** 📈
Detect cyclical patterns (business hours, nighttime, weekend rhythms) and error bursts (many errors in short time). Understand when and how your errors happen.

**Plus: Developer Insights Dashboard** 💡
Built-in analytics dashboard with severity detection, platform stability scoring, actionable recommendations, and recent error activity summaries (always available, no configuration needed).

#### 🔍 Source Code Integration (NEW!)

**View actual source code directly in error backtraces** - no need to switch to your editor or GitHub.

- **Inline Source Code Viewer** - Click "View Source" on any error frame to see the actual code with ±7 lines of context
- **Git Blame Integration** - See who last modified the code, when, and the commit message
- **Repository Links** - Jump directly to GitHub/GitLab/Bitbucket at the exact error line
- **Smart Caching** - Fast performance with 1-hour cache (configurable)
- **Security Controls** - Only shows your app code by default (not gems/frameworks)

**Perfect for debugging:**
- Understand the code context without leaving the dashboard
- Identify code ownership with git blame
- Quick navigation to your repository
- See recent changes that might have caused the error

```ruby
# Enable in config/initializers/rails_error_dashboard.rb
config.enable_source_code_integration = true
config.source_code_context_lines = 7
config.enable_git_blame = true
config.git_repository_url = "https://github.com/user/repo"
```

**📖 [Complete documentation →](docs/SOURCE_CODE_INTEGRATION.md)**

#### 🆕 v0.2 Quick Wins (NEW!)

**11 features that make error tracking smarter, safer, and more actionable:**

- **Exception Cause Chains** — Automatically captures the full `cause` chain (e.g., `SocketError` → `RuntimeError`) so you see root causes, not just wrappers
- **Enriched Context** — Every HTTP error captures `http_method`, `hostname`, `content_type`, and `request_duration_ms` automatically
- **Custom Fingerprint** — Override error grouping with a lambda: group `RecordNotFound` by controller, or any custom logic
- **CurrentAttributes Integration** — Zero-config capture of `Current.user`, `Current.account`, `Current.request_id`
- **Environment Info** — Ruby version, Rails version, gem versions, server, and database adapter captured at error time
- **Sensitive Data Filtering** — Passwords, tokens, secrets, and API keys auto-filtered from error context before storage
- **Auto-Reopen** — Resolved errors automatically reopen when they recur, with a "Reopened" badge in the UI
- **Notification Throttling** — Severity filters, per-error cooldown, and milestone threshold alerts prevent alert fatigue
- **BRIN Indexes** — PostgreSQL BRIN index on `occurred_at` for dramatically faster time-range queries (72KB vs 676MB)
- **Structured Backtrace** — Uses `backtrace_locations` for richer backtrace data with proper path/line/method fields
- **Reduced Dependencies** — Core gem now requires only `rails` + `pagy`; `browser`, `chartkick`, `httparty`, `turbo-rails` are optional

#### 🔌 Plugin System
Extensible architecture with event hooks (`on_error_logged`, `on_error_resolved`, `on_threshold_exceeded`). Built-in examples for Jira integration, metrics tracking, audit logging. Easy to create custom plugins - just drop a file in `config/initializers/error_dashboard_plugins/`.

**📚 [View complete feature list with examples →](docs/FEATURES.md)**

---

## 📦 Quick Start

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

The installer will guide you through optional feature selection:
- **Notifications** (Slack, Email, Discord, PagerDuty, Webhooks)
- **Performance** (Async Logging, Error Sampling, Separate Database)
- **Advanced Analytics** (7 powerful features including baseline alerts, fuzzy matching, platform comparison)

**All features are opt-in** - choose what you need during installation, or enable/disable them later in the initializer.

This will:
- Create `config/initializers/rails_error_dashboard.rb` with your selected features
- Copy database migrations
- Mount the engine at `/error_dashboard`

### 3. Visit your dashboard

Start your server and visit:
```
http://localhost:3000/error_dashboard
```

**Default credentials:**
- Username: `gandalf`
- Password: `youshallnotpass`

⚠️ **Change these before production!** Edit `config/initializers/rails_error_dashboard.rb`

### 4. Test it out

Trigger a test error to see it in action:

```ruby
# In Rails console or any controller
raise "Test error from Rails Error Dashboard!"
```

The error will appear instantly in your dashboard with full context, backtrace, and platform information.

**📘 [Full installation guide →](docs/QUICKSTART.md)**

---

## 🗑️ Uninstalling

Need to remove Rails Error Dashboard? We've made it simple with both automated and manual options:

```bash
# Automated uninstall (recommended)
rails generate rails_error_dashboard:uninstall

# Keep error data, remove code
rails generate rails_error_dashboard:uninstall --keep-data

# Show manual instructions only
rails generate rails_error_dashboard:uninstall --manual-only
```

The uninstaller will:
- ✅ Show exactly what will be removed
- ✅ Ask for confirmation before making changes
- ✅ Remove initializer, routes, and migrations
- ✅ Optionally drop database tables (with double confirmation)
- ✅ Provide clear next steps

**📘 [Complete uninstall guide →](docs/UNINSTALL.md)**

---

## ⚙️ Configuration

### Opt-in Feature System

Rails Error Dashboard uses an **opt-in architecture** - core features (error capture, dashboard UI, analytics) are always enabled, while everything else is disabled by default.

**Tier 1 Features (Always ON)**:
- ✅ Error capture (controllers, jobs, middleware)
- ✅ Dashboard UI with search and filtering
- ✅ Real-time updates
- ✅ Analytics and trend charts

**Optional Features (Choose During Install)**:
- 📧 Multi-channel notifications (Slack, Email, Discord, PagerDuty, Webhooks)
- ⚡ Performance optimizations (Async logging, Error sampling)
- 📊 Advanced analytics (Baseline alerts, Fuzzy matching, Platform comparison, and more)

### Basic Configuration

Edit `config/initializers/rails_error_dashboard.rb`:

```ruby
RailsErrorDashboard.configure do |config|
  # ============================================================================
  # AUTHENTICATION (Always Required)
  # ============================================================================
  config.dashboard_username = ENV.fetch('ERROR_DASHBOARD_USER', 'gandalf')
  config.dashboard_password = ENV.fetch('ERROR_DASHBOARD_PASSWORD', 'youshallnotpass')

  # ============================================================================
  # OPTIONAL FEATURES (Enable as needed)
  # ============================================================================

  # Slack notifications (if enabled during install)
  config.enable_slack_notifications = true
  config.slack_webhook_url = ENV['SLACK_WEBHOOK_URL']

  # Email notifications (if enabled during install)
  config.enable_email_notifications = true
  config.notification_email_recipients = ["dev@yourapp.com"]
  config.notification_email_from = "errors@yourapp.com"

  # Async logging for better performance (if enabled during install)
  config.async_logging = true
  config.async_adapter = :sidekiq  # or :solid_queue, :async

  # Advanced analytics features (if enabled during install)
  config.enable_baseline_alerts = true
  config.enable_similar_errors = true
  config.enable_platform_comparison = true
end
```

All features can be toggled on/off at any time by editing the initializer.

### Environment Variables

```bash
# .env
ERROR_DASHBOARD_USER=your_username
ERROR_DASHBOARD_PASSWORD=your_secure_password
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
DASHBOARD_BASE_URL=https://yourapp.com
```

**📖 [Complete configuration guide →](docs/guides/CONFIGURATION.md)**

---

## 🏢 Multi-App Support

**Rails Error Dashboard supports logging errors from multiple Rails applications to a single shared database.**

This is ideal for:
- Managing errors across microservices
- Monitoring production, staging, and development environments separately
- Tracking different apps from a central dashboard
- Organizations running multiple Rails applications

### Automatic Configuration

By default, the dashboard automatically detects your application name from `Rails.application.class.module_parent_name`:

```ruby
# BlogApp::Application → "BlogApp"
# AdminPanel::Application → "AdminPanel"
# ApiService::Application → "ApiService"
```

**No configuration needed!** Each app will automatically register itself when logging its first error.

### Manual Override

Override the auto-detected name if desired:

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  config.application_name = "MyCustomAppName"
end
```

Or use an environment variable:

```bash
# .env
APPLICATION_NAME="Production API"
```

This allows you to use different names for different environments:
```bash
# Production
APPLICATION_NAME="MyApp-Production"

# Staging
APPLICATION_NAME="MyApp-Staging"

# Development
APPLICATION_NAME="MyApp-Development"
```

### Shared Database Setup

All apps must use the same error dashboard database. Configure your `database.yml`:

```yaml
# config/database.yml
production:
  primary:
    database: my_app_production
    # ... other connection settings

  error_dashboard:
    database: shared_error_dashboard_production
    host: error-db.example.com
    # ... other connection settings
```

Then in your initializer:

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  config.database = :error_dashboard  # Use the shared database
end
```

### Dashboard UI Features

**Navbar Application Switcher:**
- Quick dropdown to switch between applications
- Shows "All Apps" by default
- Only appears when multiple apps are registered

**Filter Form:**
- Filter errors by specific application
- Combine with other filters (error type, platform, etc.)
- Active filter pills show current selection

**Application Column:**
- Displays application name for each error
- Only shown when viewing "All Apps"
- Hidden when filtered to a single app

### Per-App Error Tracking

Errors are tracked independently per application:

```ruby
# Same error in different apps creates separate records
# App A: StandardError "Database timeout" → Error #1
# App B: StandardError "Database timeout" → Error #2

# Each has its own:
# - Occurrence counts
# - Resolution status
# - Comments and history
# - Analytics and trends
```

### API Usage

When logging errors via API, specify the application:

```ruby
RailsErrorDashboard::Commands::LogError.call(
  error_type: "TypeError",
  message: "Cannot read property 'name' of null",
  platform: "iOS",
  # ... other parameters
)
# Uses config.application_name automatically
```

Or override per-error (advanced):

```ruby
# Create application first
app = RailsErrorDashboard::Application.find_or_create_by!(name: "Mobile App")

# Then create error
RailsErrorDashboard::ErrorLog.create!(
  application: app,
  error_type: "NetworkError",
  message: "Request failed",
  # ... other fields
)
```

### Performance & Concurrency

Multi-app support is designed for high-concurrency scenarios:

✅ **Row-level locking** - No table locks, apps write independently
✅ **Cached lookups** - Application names cached for 1 hour
✅ **Composite indexes** - Fast filtering on `[application_id, occurred_at]`
✅ **Per-app deduplication** - Same error in different apps tracked separately
✅ **No deadlocks** - Scoped locking prevents cross-app conflicts

**Benchmark**: Tested with 5 apps writing 1000 errors/sec with zero deadlocks.

### Rake Tasks

Manage applications via rake tasks:

```bash
# List all registered applications
rails error_dashboard:list_applications

# Backfill application for existing errors
rails error_dashboard:backfill_application APP_NAME="Legacy App"
```

### Migration Guide

If you have existing errors before enabling multi-app support:

1. Run migrations: `rails db:migrate`
2. Backfill existing errors:
   ```bash
   rails error_dashboard:backfill_application APP_NAME="My App"
   ```
3. All existing errors will be assigned to "My App"
4. New applications will auto-register on first error

**Zero downtime** - Errors can continue logging during migration.

---

## 🚀 Usage

### Automatic Error Tracking

Rails Error Dashboard automatically tracks errors from:
- **Controllers** (via Rails error reporting)
- **Background jobs** (ActiveJob, Sidekiq)
- **Rack middleware** (catches everything else)

No additional code needed! Just install and it works.

### Manual Error Logging

For frontend/mobile apps or custom error logging:

```ruby
# From your Rails API
RailsErrorDashboard::Commands::LogError.call(
  error_type: "TypeError",
  message: "Cannot read property 'name' of null",
  backtrace: ["App.js:42", "index.js:12"],
  platform: "iOS",
  app_version: "2.1.0",
  user_id: current_user.id,
  context: {
    component: "ProfileScreen",
    device_model: "iPhone 14 Pro"
  }
)
```

### Frontend Integration

```javascript
// React Native example
try {
  // Your code
} catch (error) {
  fetch('https://yourapp.com/api/errors', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      error_type: error.name,
      message: error.message,
      backtrace: error.stack.split('\n'),
      platform: Platform.OS, // 'ios' or 'android'
      app_version: VERSION
    })
  });
}
```

**📱 [Mobile app integration guide →](docs/guides/MOBILE_APP_INTEGRATION.md)**

---

## 🔔 Notifications

Set up multi-channel notifications in minutes:

### Slack
```ruby
config.enable_slack_notifications = true
config.slack_webhook_url = ENV['SLACK_WEBHOOK_URL']
```

### Discord
```ruby
config.enable_discord_notifications = true
config.discord_webhook_url = ENV['DISCORD_WEBHOOK_URL']
```

### PagerDuty (Critical Errors Only)
```ruby
config.enable_pagerduty_notifications = true
config.pagerduty_integration_key = ENV['PAGERDUTY_INTEGRATION_KEY']
```

### Custom Webhooks
```ruby
config.enable_webhook_notifications = true
config.webhook_urls = ['https://yourapp.com/hooks/errors']
```

**🔕 [Notification setup guide →](docs/guides/NOTIFICATIONS.md)**

---

## 📚 Documentation

### Getting Started
- **[Quickstart Guide](docs/QUICKSTART.md)** - Complete 5-minute setup
- **[Configuration](docs/guides/CONFIGURATION.md)** - All configuration options
- **[Mobile App Integration](docs/guides/MOBILE_APP_INTEGRATION.md)** - React Native, Flutter, etc.

### Features
- **[Complete Feature List](docs/FEATURES.md)** - Every feature explained
- **[Notifications](docs/guides/NOTIFICATIONS.md)** - Multi-channel alerting
- **[Batch Operations](docs/guides/BATCH_OPERATIONS.md)** - Bulk resolve/delete
- **[Real-Time Updates](docs/guides/REAL_TIME_UPDATES.md)** - Live dashboard
- **[Error Trend Visualizations](docs/guides/ERROR_TREND_VISUALIZATIONS.md)** - Charts & analytics

### Advanced
- **[Multi-App Support](docs/MULTI_APP_PERFORMANCE.md)** - Track multiple applications
- **[Plugin System](docs/PLUGIN_SYSTEM.md)** - Build custom integrations
- **[API Reference](docs/API_REFERENCE.md)** - Complete API documentation
- **[Customization Guide](docs/CUSTOMIZATION.md)** - Customize everything
- **[Database Options](docs/guides/DATABASE_OPTIONS.md)** - Separate database setup
- **[Database Optimization](docs/guides/DATABASE_OPTIMIZATION.md)** - Performance tuning

### Development
- **[Testing](docs/development/TESTING.md)** - Multi-version testing
- **[Smoke Tests](SMOKE_TESTS.md)** - Deployment verification tests

**📖 [View all documentation →](docs/README.md)**

---

## 🏗️ Architecture

Built with **Service Objects + CQRS Principles**:
- **Commands**: LogError, ResolveError, BatchOperations (write operations)
- **Queries**: ErrorsList, DashboardStats, Analytics (read operations)
- **Value Objects**: ErrorContext (immutable data)
- **Services**: PlatformDetector, SimilarityCalculator (business logic)
- **Plugins**: Event-driven extensibility

Clean, maintainable, testable architecture you can understand and modify.

---

## 🧪 Testing

1,800+ tests covering unit, integration, and browser-based system tests.

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run unit/integration tests only (fast)
bundle exec rspec --exclude-pattern "spec/system/**/*"

# Run system tests only (requires Chrome)
bundle exec rspec spec/system/

# Run with visible browser for debugging
HEADLESS=false bundle exec rspec spec/system/

# Run with Chrome DevTools inspector
INSPECTOR=true HEADLESS=false bundle exec rspec spec/system/

# Run with coverage report
COVERAGE=true bundle exec rspec
```

### System Tests (Browser-Based)

System tests use **Capybara + Cuprite** (Chrome DevTools Protocol) to simulate real user interactions — opening modals, filling forms, clicking buttons, and verifying page content. No Selenium or chromedriver management needed.

**Requirements:** Chrome or Chromium installed locally.

```bash
# Verify Chrome is available
which google-chrome || which chromium-browser || which chromium

# macOS: Chrome is typically at /Applications/Google Chrome.app
```

---

## 🤝 Contributing

We welcome contributions! Here's how to get started:

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`bundle exec rspec`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### Development Setup

```bash
git clone https://github.com/AnjanJ/rails_error_dashboard.git
cd rails_error_dashboard

# Automated setup (installs deps, hooks, runs tests)
bin/setup

# Or manual setup
bundle install
bundle exec lefthook install  # Installs git hooks
bundle exec rspec
```

**Git Hooks:** We use [Lefthook](https://github.com/evilmartians/lefthook) to run quality checks before commit/push. This ensures CI passes and saves GitHub Actions minutes!

**🔧 [Development guide →](DEVELOPMENT.md)** | **🧪 [Testing guide →](docs/development/TESTING.md)**

---

## 📝 License

Rails Error Dashboard is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

---

## 🙏 Acknowledgments

- Built with [Rails](https://rubyonrails.org/)
- UI powered by [Bootstrap 5](https://getbootstrap.com/)
- Charts by [Chart.js](https://www.chartjs.org/)
- Pagination by [Pagy](https://github.com/ddnexus/pagy)
- Platform detection by [Browser gem](https://github.com/fnando/browser)

---

## ❓ Frequently Asked Questions

<details>
<summary><strong>Is this production-ready?</strong></summary>

This is currently in **beta** but actively tested with 1,800+ passing tests across Rails 7.0-8.1 and Ruby 3.2-4.0. Many users are running it in production. See [production requirements](docs/FEATURES.md#production-readiness).
</details>

<details>
<summary><strong>How does this compare to Sentry/Rollbar/Honeybadger?</strong></summary>

**Similar**: Error tracking, grouping, notifications, dashboards
**Better**: 100% free, self-hosted (your data stays with you), no usage limits, Rails-optimized
**Trade-offs**: You manage hosting/backups, fewer integrations than commercial services

See [full comparison](docs/features/PLATFORM_COMPARISON.md).
</details>

<details>
<summary><strong>What's the performance impact?</strong></summary>

Minimal with async logging enabled:
- **Synchronous**: ~10-50ms per error (blocks request)
- **Async (recommended)**: ~1-2ms (queues to background job)
- **Sampling**: Log only 10% of non-critical errors for high-traffic apps

See [Performance Guide](docs/guides/ERROR_SAMPLING_AND_FILTERING.md).
</details>

<details>
<summary><strong>Can I use a separate database?</strong></summary>

Yes! Configure in your initializer:

```ruby
RailsErrorDashboard.configure do |config|
  config.database = :errors  # Use separate database
end
```

See [Database Options Guide](docs/guides/DATABASE_OPTIONS.md).
</details>

<details>
<summary><strong>How do I migrate from Sentry/Rollbar?</strong></summary>

1. Install Rails Error Dashboard
2. Run both systems in parallel (1-2 weeks)
3. Verify all errors are captured
4. Remove old error tracking gem
5. Update team documentation

Historical data cannot be imported (different formats).
</details>

<details>
<summary><strong>Does it work with API-only Rails apps?</strong></summary>

Yes! The error logging works in API-only mode. The dashboard UI requires a browser but can be:
- Mounted in a separate admin app
- Run in a separate Rails instance pointing to the same database
- Accessed via SSH tunnel

See [API-only setup](docs/guides/MOBILE_APP_INTEGRATION.md#backend-setup-rails-api).
</details>

<details>
<summary><strong>How do I track multiple Rails apps?</strong></summary>

Automatic! Just set `APP_NAME` environment variable:

```bash
# App 1
APP_NAME=my-api rails server

# App 2
APP_NAME=my-admin rails server
```

All apps share the same dashboard. See [Multi-App Guide](docs/MULTI_APP_PERFORMANCE.md).
</details>

<details>
<summary><strong>Can I customize error severity levels?</strong></summary>

Yes! Configure custom rules in your initializer:

```ruby
RailsErrorDashboard.configure do |config|
  config.custom_severity_rules = {
    /ActiveRecord::RecordNotFound/ => :low,
    /Stripe::/ => :critical
  }
end
```

See [Customization Guide](docs/CUSTOMIZATION.md).
</details>

<details>
<summary><strong>How long are errors stored?</strong></summary>

Forever by default (no automatic deletion). Manual cleanup with rake task:

```bash
# Delete resolved errors older than 90 days
rails error_dashboard:cleanup_resolved DAYS=90

# Filter by application name
rails error_dashboard:cleanup_resolved DAYS=30 APP_NAME="My App"
```

Or schedule with cron/whenever. See [Database Optimization](docs/guides/DATABASE_OPTIMIZATION.md).
</details>

<details>
<summary><strong>Can I get Slack/Discord notifications?</strong></summary>

Yes! Enable during installation or configure manually:

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_slack_notifications = true
  config.slack_webhook_url = ENV['SLACK_WEBHOOK_URL']
end
```

Supports Slack, Discord, Email, PagerDuty, and custom webhooks. See [Notifications Guide](docs/guides/NOTIFICATIONS.md).
</details>

<details>
<summary><strong>Does it work with Turbo/Hotwire?</strong></summary>

Yes! Includes Turbo Streams support for real-time updates. Errors appear in the dashboard instantly without page refresh.
</details>

<details>
<summary><strong>How do I report errors from mobile apps (React Native/Flutter)?</strong></summary>

Make HTTP POST requests to your Rails API:

```javascript
// React Native example
fetch('https://api.example.com/error_dashboard/api/v1/errors', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Basic ' + btoa('admin:password')
  },
  body: JSON.stringify({
    error_class: 'TypeError',
    message: 'Cannot read property...',
    platform: 'iOS'
  })
});
```

See [Mobile App Integration](docs/guides/MOBILE_APP_INTEGRATION.md).
</details>

<details>
<summary><strong>Can I build custom integrations?</strong></summary>

Yes! Use the plugin system:

```ruby
class MyCustomPlugin < RailsErrorDashboard::Plugin
  def on_error_logged(error_log)
    # Your custom logic
  end
end

RailsErrorDashboard::PluginRegistry.register(MyCustomPlugin.new)
```

See [Plugin System Guide](docs/PLUGIN_SYSTEM.md).
</details>

<details>
<summary><strong>What if I need help?</strong></summary>

- **📖 Read the docs**: [docs/README.md](docs/README.md)
- **🐛 Report bugs**: [GitHub Issues](https://github.com/AnjanJ/rails_error_dashboard/issues)
- **💡 Ask questions**: [GitHub Discussions](https://github.com/AnjanJ/rails_error_dashboard/discussions)
- **🔒 Security issues**: See [SECURITY.md](SECURITY.md)
</details>

---

## 💬 Support

- **📖 Documentation**: [docs/](docs/README.md)
- **🐛 Issues**: [GitHub Issues](https://github.com/AnjanJ/rails_error_dashboard/issues)
- **💡 Discussions**: [GitHub Discussions](https://github.com/AnjanJ/rails_error_dashboard/discussions)

---

## 🙏 Contributors

Thank you to everyone who has contributed to Rails Error Dashboard!

[![Contributors](https://contrib.rocks/image?repo=AnjanJ/rails_error_dashboard)](https://github.com/AnjanJ/rails_error_dashboard/graphs/contributors)

Special thanks to:
- [@bonniesimon](https://github.com/bonniesimon) - Turbo helpers production fix
- [@gundestrup](https://github.com/gundestrup) - Security fixes, dependency updates, CI/CD improvements
- [@midwire](https://github.com/midwire) - Backtrace line numbers, loading states & skeleton screens

See [CONTRIBUTORS.md](CONTRIBUTORS.md) for the complete list of contributors and their contributions.

Want to contribute? Check out our [Contributing Guide](CONTRIBUTING.md)!

---

**Made with ❤️ by [Anjan](https://www.anjan.dev) for the Rails community**

*One Gem to rule them all, One Gem to find them, One Gem to bring them all, and in the dashboard bind them.* 🧙‍♂️
