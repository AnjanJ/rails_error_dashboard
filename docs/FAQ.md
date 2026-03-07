# Frequently Asked Questions

Common questions about Rails Error Dashboard.

---

<details>
<summary><strong>Is this production-ready?</strong></summary>

This is currently in **beta** but actively tested with 2,100+ passing tests across Rails 7.0-8.1 and Ruby 3.2-4.0. Many users are running it in production. See [production requirements](FEATURES.md#production-ready).
</details>

<details>
<summary><strong>How does this compare to Sentry/Rollbar/Honeybadger?</strong></summary>

**Similar**: Error tracking, grouping, notifications, dashboards
**Better**: 100% free, self-hosted (your data stays with you), no usage limits, Rails-optimized
**Trade-offs**: You manage hosting/backups, fewer integrations than commercial services

See [full comparison](features/PLATFORM_COMPARISON.md).
</details>

<details>
<summary><strong>What's the performance impact?</strong></summary>

Minimal with async logging enabled:
- **Synchronous**: ~10-50ms per error (blocks request)
- **Async (recommended)**: ~1-2ms (queues to background job)
- **Sampling**: Log only 10% of non-critical errors for high-traffic apps

See [Performance Guide](guides/ERROR_SAMPLING_AND_FILTERING.md).
</details>

<details>
<summary><strong>Can I use a separate database?</strong></summary>

Yes! Configure in your initializer:

```ruby
RailsErrorDashboard.configure do |config|
  config.database = :errors  # Use separate database
end
```

See [Database Options Guide](guides/DATABASE_OPTIONS.md).
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

See [API-only setup](guides/MOBILE_APP_INTEGRATION.md#backend-setup-rails-api).
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

All apps share the same dashboard. See [Multi-App Guide](MULTI_APP_PERFORMANCE.md).
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

See [Customization Guide](CUSTOMIZATION.md).
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

Or schedule with cron/whenever. See [Database Optimization](guides/DATABASE_OPTIMIZATION.md).
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

Supports Slack, Discord, Email, PagerDuty, and custom webhooks. See [Notifications Guide](guides/NOTIFICATIONS.md).
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

See [Mobile App Integration](guides/MOBILE_APP_INTEGRATION.md).
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

See [Plugin System Guide](PLUGIN_SYSTEM.md).
</details>

<details>
<summary><strong>What if I need help?</strong></summary>

- **Read the docs**: [docs/README.md](README.md)
- **Report bugs**: [GitHub Issues](https://github.com/AnjanJ/rails_error_dashboard/issues)
- **Ask questions**: [GitHub Discussions](https://github.com/AnjanJ/rails_error_dashboard/discussions)
- **Security issues**: See [SECURITY.md](../SECURITY.md)
</details>
