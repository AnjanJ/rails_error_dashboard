# Notification Configuration Guide

Rails Error Dashboard supports multiple notification backends to alert your team when errors occur.

## Available Notification Backends

- ✅ **Email** - Send error notifications via email
- ✅ **Slack** - Post errors to Slack channels
- ✅ **Discord** - Post errors to Discord channels
- ✅ **PagerDuty** - Create incidents for critical errors
- ✅ **Webhooks** - Send to any custom webhook URL

---

## Email Notifications

Send error notifications via email to your team.

### Configuration

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  config.enable_email_notifications = true
  config.notification_email_recipients = ['dev-team@example.com', 'alerts@example.com']
  config.notification_email_from = 'errors@yourapp.com'
end
```

### Environment Variables

```bash
# .env
ERROR_NOTIFICATION_EMAILS=dev-team@example.com,alerts@example.com
ERROR_NOTIFICATION_FROM=errors@yourapp.com
```

---

## Slack Notifications

Post error notifications to Slack channels using webhooks.

### Setup

1. Create a Slack webhook:
   - Go to https://api.slack.com/apps
   - Create an app → Incoming Webhooks
   - Activate webhooks and add to channel
   - Copy the webhook URL

2. Configure:

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  config.enable_slack_notifications = true
  config.slack_webhook_url = ENV['SLACK_WEBHOOK_URL']
end
```

### Environment Variables

```bash
# .env
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

---

## Discord Notifications (NEW! 🎉)

Post rich error notifications to Discord channels with color-coded severity.

### Setup

1. Create a Discord webhook:
   - Open Discord → Server Settings → Integrations → Webhooks
   - Click "New Webhook"
   - Choose channel and copy webhook URL

2. Configure:

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  config.enable_discord_notifications = true
  config.discord_webhook_url = ENV['DISCORD_WEBHOOK_URL']
end
```

### Environment Variables

```bash
# .env
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR/WEBHOOK/URL
```

### Discord Message Format

Discord notifications include:
- **Title**: Error type and severity icon (🚨)
- **Description**: Error message (truncated to 200 chars)
- **Color**: Severity-based (Red=Critical, Orange=High, Yellow=Medium, Gray=Low)
- **Fields**:
  - Platform (iOS/Android/API)
  - Environment (production/staging)
  - Occurrences count
  - Controller & Action
  - First seen timestamp
  - Backtrace location
- **Footer**: "Rails Error Dashboard"
- **Timestamp**: When error occurred

---

## PagerDuty Notifications (NEW! 🚨)

Create PagerDuty incidents for **critical errors only** to alert on-call engineers.

### Setup

1. Get PagerDuty Integration Key:
   - Go to PagerDuty → Services
   - Select your service → Integrations
   - Add "Events API V2" integration
   - Copy the Integration Key

2. Configure:

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  config.enable_pagerduty_notifications = true
  config.pagerduty_integration_key = ENV['PAGERDUTY_INTEGRATION_KEY']

  # Optional: Set dashboard URL for links in PagerDuty
  config.dashboard_base_url = 'https://yourapp.com'
end
```

### Environment Variables

```bash
# .env
PAGERDUTY_INTEGRATION_KEY=your_integration_key_here
DASHBOARD_BASE_URL=https://yourapp.com
```

### Behavior

**Important**: PagerDuty notifications only trigger for **CRITICAL severity errors**:

- `SecurityError`
- `NoMemoryError`
- `SystemStackError`
- `SignalException`
- `ActiveRecord::StatementInvalid`

This prevents alert fatigue from non-critical errors.

### PagerDuty Incident Format

- **Summary**: "Critical Error: {ErrorType} in {Platform}"
- **Severity**: critical
- **Source**: Controller#action or request URL
- **Component**: Controller name
- **Custom Details**:
  - Full error message
  - Controller & action
  - Platform & environment
  - Occurrence count
  - First/last seen timestamps
  - Request URL
  - Backtrace (first 10 lines)
  - Error ID
- **Link**: Direct link to error in dashboard

---

## Webhook Notifications (NEW! 🔗)

Send error notifications to custom webhook URLs for integration with any service.

### Setup

Configure one or multiple webhook URLs:

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  config.enable_webhook_notifications = true
  config.webhook_urls = [
    'https://your-service.com/webhook',
    'https://another-service.com/errors'
  ]

  # Or single webhook:
  # config.webhook_urls = 'https://your-service.com/webhook'
end
```

