# Configuration Guide

This guide covers all configuration options for Rails Error Dashboard, including advanced features for customization and extensibility.

## Table of Contents

- [Opt-in Feature System](#opt-in-feature-system)
- [Basic Configuration](#basic-configuration)
- [Notification Features](#notification-features)
- [Performance Features](#performance-features)
- [Advanced Analytics Features](#advanced-analytics-features)
- [Custom Severity Classification](#custom-severity-classification)
- [Ignored Exceptions](#ignored-exceptions)
- [Error Sampling](#error-sampling)
- [Notification Callbacks](#notification-callbacks)
- [ActiveSupport Notifications](#activesupport-notifications)
- [Backtrace Configuration](#backtrace-configuration)
- [Complete Configuration Example](#complete-configuration-example)

---

## Opt-in Feature System

Rails Error Dashboard uses an **opt-in architecture**. Core features are always enabled, while everything else is disabled by default.

**Tier 1 Features (Always ON):**
- ✅ Error capture (controllers, jobs, middleware)
- ✅ Dashboard UI with search and filtering
- ✅ Real-time updates via Turbo Streams
- ✅ Analytics and trend charts

**Optional Features (15 total):**
- 📧 **5 Notification Channels** (Slack, Email, Discord, PagerDuty, Webhooks)
- ⚡ **3 Performance Features** (Async Logging, Error Sampling, Separate Database)
- 📊 **7 Advanced Analytics** (Baseline Alerts, Fuzzy Matching, Co-occurring Errors, Error Cascades, Correlation, Platform Comparison, Occurrence Patterns)

All features can be enabled during installation via the interactive installer, or toggled on/off at any time in the initializer.

---

## Basic Configuration

Create an initializer at `config/initializers/rails_error_dashboard.rb`:

```ruby
RailsErrorDashboard.configure do |config|
  # Dashboard authentication (always required)
  config.dashboard_username = "admin"
  config.dashboard_password = ENV.fetch("ERROR_DASHBOARD_PASSWORD", "changeme")

  # Data retention (days)
  config.retention_days = 90

  # User model for error association
  config.user_model = "User"

  # Enable/disable middleware and error subscriber
  config.enable_middleware = true
  config.enable_error_subscriber = true
end
```

---

## Notification Features

Rails Error Dashboard supports 5 notification channels, all disabled by default.

### Slack Notifications

Send real-time error notifications to Slack channels.

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_slack_notifications = true
  config.slack_webhook_url = ENV['SLACK_WEBHOOK_URL']
end
```

### Email Notifications

Send error alerts via email to your team.

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_email_notifications = true
  config.notification_email_recipients = ["dev@yourapp.com", "team@yourapp.com"]
  config.notification_email_from = "errors@yourapp.com"
end
```

### Discord Notifications

Push errors to Discord channels via webhooks.

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_discord_notifications = true
  config.discord_webhook_url = ENV['DISCORD_WEBHOOK_URL']
end
```

### PagerDuty Integration

Escalate critical errors to PagerDuty for on-call teams. **Only triggers for critical errors** to avoid alert fatigue.

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_pagerduty_notifications = true
  config.pagerduty_integration_key = ENV['PAGERDUTY_INTEGRATION_KEY']
end
```

### Custom Webhooks

Send errors to custom endpoints (Zapier, IFTTT, custom services).

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_webhook_notifications = true
  config.webhook_urls = [
    'https://yourapp.com/hooks/errors',
    'https://zapier.com/hooks/catch/123456/abcdef'
  ]
end
```

**Dashboard Base URL** (for notification links):
```ruby
config.dashboard_base_url = ENV['DASHBOARD_BASE_URL']  # e.g., "https://yourapp.com"
```

See [Notifications Guide](NOTIFICATIONS.md) for detailed setup instructions.

---

## Performance Features

Optimize performance and reduce database load with these features.

### Async Error Logging

Log errors in background jobs for non-blocking performance.

```ruby
RailsErrorDashboard.configure do |config|
  config.async_logging = true
  config.async_adapter = :sidekiq  # Options: :sidekiq, :solid_queue, :async
end
```

**Supported Adapters:**
- `:sidekiq` - Battle-tested, recommended for production
- `:solid_queue` - Rails 8.1+ built-in job backend
- `:async` - Rails default (in-process, good for development)

### Error Sampling

Reduce database writes by logging only a percentage of non-critical errors. **Critical errors are ALWAYS logged** regardless of sampling rate.

```ruby
RailsErrorDashboard.configure do |config|
  config.sampling_rate = 0.1  # Log 10% of non-critical errors
end
```

See [Error Sampling](#error-sampling) section below for details.

### Separate Database

Isolate error data in a dedicated database for better performance and separation of concerns.

```ruby
RailsErrorDashboard.configure do |config|
  config.use_separate_database = true
end
```

Requires additional database configuration. See [Database Options Guide](DATABASE_OPTIONS.md) for setup instructions.

---

## Advanced Analytics Features

Powerful analytics features for deep error insights, all disabled by default.

### Baseline Anomaly Alerts

Automatically detect when error rates exceed normal patterns using statistical analysis.

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_baseline_alerts = true
  config.baseline_alert_threshold_std_devs = 2.0  # Alert when >2 std devs above baseline
  config.baseline_alert_severities = [:critical, :high]  # Alert on these severities only
  config.baseline_alert_cooldown_minutes = 120  # 2 hours between alerts for same error
end
```

See [Baseline Monitoring Guide](../features/BASELINE_MONITORING.md) for details.

### Fuzzy Error Matching

Find similar errors even with different error_hashes using backtrace signatures and message similarity.

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_similar_errors = true
end
```

See [Advanced Error Grouping Guide](../features/ADVANCED_ERROR_GROUPING.md) for details.

### Co-occurring Errors

Detect errors that happen together in time (within 5-minute windows).

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_co_occurring_errors = true
end
```

See [Advanced Error Grouping Guide](../features/ADVANCED_ERROR_GROUPING.md) for details.

### Error Cascades

Identify parent→child error relationships (error A causes error B).

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_error_cascades = true
end
```

See [Advanced Error Grouping Guide](../features/ADVANCED_ERROR_GROUPING.md) for details.

### Error Correlation

Correlate errors with app versions, users, and time patterns.

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_error_correlation = true
end
```

See [Error Correlation Guide](../features/ERROR_CORRELATION.md) for details.

### Platform Comparison

Compare iOS vs Android vs Web health metrics and platform-specific error rates.

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_platform_comparison = true
end
```

See [Platform Comparison Guide](../features/PLATFORM_COMPARISON.md) for details.

### Occurrence Patterns

Detect cyclical patterns (daily/weekly rhythms) and error bursts.

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_occurrence_patterns = true
end
```

See [Occurrence Patterns Guide](../features/OCCURRENCE_PATTERNS.md) for details.

---

## Custom Severity Classification

Override default severity levels for specific error types. This is useful when you want to treat certain errors differently than the defaults.

### Default Severity Levels

- **Critical**: `SecurityError`, `NoMemoryError`, `SystemStackError`, `ActiveRecord::StatementInvalid`
- **High**: `ActiveRecord::RecordNotFound`, `ArgumentError`, `TypeError`, `NoMethodError`, `NameError`
- **Medium**: `ActiveRecord::RecordInvalid`, `Timeout::Error`, `Net::ReadTimeout`, `Net::OpenTimeout`
- **Low**: All other errors

### Configuration

```ruby
RailsErrorDashboard.configure do |config|
  config.custom_severity_rules = {
    # Treat payment errors as critical
    "Stripe::CardError" => :critical,
    "PaymentProcessingError" => :critical,

    # Downgrade validation errors to low
    "ActiveRecord::RecordInvalid" => :low,

    # Custom application errors
    "MyApp::BusinessLogicError" => :medium
  }
end
```

### Use Cases

- **Payment Errors**: Treat as critical to ensure immediate attention
- **Validation Errors**: Downgrade to low if they're expected user input errors
- **Third-party API Errors**: Classify based on business impact
- **Custom Application Errors**: Set appropriate severity for domain-specific errors

---

## Ignored Exceptions

Prevent certain exceptions from being logged. Useful for reducing noise from expected errors or third-party gems.

### Configuration

```ruby
RailsErrorDashboard.configure do |config|
  config.ignored_exceptions = [
    # Exact class names
    "ActionController::RoutingError",
    "ActiveRecord::RecordNotFound",

    # Regex patterns for flexible matching
    /Rack::Timeout/,
    /ActionController::InvalidAuthenticityToken/,

    # All errors from a specific namespace
    /ThirdPartyGem::.*/
  ]
end
```

### Features

- **Exact Matching**: Specify exception class names as strings
- **Regex Patterns**: Use regular expressions for flexible matching
- **Inheritance Support**: Ignoring a parent class ignores all subclasses
- **Early Exit**: Ignored exceptions skip all processing, saving resources

### Use Cases

```ruby
# Production: Ignore bot-related errors
config.ignored_exceptions = [
  "ActionController::RoutingError",  # Bots scanning for vulnerabilities
  /ActionController::InvalidAuthenticityToken/  # CSRF from legitimate crawlers
]

# Development: Ignore known third-party issues
config.ignored_exceptions = [
  /Geocoder::.*/,  # Geocoding API rate limits
  "Redis::CannotConnectError"  # Redis disconnects during development
]
```

---

## Error Sampling

Reduce database load by logging only a percentage of non-critical errors. **Critical errors are ALWAYS logged** regardless of sampling rate.

### Configuration

```ruby
RailsErrorDashboard.configure do |config|
  # Log 100% of errors (default)
  config.sampling_rate = 1.0

  # Log only 10% of non-critical errors (critical errors always logged)
  config.sampling_rate = 0.1

  # Disable logging of non-critical errors entirely
  config.sampling_rate = 0.0
end
```

### Behavior

- **1.0 (100%)**: Log all errors - default behavior
- **0.1 (10%)**: Log 10% of non-critical errors, 100% of critical errors
- **0.0 (0%)**: Skip all non-critical errors, log only critical errors
- **> 1.0**: Treated as 100%
- **< 0.0**: Treated as 0%

### Critical Errors (Always Logged)

These errors bypass sampling because they indicate serious system issues:
- `SecurityError`
- `NoMemoryError`
- `SystemStackError`
- `ActiveRecord::StatementInvalid`

### Use Cases

```ruby
# High-traffic production: Reduce database writes
config.sampling_rate = 0.1  # 10% sampling

# Load testing: Only log critical issues
config.sampling_rate = 0.0  # Skip non-critical

# Monitoring phase: Full visibility
config.sampling_rate = 1.0  # Log everything
```

---

## Notification Callbacks

Register custom Ruby blocks that execute when errors are logged or resolved. Perfect for integrating with external services.

### Available Callbacks

#### 1. `on_error_logged` - Any Error Logged

```ruby
RailsErrorDashboard.on_error_logged do |error_log|
  # Called for every NEW error (not recurrences)

  # Send to custom logging service
  CustomLogger.log(
    level: error_log.severity,
    message: error_log.message,
    metadata: {
      error_type: error_log.error_type,
      platform: error_log.platform,
      environment: error_log.environment
    }
  )
end
```

#### 2. `on_critical_error` - Critical Errors Only

```ruby
RailsErrorDashboard.on_critical_error do |error_log|
  # Called ONLY for critical errors (in addition to on_error_logged)

  # Trigger PagerDuty incident
  PagerDuty.trigger(
    summary: "Critical: #{error_log.error_type}",
    severity: "critical",
    source: error_log.platform,
    custom_details: {
      message: error_log.message,
      backtrace: error_log.backtrace&.lines&.first(5)
    }
  )
end
```

#### 3. `on_error_resolved` - Error Resolved

```ruby
RailsErrorDashboard.on_error_resolved do |error_log|
  # Called when error is marked as resolved

  # Notify team
  Slack.post_message(
    channel: "#engineering",
    text: "✅ Error resolved: #{error_log.error_type}",
    attachments: [{
      fields: [
        { title: "Resolved By", value: error_log.resolved_by_name },
        { title: "Occurrences", value: error_log.occurrence_count },
        { title: "Resolution", value: error_log.resolution_comment }
      ]
    }]
  )
end
```

### Multiple Callbacks

You can register multiple callbacks for the same event:

```ruby
# Callback 1: Log to external service
RailsErrorDashboard.on_error_logged do |error_log|
  Datadog.increment("errors.logged", tags: ["type:#{error_log.error_type}"])
end

# Callback 2: Send to analytics
RailsErrorDashboard.on_error_logged do |error_log|
  Analytics.track_error(error_log)
end

# Both callbacks will execute
```

### Error Handling

Callbacks are fail-safe - if one callback raises an error, it won't break error logging or prevent other callbacks from running:

```ruby
RailsErrorDashboard.on_error_logged do |error_log|
  raise "Callback error"  # Logged as warning, other callbacks still run
end

RailsErrorDashboard.on_error_logged do |error_log|
  puts "This still executes"  # ✓ Runs even if previous callback failed
end
```

### Integration Examples

#### Datadog

```ruby
RailsErrorDashboard.on_error_logged do |error_log|
  Datadog::Statsd.increment("errors.logged",
    tags: [
      "severity:#{error_log.severity}",
      "platform:#{error_log.platform}",
      "environment:#{error_log.environment}"
    ]
  )
end
```

#### Sentry (alongside Error Dashboard)

```ruby
RailsErrorDashboard.on_critical_error do |error_log|
  Sentry.capture_message(
    "Critical Error: #{error_log.error_type}",
    level: :fatal,
    extra: {
      error_id: error_log.id,
      message: error_log.message,
      platform: error_log.platform
    }
  )
end
```

#### Custom Metrics

```ruby
RailsErrorDashboard.on_error_logged do |error_log|
  Prometheus.error_counter.increment(
    labels: {
      type: error_log.error_type,
      severity: error_log.severity,
      platform: error_log.platform
    }
  )
end
```

---

## ActiveSupport Notifications

Rails Error Dashboard emits standard Rails instrumentation events that can be subscribed to using `ActiveSupport::Notifications`.

### Available Events

#### 1. `error_logged.rails_error_dashboard`

Emitted when any error is logged (new errors only, not recurrences).

```ruby
ActiveSupport::Notifications.subscribe("error_logged.rails_error_dashboard") do |name, start, finish, id, payload|
  # Payload contains:
  # - error_log: Full ErrorLog record
  # - error_id: Error ID
  # - error_type: Exception class name
  # - message: Error message
  # - severity: Error severity (:critical, :high, :medium, :low)
  # - platform: Platform (iOS, Android, API)
  # - environment: Rails environment
  # - occurred_at: Timestamp

  duration = finish - start
  StatsD.timing("error_logging.duration", duration)
  StatsD.increment("errors.logged", tags: ["type:#{payload[:error_type]}"])
end
```

#### 2. `critical_error.rails_error_dashboard`

Emitted when a critical error is logged (in addition to `error_logged`).

```ruby
ActiveSupport::Notifications.subscribe("critical_error.rails_error_dashboard") do |name, start, finish, id, payload|
  # Same payload as error_logged

  # Trigger immediate alert
  PagerDuty.trigger_incident(
    title: "Critical Error: #{payload[:error_type]}",
    severity: "critical",
    details: payload[:message]
  )
end
```

#### 3. `error_resolved.rails_error_dashboard`

Emitted when an error is marked as resolved.

```ruby
ActiveSupport::Notifications.subscribe("error_resolved.rails_error_dashboard") do |name, start, finish, id, payload|
  # Payload contains:
  # - error_log: Full ErrorLog record
  # - error_id: Error ID
  # - error_type: Exception class name
  # - resolved_by: Name of person who resolved it
  # - resolved_at: Timestamp

  Analytics.track_resolution(
    error_id: payload[:error_id],
    resolved_by: payload[:resolved_by],
    resolution_time: payload[:resolved_at] - payload[:error_log].occurred_at
  )
end
```

### Using Event Objects

```ruby
ActiveSupport::Notifications.subscribe("error_logged.rails_error_dashboard") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)

  puts "Event: #{event.name}"
  puts "Duration: #{event.duration}ms"
  puts "Error Type: #{event.payload[:error_type]}"
  puts "Severity: #{event.payload[:severity]}"
end
```

### Wildcard Subscriptions

```ruby
# Subscribe to all Rails Error Dashboard events
ActiveSupport::Notifications.subscribe(/rails_error_dashboard/) do |event|
  Rails.logger.info "Error Dashboard Event: #{event.name}"
end
```

### Integration Examples

#### NewRelic

```ruby
ActiveSupport::Notifications.subscribe("critical_error.rails_error_dashboard") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  NewRelic::Agent.notice_error(
    StandardError.new(event.payload[:message]),
    custom_params: {
      error_id: event.payload[:error_id],
      platform: event.payload[:platform]
    }
  )
end
```

#### Prometheus

```ruby
error_counter = Prometheus::Client::Counter.new(
  :rails_errors_total,
  docstring: "Total number of Rails errors",
  labels: [:type, :severity, :platform]
)

ActiveSupport::Notifications.subscribe("error_logged.rails_error_dashboard") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  error_counter.increment(
    labels: {
      type: event.payload[:error_type],
      severity: event.payload[:severity],
      platform: event.payload[:platform]
    }
  )
end
```

#### Elasticsearch

```ruby
ActiveSupport::Notifications.subscribe("error_logged.rails_error_dashboard") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)

  Elasticsearch::Client.new.index(
    index: "rails-errors",
    body: {
      timestamp: event.payload[:occurred_at],
      error_type: event.payload[:error_type],
      message: event.payload[:message],
      severity: event.payload[:severity],
      platform: event.payload[:platform],
      environment: event.payload[:environment]
    }
  )
end
```

---

## Async Error Logging (Revisited)

Async logging is available and fully functional. See the [Async Error Logging](#async-error-logging) section above for complete configuration details.

For quick reference:

```ruby
RailsErrorDashboard.configure do |config|
  # Enable async logging
  config.async_logging = true

  # Choose adapter: :sidekiq (default), :solid_queue, or :async
  config.async_adapter = :sidekiq
end
```

---

## Backtrace Configuration

Control how many lines of backtrace are stored:

```ruby
RailsErrorDashboard.configure do |config|
  # Limit backtrace to 50 lines (default)
  config.max_backtrace_lines = 50

  # Store more for detailed debugging
  config.max_backtrace_lines = 100

  # Minimal storage (just the first line)
  config.max_backtrace_lines = 1
end
```

**Benefits:**
- Reduced database storage
- Faster error logging
- Still captures the most relevant stack frames

---

## Complete Configuration Example

Here's a production-ready configuration combining multiple features:

```ruby
# config/initializers/rails_error_dashboard.rb

RailsErrorDashboard.configure do |config|
  # ============================================================================
  # AUTHENTICATION (Always Required)
  # ============================================================================
  # Authentication is always required in all environments
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
  # NOTIFICATION SETTINGS
  # ============================================================================

  # Slack Notifications
  config.enable_slack_notifications = true
  config.slack_webhook_url = ENV["SLACK_WEBHOOK_URL"]

  # Email Notifications
  config.enable_email_notifications = true
  config.notification_email_recipients = ENV.fetch("ERROR_NOTIFICATION_EMAILS", "").split(",").map(&:strip)
  config.notification_email_from = ENV.fetch("ERROR_NOTIFICATION_FROM", "errors@example.com")

  # Discord Notifications
  config.enable_discord_notifications = true
  config.discord_webhook_url = ENV["DISCORD_WEBHOOK_URL"]

  # PagerDuty Integration (critical errors only)
  config.enable_pagerduty_notifications = true
  config.pagerduty_integration_key = ENV["PAGERDUTY_INTEGRATION_KEY"]

  # Generic Webhook Notifications
  config.enable_webhook_notifications = true
  config.webhook_urls = ENV.fetch("WEBHOOK_URLS", "").split(",").map(&:strip).reject(&:empty?)

  # Dashboard base URL (used in notification links)
  config.dashboard_base_url = ENV["DASHBOARD_BASE_URL"]

  # ============================================================================
  # PERFORMANCE & SCALABILITY
  # ============================================================================

  # Async Error Logging
  config.async_logging = true
  config.async_adapter = :sidekiq  # Options: :sidekiq, :solid_queue, :async

  # Backtrace size limiting
  config.max_backtrace_lines = 50

  # Error Sampling (10% - critical errors ALWAYS logged)
  config.sampling_rate = 0.1

  # Ignored exceptions
  config.ignored_exceptions = [
    "ActionController::RoutingError",
    "ActionController::InvalidAuthenticityToken",
    /^ActiveRecord::RecordNotFound/
  ]

  # ============================================================================
  # DATABASE CONFIGURATION
  # ============================================================================
  config.use_separate_database = false

  # ============================================================================
  # ADVANCED ANALYTICS
  # ============================================================================

  # Baseline Anomaly Alerts
  config.enable_baseline_alerts = true
  config.baseline_alert_threshold_std_devs = 2.0
  config.baseline_alert_severities = [:critical, :high]
  config.baseline_alert_cooldown_minutes = 120

  # Fuzzy Error Matching
  config.enable_similar_errors = true

  # Co-occurring Errors
  config.enable_co_occurring_errors = true

  # Error Cascade Detection
  config.enable_error_cascades = true

  # Error Correlation Analysis
  config.enable_error_correlation = true

  # Platform Comparison
  config.enable_platform_comparison = true

  # Occurrence Pattern Detection
  config.enable_occurrence_patterns = true

  # ============================================================================
  # ADDITIONAL CONFIGURATION
  # ============================================================================

  # Custom severity rules
  config.custom_severity_rules = {
    "PaymentError" => :critical,
    "ValidationError" => :low
  }

  # Enhanced metrics
  config.app_version = ENV["APP_VERSION"]
  config.git_sha = ENV["GIT_SHA"]
  # config.total_users_for_impact = 10000  # For user impact % calculation
end

# ============================================================================
# NOTIFICATION CALLBACKS
# ============================================================================

# Alert on critical errors
RailsErrorDashboard.on_critical_error do |error_log|
  PagerDuty.trigger(
    summary: "Critical: #{error_log.error_type}",
    severity: "critical",
    source: error_log.platform
  )
end

# Track metrics
RailsErrorDashboard.on_error_logged do |error_log|
  StatsD.increment("errors.logged",
    tags: [
      "type:#{error_log.error_type}",
      "severity:#{error_log.severity}",
      "platform:#{error_log.platform}"
    ]
  )
end

# Notify on resolution
RailsErrorDashboard.on_error_resolved do |error_log|
  Slack.post_message(
    channel: "#engineering",
    text: "✅ #{error_log.error_type} resolved by #{error_log.resolved_by_name}"
  )
end

# ============================================================================
# ACTIVESUPPORT NOTIFICATIONS
# ============================================================================

# Send to external logging service
ActiveSupport::Notifications.subscribe("error_logged.rails_error_dashboard") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)

  Elasticsearch::Client.new.index(
    index: "rails-errors",
    body: {
      timestamp: event.payload[:occurred_at],
      error_type: event.payload[:error_type],
      message: event.payload[:message],
      severity: event.payload[:severity],
      platform: event.payload[:platform]
    }
  )
end
```

---

## Environment-Specific Configuration

Configure differently per environment:

```ruby
RailsErrorDashboard.configure do |config|
  # Common configuration
  config.user_model = "User"
  config.max_backtrace_lines = 50

  if Rails.env.production?
    # Production: Aggressive sampling, strict filtering
    config.sampling_rate = 0.1
    config.ignored_exceptions = [
      "ActionController::RoutingError",
      /ActionController::InvalidAuthenticityToken/
    ]

  elsif Rails.env.staging?
    # Staging: Moderate sampling
    config.sampling_rate = 0.5

  else
    # Development/Test: Log everything
    config.sampling_rate = 1.0
    config.ignored_exceptions = []
  end
end
```

---

## Troubleshooting

### Configuration Not Taking Effect

**Problem**: Changes to `config/initializers/rails_error_dashboard.rb` don't seem to work.

**Solutions**:
1. **Restart server** - Configuration is loaded at startup
   ```bash
   rails server
   ```

2. **Check file location** - Must be in `config/initializers/`
   ```bash
   ls -la config/initializers/rails_error_dashboard.rb
   ```

3. **Check for syntax errors**
   ```bash
   ruby -c config/initializers/rails_error_dashboard.rb
   ```

4. **Verify configuration is loaded**
   ```ruby
   # In rails console
   RailsErrorDashboard.configuration.inspect
   ```

### Environment Variables Not Working

**Problem**: `ENV['VARIABLE']` returns `nil` in configuration.

**Solutions**:
1. **Load environment variables before Rails**
   - Use `dotenv-rails` gem for development
   - Use system environment variables in production

2. **Check variable is set**
   ```bash
   echo $SLACK_WEBHOOK_URL
   ```

3. **Provide defaults**
   ```ruby
   config.slack_webhook_url = ENV.fetch('SLACK_WEBHOOK_URL', nil)
   ```

### Notifications Not Sending

**Problem**: Slack/Discord notifications aren't working.

**Solutions**:
1. **Check notifications are enabled**
   ```ruby
   # In rails console
   RailsErrorDashboard.configuration.enable_slack_notifications
   # Should return true
   ```

2. **Verify webhook URL is set**
   ```ruby
   RailsErrorDashboard.configuration.slack_webhook_url
   # Should return your webhook URL
   ```

3. **Test webhook manually**
   ```bash
   curl -X POST YOUR_WEBHOOK_URL \
     -H 'Content-Type: application/json' \
     -d '{"text": "Test message"}'
   ```

4. **Check background jobs are running**
   ```bash
   # With Sidekiq
   bundle exec sidekiq

   # With Solid Queue
   bin/jobs
   ```

5. **Check notification thresholds**
   ```ruby
   # Critical errors only go to PagerDuty
   config.severity_thresholds[:pagerduty] = :critical
   ```

### Custom Severity Rules Not Working

**Problem**: Custom severity rules aren't being applied.

**Solutions**:
1. **Check rule format** - Use regex or symbol
   ```ruby
   # Correct
   config.custom_severity_rules = {
     /ActiveRecord::RecordNotFound/ => :low,
     :timeout_error => :high
   }

   # Incorrect (string won't match)
   config.custom_severity_rules = {
     "ActiveRecord::RecordNotFound" => :low
   }
   ```

2. **Test regex patterns**
   ```ruby
   # In rails console
   error_class = "ActiveRecord::RecordNotFound"
   /ActiveRecord::RecordNotFound/.match?(error_class)
   # Should return true
   ```

3. **Check rule order** - First match wins
   ```ruby
   # More specific rules should come first
   config.custom_severity_rules = {
     /ActiveRecord::RecordNotFound.*User/ => :high,  # Specific
     /ActiveRecord::RecordNotFound/ => :low          # General
   }
   ```

### Background Jobs Not Processing

**Problem**: Async logging enabled but errors not appearing.

**Solutions**:
1. **Check job adapter configuration**
   ```ruby
   # In rails console
   RailsErrorDashboard.configuration.async_adapter
   # Should return :sidekiq, :solid_queue, or :async
   ```

2. **Verify job processor is running**
   ```bash
   # Sidekiq
   ps aux | grep sidekiq

   # Solid Queue
   ps aux | grep solid_queue
   ```

3. **Check failed jobs**
   ```ruby
   # Sidekiq
   require 'sidekiq/api'
   Sidekiq::RetrySet.new.size
   Sidekiq::DeadSet.new.size

   # Solid Queue
   SolidQueue::Job.failed.count
   ```

4. **Test with sync logging temporarily**
   ```ruby
   config.async_logging = false  # For debugging
   ```

### Sampling Too Aggressive

**Problem**: Too many errors being filtered out.

**Solutions**:
1. **Check sampling rate**
   ```ruby
   RailsErrorDashboard.configuration.sampling_rate
   # 0.1 = 10% of errors logged
   ```

2. **Critical errors always logged** - Check severity
   ```ruby
   # Critical errors bypass sampling
   config.severity_thresholds[:critical]
   ```

3. **Adjust rate** - Start higher, tune down
   ```ruby
   config.sampling_rate = 0.5  # Start with 50%
   ```

4. **Use conditional sampling**
   ```ruby
   config.before_log_callback = lambda do |exception, context|
     # Always log payment errors
     return true if exception.message.include?("Stripe")

     # Sample others based on environment
     Rails.env.production? ? rand < 0.1 : true
   end
   ```

### Database Performance Issues

**Problem**: Error logging is slow or causing database issues.

**Solutions**:
1. **Enable async logging**
   ```ruby
   config.async_logging = true
   ```

2. **Use separate database**
   ```ruby
   config.database = :errors
   ```

3. **Add database indexes** - Already included in migrations

4. **Increase backtrace limit**
   ```ruby
   config.max_backtrace_lines = 20  # Default is 50
   ```

5. **Configure retention policy**
   ```ruby
   config.retention_days = 30  # Auto-cleanup old errors
   ```

See [Database Optimization Guide](DATABASE_OPTIMIZATION.md) for more.

### Authentication Not Working

**Problem**: Can't access dashboard even with correct credentials.

**Solutions**:
1. **Check username and password are set**
   ```ruby
   # In rails console
   RailsErrorDashboard.configuration.dashboard_username
   RailsErrorDashboard.configuration.dashboard_password
   ```

2. **Verify HTTP Basic Auth is configured**
   ```ruby
   config.dashboard_username = "admin"
   config.dashboard_password = "secure_password"
   ```

3. **Test credentials**
   ```bash
   curl -u admin:password http://localhost:3000/error_dashboard
   ```

4. **Check for proxy/load balancer issues**
   - Some proxies strip Authorization headers
   - May need to configure pass-through

5. **Clear browser cache** - Old credentials may be cached

### Multi-App Configuration Issues

**Problem**: Errors from multiple apps not showing correctly.

**Solutions**:
1. **Set APP_NAME environment variable**
   ```bash
   APP_NAME=my-api rails server
   ```

2. **Or configure manually**
   ```ruby
   config.application_name = "my-api"
   ```

3. **Verify application is created**
   ```ruby
   # In rails console
   RailsErrorDashboard::Application.all.pluck(:name)
   ```

4. **Check errors are tagged correctly**
   ```ruby
   RailsErrorDashboard::ErrorLog.last.application.name
   ```

See [Multi-App Support Guide](../MULTI_APP_PERFORMANCE.md) for more.

---

## Resetting Configuration

For testing or dynamic reconfiguration:

```ruby
# Reset to defaults
RailsErrorDashboard.reset_configuration!

# Reconfigure
RailsErrorDashboard.configure do |config|
  config.sampling_rate = 1.0
end
```

---

## Next Steps

- **Testing**: Write tests for your custom callbacks and severity rules
- **Monitoring**: Set up ActiveSupport::Notifications subscribers for your metrics service
- **Optimization**: Review database optimization and performance tuning guides

For questions or issues, visit: https://github.com/AnjanJ/rails_error_dashboard
