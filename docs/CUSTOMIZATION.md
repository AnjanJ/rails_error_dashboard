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

### Pattern Matching

Use string matching for flexibility:

```ruby
config.custom_severity_rules = {
  # Exact match
  'ActiveRecord::RecordNotFound' => :low,

  # Your custom errors
  'MyApp::PaymentProcessingError' => :critical,
  'MyApp::EmailDeliveryError' => :medium,

  # Third-party gems
  'Stripe::CardError' => :high,
  'AWS::S3::Errors::ServiceError' => :medium
}
```

### Dynamic Severity

For more complex logic, use a proc:

```ruby
# Advanced: Not yet implemented, but planned for future
config.severity_calculator = ->(error) do
  return :critical if error.message.include?('payment')
  return :high if error.backtrace.any? { |line| line.include?('critical_path') }
  :medium
end
```

## Custom Error Context

Add custom data to every error for better debugging.

### Basic Context

```ruby
RailsErrorDashboard.configure do |config|
  config.add_error_context do |context|
    # Add custom fields
    context[:environment] = Rails.env
    context[:server_name] = ENV['SERVER_NAME']
    context[:deploy_version] = ENV['DEPLOY_VERSION']
    context
  end
end
```

### Request-Specific Context

Add data from the current request:

```ruby
config.add_error_context do |context|
  # Available in context: request, user, etc.
  if context[:request]
    context[:user_agent] = context[:request].user_agent
    context[:referer] = context[:request].referer
    context[:request_id] = context[:request].request_id
  end

  if context[:user]
    context[:user_email] = context[:user].email
    context[:user_role] = context[:user].role
    context[:subscription_plan] = context[:user].subscription&.plan
  end

  context
end
```

### Performance Context

Track performance metrics:

```ruby
config.add_error_context do |context|
  context[:memory_usage] = `ps -o rss= -p #{Process.pid}`.to_i / 1024
  context[:load_average] = File.read('/proc/loadavg').split.first rescue nil
  context[:active_connections] = ActiveRecord::Base.connection_pool.stat[:busy]
  context
end
```

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

### Conditional Logging

Use a proc for complex filtering:

```ruby
config.should_log_error = ->(exception, context) do
  # Don't log in test environment
  return false if Rails.env.test?

  # Don't log bot requests
  return false if context[:user_agent]&.match?(/bot|crawler|spider/i)

  # Don't log known third-party errors
  return false if exception.is_a?(Faraday::TimeoutError)

  # Log everything else
  true
end
```

## Custom Notifications

### Custom Notification Channels

Add your own notification logic:

```ruby
RailsErrorDashboard.configure do |config|
  config.on_error_logged do |error_log|
    # Custom notification logic
    if error_log.critical?
      CustomNotifier.alert(
        message: "Critical error: #{error_log.error_type}",
        error_id: error_log.id
      )
    end
  end
end
```

### Conditional Notifications

Only notify for certain errors:

```ruby
config.on_error_logged do |error_log|
  # Only notify for payment errors
  if error_log.error_type.include?('Payment')
    PaymentTeam.notify(error_log)
  end

  # Only notify during business hours
  if Time.current.hour.between?(9, 17)
    SlackNotifier.send(error_log)
  end
end
```

### Custom Slack Format

Customize Slack message format:

```ruby
# Override in your own job
class CustomSlackNotification < RailsErrorDashboard::SlackErrorNotificationJob
  def build_payload(error_log)
    {
      text: "🚨 #{error_log.error_type}",
      blocks: [
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: "*Error*: #{error_log.error_type}\n*Message*: #{error_log.message}"
          }
        },
        # Your custom blocks
      ]
    }
  end
end

# Use your custom job
config.on_error_logged do |error_log|
  CustomSlackNotification.perform_later(error_log.id)
end
```

## UI Customization

### Custom Styles

Override the dashboard CSS:

```css
/* app/assets/stylesheets/rails_error_dashboard_custom.css */
.rails-error-dashboard {
  --primary-color: #FF6B6B;
  --success-color: #51CF66;
  --danger-color: #FF6B6B;
}