### Environment Variables

```bash
# .env (comma-separated for multiple URLs)
WEBHOOK_URLS=https://service1.com/webhook,https://service2.com/webhook
```

### Webhook Payload

Webhooks receive a JSON payload with complete error details:

```json
{
  "event": "error.created",
  "timestamp": "2024-12-24T10:30:45Z",
  "error": {
    "id": 123,
    "type": "NoMethodError",
    "message": "undefined method `name' for nil:NilClass",
    "severity": "high",
    "platform": "iOS",
    "environment": "production",
    "controller": "UsersController",
    "action": "show",
    "occurrence_count": 5,
    "first_seen_at": "2024-12-24T10:00:00Z",
    "last_seen_at": "2024-12-24T10:30:45Z",
    "occurred_at": "2024-12-24T10:30:45Z",
    "resolved": false,
    "request": {
      "url": "/users/123",
      "params": {"id": "123"},
      "user_agent": "Mozilla/5.0...",
      "ip_address": "192.168.1.1"
    },
    "user": {
      "id": 456
    },
    "backtrace": [
      "app/controllers/users_controller.rb:23:in `show'",
      "..."
    ],
    "metadata": {
      "error_hash": "abc123def456",
      "dashboard_url": "https://yourapp.com/error_dashboard/errors/123"
    }
  }
}
```

### HTTP Headers

Webhooks include these headers:

```
Content-Type: application/json
User-Agent: RailsErrorDashboard/1.0
X-Error-Dashboard-Event: error.created
X-Error-Dashboard-ID: 123
```

### Timeout

Webhook requests timeout after 10 seconds to prevent blocking.

---

## Complete Configuration Example

Here's a full configuration using all notification backends:

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  # Authentication
  config.dashboard_username = ENV.fetch('ERROR_DASHBOARD_USER', 'admin')
  config.dashboard_password = ENV.fetch('ERROR_DASHBOARD_PASSWORD', 'changeme')
  config.require_authentication = true

  # Dashboard URL (for links in notifications)
  config.dashboard_base_url = ENV['DASHBOARD_BASE_URL'] || 'https://yourapp.com'

  # Email notifications (for all errors)
  config.enable_email_notifications = true
  config.notification_email_recipients = ENV.fetch('ERROR_NOTIFICATION_EMAILS', '').split(',')
  config.notification_email_from = 'errors@yourapp.com'

  # Slack notifications (for all errors)
  config.enable_slack_notifications = true
  config.slack_webhook_url = ENV['SLACK_WEBHOOK_URL']

  # Discord notifications (for all errors)
  config.enable_discord_notifications = true
  config.discord_webhook_url = ENV['DISCORD_WEBHOOK_URL']

  # PagerDuty notifications (CRITICAL ERRORS ONLY)
  config.enable_pagerduty_notifications = true
  config.pagerduty_integration_key = ENV['PAGERDUTY_INTEGRATION_KEY']

  # Custom webhooks (for all errors)
  config.enable_webhook_notifications = true
  config.webhook_urls = ENV.fetch('WEBHOOK_URLS', '').split(',')
end
```

### Environment Variables (.env)

