---
layout: default
title: "Customization Guide"
order: 13
---

# Customization Guide

Learn how to customize Rails Error Dashboard to fit your application's specific needs.

## Table of Contents

- [Custom Severity Rules](#custom-severity-rules)
- [Custom Error Context](#custom-error-context)
- [Sampling and Filtering](#sampling-and-filtering)
- [Custom Notifications](#custom-notifications)
- [UI Customization](#ui-customization)
- [Database Customization](#database-customization)

## Custom Severity Rules

Override the default severity classification for specific error types.

### Basic Usage

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  config.custom_severity_rules = {
    'PaymentError' => :critical,
    'SecurityError' => :critical,
    'DataLossError' => :critical,
    'ThirdPartyAPIError' => :high,
    'CacheError' => :medium,
    'ValidationError' => :low,
    'DeprecationWarning' => :low
  }
end
```

### Available Severity Levels

- `:critical` - Immediate action required (payment failures, security issues)
- `:high` - Should be fixed soon (data integrity, important features)
- `:medium` - Should be fixed eventually (non-critical features)
- `:low` - Nice to fix (deprecations, minor issues)

### Matching

Keys are matched against the full class name, exactly. There are no wildcards, and a rule does not apply to subclasses.

```ruby
config.custom_severity_rules = {
  # Built-in and third-party classes
  'ActiveRecord::RecordNotFound' => :low,
  'Stripe::CardError' => :high,

  # Your own classes
  'MyApp::PaymentProcessingError' => :critical,
  'MyApp::EmailDeliveryError' => :medium
}
```

There is no hook for computing severity from the message or backtrace. Use a rule per class.

## Custom Error Context

Attach your own data to an error.

### Metadata

Errors you report yourself with `ManualErrorReporter.report` can carry a `metadata` hash:

```ruby
RailsErrorDashboard::ManualErrorReporter.report(
  error_type: "PaymentError",
  message: "Card declined",
  platform: "Web",
  user_id: current_user.id,
  metadata: { cart_id: @cart.id, plan: current_user.plan }
)
```

There is no setting that adds fields to errors RED captures on its own. To add a trail of events to those, use breadcrumbs.

### Custom Breadcrumbs

Add manual breadcrumbs at key points in your application to capture domain-specific context:

```ruby
# In a controller
def checkout
  RailsErrorDashboard.add_breadcrumb("checkout started", { cart_id: @cart.id, items: @cart.items.count })

  process_payment(@cart)

  RailsErrorDashboard.add_breadcrumb("payment processed", { provider: "stripe", amount: @cart.total })
rescue => e
  # Breadcrumbs captured automatically — shows the trail leading to the error
  raise
end
```

Custom breadcrumbs appear alongside automatically-captured events (SQL, controller, cache) in the error detail page. Requires `config.enable_breadcrumbs = true`.

## Sampling and Filtering

Control which errors are logged to reduce noise and storage.

### Sampling Rate

Log only a percentage of errors (useful for high-traffic apps):

```ruby
RailsErrorDashboard.configure do |config|
  # Log 10% of errors
  config.sampling_rate = 0.1

  # Log 50% of errors
  config.sampling_rate = 0.5

  # Log all errors (default)
  config.sampling_rate = 1.0
end
```

### Ignore Specific Exceptions

Completely ignore certain error types:

```ruby
config.ignored_exceptions = [
  'ActionController::RoutingError',
  'ActiveRecord::RecordNotFound',
  'ActionController::InvalidAuthenticityToken'
]
```

### Custom Grouping

To change how errors are grouped, set `config.custom_fingerprint`. See [Custom Grouping](/rails_error_dashboard/docs/guides/configuration/#custom-grouping) in the Configuration Guide.

## Custom Notifications

### Notification Callbacks

Register Ruby blocks that run when an error is logged. Call these in an initializer, outside the `configure` block:

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.on_error_logged do |error_log|
  CustomNotifier.alert(
    message: "Error: #{error_log.error_type}",
    error_id: error_log.id
  )
end

RailsErrorDashboard.on_critical_error do |error_log|
  PagerDuty.trigger(error_log)
end

RailsErrorDashboard.on_error_resolved do |error_log|
  CustomNotifier.alert(message: "Resolved: #{error_log.error_type}")
end
```

`on_error_logged` runs when an error is first logged, and when a resolved error reopens. `on_critical_error` runs only for critical errors. Each block receives the `ErrorLog` record. See the [Configuration Guide](/rails_error_dashboard/docs/guides/configuration/#notification-callbacks) for details.

### Conditional Notifications

Filter inside the block:

```ruby
RailsErrorDashboard.on_error_logged do |error_log|
  # Only notify for payment errors
  PaymentTeam.notify(error_log) if error_log.error_type.include?('Payment')

  # Only notify during business hours
  SlackNotifier.send(error_log) if Time.current.hour.between?(9, 17)
end
```

### Built-in Channels

Slack, Discord, email, PagerDuty, Telegram and generic webhooks are built in. Turn them on with their `enable_*_notifications` settings. See the [Configuration Guide](/rails_error_dashboard/docs/guides/configuration/). The message format is not customizable. For a different format, send your own message from a callback.

## UI Customization

### Custom Styles

The dashboard layout carries its own inline CSS and does not use your app's asset pipeline, so a stylesheet added through `config.assets.precompile` is not loaded. The accent color can be changed with `config.accent_color` (`:crimson`, `:ruby`, `:ember` or `:violet`).

### Custom Views

Override dashboard views by creating files in your app:

```text
app/
└── views/
    └── rails_error_dashboard/
        └── errors/
            ├── index.html.erb    # Override error list
            ├── show.html.erb     # Override error detail
            └── _error_card.html.erb  # Override error card partial
```

Example custom index:

```erb
<!-- app/views/rails_error_dashboard/errors/index.html.erb -->
<h1>My Custom Error Dashboard</h1>

<% @errors.each do |error| %>
  <div class="custom-error-card">
    <%= link_to error.error_type, error_path(error) %>
    <span class="badge"><%= error.platform %></span>
  </div>
<% end %>
```

### Custom Helper Methods

Add your own helpers:

```ruby
# app/helpers/rails_error_dashboard/application_helper.rb
module RailsErrorDashboard
  module ApplicationHelper
    def custom_error_badge(error)
      color = error.critical? ? 'red' : 'yellow'
      content_tag(:span, error.severity, class: "badge-#{color}")
    end

    def formatted_backtrace(error)
      error.backtrace.first(5).join("\n")
    end
  end
end
```

## Database Customization

### Use Separate Database

For large applications, use a separate database for error logs:

```ruby
# config/database.yml
production:
  primary:
    <<: *default
    database: my_app_production

  error_logs:
    <<: *default
    database: my_app_errors_production
    migrations_paths: db/error_logs_migrate
```

Enable in configuration:

```ruby
RailsErrorDashboard.configure do |config|
  config.use_separate_database = true
end
```

See [Database Options Guide](/rails_error_dashboard/docs/guides/database-options/) for details.

### Custom Retention Policy

Automatically delete old errors:

```ruby
# lib/tasks/error_cleanup.rake
namespace :errors do
  desc 'Delete errors older than 90 days'
  task cleanup: :environment do
    cutoff = 90.days.ago
    RailsErrorDashboard::ErrorLog.where('occurred_at < ?', cutoff).delete_all
    puts "Deleted errors older than #{cutoff}"
  end
end
```

Schedule with cron:

```ruby
# config/schedule.rb (with whenever gem)
every 1.day, at: '3:00 am' do
  rake 'errors:cleanup'
end
```

### Custom Indexes

Add indexes for your query patterns:

```ruby
# db/migrate/XXXXXX_add_custom_error_indexes.rb
class AddCustomErrorIndexes < ActiveRecord::Migration[7.0]
  def change
    add_index :rails_error_dashboard_error_logs, [:app_version, :occurred_at]
    add_index :rails_error_dashboard_error_logs, [:user_id, :resolved]
  end
end
```

## Advanced Customization

### Reporting Errors from Your Code

Report an error that Rails did not raise, or one you rescued yourself:

```ruby
begin
  # risky code
rescue => e
  RailsErrorDashboard::ManualErrorReporter.report(
    error_type: e.class.name,
    message: e.message,
    backtrace: e.backtrace,
    user_id: current_user.id
  )
end
```

### Custom Middleware

RED already catches errors in the Rack stack. If you add your own middleware, let the exception pass through and RED will see it. To report one you rescue yourself, use `ManualErrorReporter.report` as above and re-raise.

### Plugin Development

Create custom plugins for integrations:

```ruby
class JiraPlugin < RailsErrorDashboard::Plugin
  def name
    "Jira"
  end

  def on_error_logged(error_log)
    create_jira_ticket(error_log) if error_log.critical?
  end

  private

  def create_jira_ticket(error_log)
    JIRA::Client.new.Issue.create(
      summary: error_log.error_type,
      description: error_log.message,
      priority: 'High'
    )
  end
end

RailsErrorDashboard.register_plugin(JiraPlugin.new)
```

See [Plugin System Guide](/rails_error_dashboard/docs/features/plugin-system/) for details.

## Configuration Reference

### All Configuration Options

```ruby
RailsErrorDashboard.configure do |config|
  # Dashboard credentials come from the ERROR_DASHBOARD_USER and
  # ERROR_DASHBOARD_PASSWORD environment variables. Don't set them here.

  # Performance
  config.async_logging = true
  config.max_backtrace_lines = 50
  config.sampling_rate = 1.0

  # Filtering
  config.ignored_exceptions = []

  # Severity
  config.custom_severity_rules = {}

  # Notifications
  config.enable_slack_notifications = false
  config.slack_webhook_url = nil
  config.enable_email_notifications = false
  config.notification_email_recipients = []
  config.enable_discord_notifications = false
  config.discord_webhook_url = nil
  config.enable_pagerduty_notifications = false
  config.pagerduty_integration_key = nil
  config.enable_webhook_notifications = false
  config.webhook_urls = []

  # Baseline Alerts (Advanced)
  config.enable_baseline_alerts = true
  config.baseline_alert_threshold_std_devs = 2.0
  config.baseline_alert_severities = [:critical, :high]
  config.baseline_alert_cooldown_minutes = 120

  # Database
  config.use_separate_database = false
  config.user_model = "User"

  # UI
  config.dashboard_base_url = "http://localhost:3000"

  # Developer Tools (v0.3+)
  config.enable_breadcrumbs = false
  config.enable_system_health = false
  config.enable_source_code_integration = false
  config.enable_git_blame = false

  # Deep Debugging (v0.4)
  config.enable_local_variables = false
  config.enable_instance_variables = false
  config.detect_swallowed_exceptions = false     # Requires Ruby 3.3+
  config.enable_diagnostic_dump = false
  config.enable_rack_attack_tracking = false      # Persists to its own table
  config.enable_crash_capture = false
end
```

## Examples

### Example 1: E-commerce Setup

```ruby
RailsErrorDashboard.configure do |config|
  # Dashboard credentials come from the ERROR_DASHBOARD_USER and
  # ERROR_DASHBOARD_PASSWORD environment variables. Don't set them here.

  # Performance (high traffic)
  config.async_logging = true
  config.sampling_rate = 0.5  # Log 50% of errors

  # Critical errors
  config.custom_severity_rules = {
    'PaymentError' => :critical,
    'CheckoutError' => :critical,
    'InventoryError' => :high,
    'ShippingError' => :high
  }

  # Notifications
  config.enable_slack_notifications = true
  config.slack_webhook_url = ENV['SLACK_WEBHOOK_URL']
  config.enable_pagerduty_notifications = true
  config.pagerduty_integration_key = ENV['PAGERDUTY_KEY']
end
```

### Example 2: SaaS Application

```ruby
RailsErrorDashboard.configure do |config|
  config.async_logging = true
end

# Notify immediately for enterprise customers
RailsErrorDashboard.on_error_logged do |error_log|
  PagerDuty.trigger(error_log) if error_log.user&.subscription&.enterprise?
end
```

## Further Reading

- [Configuration Guide](/rails_error_dashboard/docs/guides/configuration/) - Complete reference
- [Plugin System](/rails_error_dashboard/docs/features/plugin-system/) - Build custom plugins
- [API Reference](/rails_error_dashboard/docs/reference/api-reference/) - The dashboard's HTTP routes and the Ruby API
- [Database Options](/rails_error_dashboard/docs/guides/database-options/) - Separate database setup

---

**Questions?** Check the [documentation](/rails_error_dashboard/docs/documentation/) or [open an issue](https://github.com/AnjanJ/rails_error_dashboard/issues).