.error-card {
  border-left: 4px solid var(--primary-color);
}
```

Include in your application:

```ruby
# config/initializers/assets.rb
Rails.application.config.assets.precompile += %w[rails_error_dashboard_custom.css]
```

### Custom Views

Override dashboard views by creating files in your app:

```
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

See [Database Options Guide](guides/DATABASE_OPTIONS.md) for details.

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

### Custom Error Reporter

Replace the default error reporter:

```ruby
class CustomErrorReporter
  def self.report(exception, context = {})
    # Your custom error reporting logic
    RailsErrorDashboard::Commands::LogError.call(
      error_type: exception.class.name,
      message: exception.message,
      backtrace: exception.backtrace,
      **context
    )

    # Also send to external service
    Sentry.capture_exception(exception)
  end
end

# Use it in your application
begin
  # risky code
rescue => e
  CustomErrorReporter.report(e, user_id: current_user.id)
end
```

### Custom Middleware

Add custom error catching middleware:

```ruby
class CustomErrorCatcher
  def initialize(app)
    @app = app
  end

  def call(env)
    @app.call(env)
  rescue => exception
    # Custom error handling
    context = {
      path: env['PATH_INFO'],
      method: env['REQUEST_METHOD'],
      custom_field: extract_custom_data(env)
    }

    RailsErrorDashboard::ErrorReporter.report(exception, context)
    raise # Re-raise to let Rails handle it
  end

  private

  def extract_custom_data(env)
    # Your custom logic
  end
end

# Add to middleware stack
config.middleware.use CustomErrorCatcher
```

### Plugin Development

Create custom plugins for integrations:

```ruby
# lib/rails_error_dashboard/plugins/jira_plugin.rb
module RailsErrorDashboard
  module Plugins
    class JiraPlugin < Plugin
      on :error_logged do |error_log|
        create_jira_ticket(error_log) if error_log.critical?
      end

      def create_jira_ticket(error_log)
        JIRA::Client.new.Issue.create(
          summary: error_log.error_type,
          description: error_log.message,
          priority: 'High'
        )
      end
    end
  end
end
```

See [Plugin System Guide](PLUGIN_SYSTEM.md) for details.

## Configuration Reference

### All Configuration Options

```ruby
RailsErrorDashboard.configure do |config|
  # Authentication
  config.username = "admin"
  config.password = "secure_password"

  # Performance
  config.async_logging = true
  config.async_adapter = :sidekiq
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
  config.notification_email = nil
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
end
```

## Examples

### Example 1: E-commerce Setup

```ruby
RailsErrorDashboard.configure do |config|
  # Security
  config.username = ENV['ERROR_DASHBOARD_USERNAME']
  config.password = ENV['ERROR_DASHBOARD_PASSWORD']

  # Performance (high traffic)
  config.async_logging = true
  config.async_adapter = :sidekiq
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

  # Context
  config.add_error_context do |context|
    context[:checkout_step] = context[:request]&.params&.dig(:step)
    context[:cart_value] = context[:user]&.cart&.total
    context
  end
end
```

### Example 2: SaaS Application

```ruby
RailsErrorDashboard.configure do |config|
  config.async_logging = true

  # Severity by plan
  config.on_error_logged do |error_log|
    if error_log.user&.subscription&.enterprise?
      # Notify immediately for enterprise customers
      PagerDuty.trigger(error_log)
    end
  end

  # Context
  config.add_error_context do |context|
    if context[:user]
      context[:subscription_plan] = context[:user].subscription&.plan
      context[:account_id] = context[:user].account_id
    end
    context
  end
end
```

## Further Reading

- [Configuration Guide](guides/CONFIGURATION.md) - Complete reference
- [Plugin System](PLUGIN_SYSTEM.md) - Build custom plugins
- [API Reference](API_REFERENCE.md) - Full API documentation
- [Database Options](guides/DATABASE_OPTIONS.md) - Separate database setup

---

**Questions?** Check the [documentation](README.md) or [open an issue](https://github.com/AnjanJ/rails_error_dashboard/issues).