```bash
# Dashboard
DASHBOARD_BASE_URL=https://yourapp.com
ERROR_DASHBOARD_USER=admin
ERROR_DASHBOARD_PASSWORD=super_secret_password

# Email
ERROR_NOTIFICATION_EMAILS=dev-team@example.com,alerts@example.com

# Slack
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL

# Discord
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR/WEBHOOK/URL

# PagerDuty (critical errors only)
PAGERDUTY_INTEGRATION_KEY=your_pagerduty_integration_key

# Custom Webhooks
WEBHOOK_URLS=https://service1.com/webhook,https://service2.com/webhook
```

---

## Notification Strategy Recommendations

### For Small Teams (< 5 developers)

```ruby
config.enable_email_notifications = true
config.enable_slack_notifications = true
config.enable_discord_notifications = false
config.enable_pagerduty_notifications = false
config.enable_webhook_notifications = false
```

**Why**: Email + Slack provides good coverage without overwhelming the team.

### For Medium Teams (5-20 developers)

```ruby
config.enable_email_notifications = true
config.enable_slack_notifications = true
config.enable_discord_notifications = true  # If team uses Discord
config.enable_pagerduty_notifications = true  # For critical errors
config.enable_webhook_notifications = false
```

**Why**: Multiple channels + PagerDuty for critical alerts ensures on-call coverage.

### For Large Teams (20+ developers)

```ruby
config.enable_email_notifications = false  # Too noisy
config.enable_slack_notifications = true   # #errors channel
config.enable_discord_notifications = true  # Alternative channel
config.enable_pagerduty_notifications = true  # Critical alerts
config.enable_webhook_notifications = true  # Custom integrations
```

**Why**: Focus on actionable channels, skip email noise, use PagerDuty for escalation.

---

## Testing Notifications

To test your notification configuration:

```ruby
# rails console
error = begin
  raise StandardError, "Test error notification"
rescue => e
  e
end

RailsErrorDashboard::Commands::LogError.call(error, {
  controller_name: "TestController",
  action_name: "test_action",
  platform: "API"
})
```

Check that notifications arrive in:
- ✅ Email inbox
- ✅ Slack channel
- ✅ Discord channel
- ✅ PagerDuty incidents (only for critical errors)
- ✅ Webhook endpoints

---

## Disabling Notifications in Development

To avoid notification spam during development:

```ruby
# config/environments/development.rb
Rails.application.configure do
  # Disable all notifications in development
  config.after_initialize do
    if defined?(RailsErrorDashboard)
      RailsErrorDashboard.configuration.enable_email_notifications = false
      RailsErrorDashboard.configuration.enable_slack_notifications = false
      RailsErrorDashboard.configuration.enable_discord_notifications = false
      RailsErrorDashboard.configuration.enable_pagerduty_notifications = false
      RailsErrorDashboard.configuration.enable_webhook_notifications = false
    end
  end
end
```

---

## Troubleshooting

### Notifications not sending

1. **Check configuration**:
   ```ruby
   rails console
   config = RailsErrorDashboard.configuration
   config.enable_slack_notifications  # Should be true
   config.slack_webhook_url  # Should have URL
   ```

2. **Check background jobs**:
   ```ruby
   # Ensure ActiveJob is configured
   Rails.application.config.active_job.queue_adapter  # Should be :sidekiq or :solid_queue

   # Check job queue
   Sidekiq::Queue.new("default").size  # Should see jobs
   ```

3. **Check logs**:
   ```bash
   tail -f log/production.log | grep "notification"
   ```

### Webhook timeouts

If webhooks are timing out:

1. Increase timeout in job (default: 10s)
2. Check webhook endpoint is responding
3. Consider async webhook processing

### PagerDuty not triggering

PagerDuty only triggers for **critical** errors. Test with:

```ruby
error = begin
  raise SecurityError, "Test critical error"  # Critical type
rescue => e
  e
end

RailsErrorDashboard::Commands::LogError.call(error, {})
```

---

## Next Steps

- Configure your preferred notification backends
- Test notifications work correctly
- Set up appropriate channels/webhooks
- Configure environment variables
- Monitor error notifications

For more help, see the [main README](../README.md).
