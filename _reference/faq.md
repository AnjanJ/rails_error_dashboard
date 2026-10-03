---
layout: default
title: "Frequently Asked Questions"
order: 2
---

# Frequently Asked Questions

Common questions about Rails Error Dashboard.

---

<details>
<summary><strong>Is this production-ready?</strong></summary>

This is currently in **beta** but covered by an RSpec suite that CI runs across Rails 7.0-8.1 on Ruby 3.2-3.4 (Ruby 4.0 is verified by the maintainer). Many users are running it in production. See [production requirements](/rails_error_dashboard/docs/features/#production-ready).
</details>

<details>
<summary><strong>How does this compare to Sentry/Rollbar/Honeybadger?</strong></summary>

**What RED records that they don't**: the state of the process at the moment of failure — GC, memory, file descriptors, load, the ActiveRecord pool, Puma, job queues, RubyVM/YJIT — stored on the error record itself and refreshed on every captured occurrence; a raise-vs-rescue aggregate of swallowed exceptions; Copy as RSpec; and a Storm History ledger of everything shed during an error flood.
**Similar**: error capture and grouping, breadcrumbs, local variables, notifications, workflow, dashboards.
**Also**: it runs inside your app and your data never leaves your infrastructure — a self-hosted Sentry alternative — and the gem is MIT and free forever, with no plan limits — your database is the only cap.
**Trade-offs**: you manage hosting and backups; no mobile SDKs, no merge/split, no MCP server, and fewer integrations than commercial services.

Every claim above was checked against 30+ products and gems in August 2026 — see [the verified ledger](https://github.com/AnjanJ/rails_error_dashboard/blob/main/.shipkit/research/red-unique-features-verified.md).
</details>

<details>
<summary><strong>What's the performance impact?</strong></summary>

Minimal with async logging enabled:
- **Synchronous**: ~10-50ms per error (blocks request)
- **Async (recommended)**: ~1-2ms (queues to background job)
- **Sampling**: Log only 10% of non-critical errors for high-traffic apps

See [Performance Guide](/rails_error_dashboard/docs/guides/error-sampling-and-filtering/).
</details>

<details>
<summary><strong>Can I use a separate database?</strong></summary>

Yes. Choose option 2 at the installer's database prompt, or pass `--separate-database`. The installer then writes both settings it needs:

```ruby
RailsErrorDashboard.configure do |config|
  config.use_separate_database = true
  config.database = :error_dashboard
end
```

It also prints the `config/database.yml` entry to add. Add it for every environment, with `migrations_paths: db/error_dashboard_migrate`, then run `bin/rails db:create`.

Both settings matter: `config.database` on its own is ignored unless `use_separate_database` is true. And if `config/database.yml` has no entry for the current environment, RED logs an error at boot, `bin/rails error_dashboard:verify` fails, and RED falls back to your main database, where its tables don't exist, so errors in that environment are not recorded.

See [Database Options Guide](/rails_error_dashboard/docs/guides/database-options/).
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

To report errors from your API's clients, see [the mobile endpoint](/rails_error_dashboard/docs/guides/mobile-app-integration/#the-endpoint).
</details>

<details>
<summary><strong>How do I track multiple Rails apps?</strong></summary>

Point every app at the same error database: choose option 3 (shared database) at each app's installer prompt. Apps share a dashboard only when they share that database.

Each app's errors are recorded under its name. RED uses `config.application_name` if you set it, then the `APPLICATION_NAME` environment variable, and otherwise the app's module name (`MyApi` for `module MyApi` in `config/application.rb`):

```ruby
# config/initializers/rails_error_dashboard.rb
config.application_name = "my-api"
```

The dashboard can filter by app. See [Multi-App Guide](/rails_error_dashboard/docs/features/multi-app-performance/).
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

See [Customization Guide](/rails_error_dashboard/docs/guides/customization/).
</details>

<details>
<summary><strong>How long are errors stored?</strong></summary>

Until you delete them: the gem never deletes errors by itself.

The generated initializer sets `config.retention_days = 90`. Errors not seen for that many days are deleted when retention cleanup runs. Run it by hand, or schedule it daily with your scheduler (Solid Queue's `config/recurring.yml`, sidekiq-cron, cron):

```bash
bin/rails error_dashboard:retention_cleanup
# or schedule the job: RailsErrorDashboard::RetentionCleanupJob
```

To delete only resolved errors:

```bash
# Delete resolved errors older than 90 days
rails error_dashboard:cleanup_resolved DAYS=90

# Filter by application name
rails error_dashboard:cleanup_resolved DAYS=30 APP_NAME="My App"
```

Or schedule with cron/whenever. See [Database Optimization](/rails_error_dashboard/docs/guides/database-optimization/).
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

Supports Slack, Discord, Email, PagerDuty, and custom webhooks. See [Notifications Guide](/rails_error_dashboard/docs/guides/notifications/).
</details>

<details>
<summary><strong>Does it work with Turbo/Hotwire?</strong></summary>

Yes — with `turbo-rails` and a working ActionCable adapter in the host app, new errors appear in the dashboard over Turbo Streams without a page refresh. Without them the dashboard does not auto-refresh; there is no polling fallback.
</details>

<details>
<summary><strong>How do I report errors from mobile apps?</strong></summary>

The gem ships no mobile SDK and no ingest endpoint. Add a small endpoint to your own Rails app that calls `RailsErrorDashboard::ManualErrorReporter`, then POST to it from the app. The platform is whatever the endpoint passes as `platform:`; RED doesn't work it out from a mobile app's User-Agent:

```javascript
// React Native: the endpoint is the one in the guide, with your API's own auth header
fetch('https://api.example.com/api/v1/mobile_errors', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${apiToken}`
  },
  body: JSON.stringify({
    error: {
      error_type: 'TypeError',
      message: "Cannot read properties of undefined (reading 'id')",
      platform: Platform.OS,
      timestamp: Date.now()
    }
  })
});
```

See [Mobile App Integration](/rails_error_dashboard/docs/guides/mobile-app-integration/).
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

See [Plugin System Guide](/rails_error_dashboard/docs/features/plugin-system/).
</details>

<details>
<summary><strong>Is TracePoint safe for production? What's the performance impact?</strong></summary>

Yes. TracePoint(`:raise`) is the same mechanism Sentry uses in production. It only fires when an exception is raised (not on every line of code). The overhead is sub-millisecond per exception. Values are extracted immediately and the Binding is discarded — no memory leaks.

TracePoint(`:rescue`) (used for swallowed exception detection) is similarly lightweight. It was added in Ruby 3.3 (Feature #19572) and only fires on rescue events.

Both are opt-in and disabled by default. See [Local Variable Capture](/rails_error_dashboard/docs/features/#local-variable-capture-v040) and the [safety guarantees](/rails_error_dashboard/docs/features/#safety-guarantees).
</details>

<details>
<summary><strong>What Ruby version do I need for swallowed exception detection?</strong></summary>

**Ruby 3.3+** is required for swallowed exception detection. The feature uses `TracePoint(:rescue)` which was added in Ruby 3.3 (Feature #19572).

If you enable `detect_swallowed_exceptions = true` on Ruby < 3.3, it will be automatically disabled with a warning — no crash or error.

All other v0.4.0 features (local variables, instance variables, diagnostic dumps, crash capture, Rack Attack tracking) work on Ruby 3.2+.
</details>

<details>
<summary><strong>How do I capture a diagnostic dump?</strong></summary>

Two ways:

1. **Dashboard button** — Visit `/errors/diagnostic_dumps` and click "Capture Dump"
2. **Rake task** — `rails error_dashboard:diagnostic_dump` (add `NOTE="deploy check"` for a note)

Dumps capture: environment, GC stats, threads, connection pool, memory, job queue health, RubyVM/YJIT stats. Requires `config.enable_diagnostic_dump = true`.
</details>

<details>
<summary><strong>What are swallowed exceptions? Why should I care?</strong></summary>

Swallowed exceptions are exceptions that are `raise`d but then silently `rescue`d — never logged, re-raised, or handled meaningfully. They're the hardest bugs to find because they produce no visible error.

Example: a `rescue => e` that does nothing silently corrupts state. The swallowed exception detector finds these code paths by comparing raise counts vs rescue counts per location.

No self-hosted Rails tool has this. Only Datadog's paid APM detects rescued exceptions (Ruby 3.3+, inside a traced request); RED does it without an APM span and aggregates the raise-vs-rescue ratio per location, which nothing else does. See [Swallowed Exception Detection](/rails_error_dashboard/docs/features/#swallowed-exception-detection-v040).
</details>

<details>
<summary><strong>What if I need help?</strong></summary>

- **Read the docs**: [docs/README.md](/rails_error_dashboard/docs/documentation/)
- **Report bugs**: [GitHub Issues](https://github.com/AnjanJ/rails_error_dashboard/issues)
- **Ask questions**: [GitHub Discussions](https://github.com/AnjanJ/rails_error_dashboard/discussions)
- **Security issues**: See [SECURITY.md](https://github.com/AnjanJ/rails_error_dashboard/blob/main/SECURITY.md)
</details>
