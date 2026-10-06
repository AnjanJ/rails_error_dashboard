---
layout: default
title: "Plugin System Guide"
permalink: /docs/PLUGIN_SYSTEM
---

# Plugin System Guide

A plugin is a Ruby class that RED calls when something happens to an error: it is recorded, happens
again, is resolved, muted, deleted, or viewed. Use one to send metrics, write an audit trail, or
open tickets in a tracker RED doesn't support. (RED's own
[issue tracking](guides/CONFIGURATION.md#issue-tracking--githubgitlabcodeberg-v058) covers GitHub,
GitLab, Codeberg and Linear.)

## Quick Start

### 1. Create a plugin

```ruby
# config/initializers/error_dashboard_plugins.rb
class MyCustomPlugin < RailsErrorDashboard::Plugin
  def name
    "My Custom Plugin"
  end

  def description
    "Does something with errors"
  end

  def on_error_logged(error_log)
    Rails.logger.info("New error: #{error_log.error_type}")
  end
end
```

### 2. Register it

```ruby
# config/initializers/error_dashboard_plugins.rb, after the class
RailsErrorDashboard.register_plugin(MyCustomPlugin.new)
```

From then on, each new error calls `on_error_logged`. The plugin appears under **Active Plugins** on
the [Settings page](guides/SETTINGS.md).

---

## Event hooks

Define the hooks you need; the base class defines all of them as doing nothing.

| Hook | Argument | Called when |
|---|---|---|
| `on_error_logged` | the `ErrorLog` | An error is recorded for the first time. An open error that keeps happening more than 24 hours after RED first recorded it starts a new record, and calls this again |
| `on_error_recurred` | the `ErrorLog` | An open error happens again, muted errors included |
| `on_error_reopened` | the `ErrorLog` | A resolved error happens again, which reopens it |
| `on_error_resolved` | the `ErrorLog` | An error is resolved with the Resolve button, `ErrorLog#resolve!`, or by its linked issue being closed |
| `on_error_muted` | the `ErrorLog` | An error is muted (the Mute button or `ErrorLog#mute!`) |
| `on_error_unmuted` | the `ErrorLog` | An error is unmuted |
| `on_errors_batch_resolved` | an Array of the `ErrorLog`s resolved | A batch resolve |
| `on_errors_batch_muted` | an Array of `ErrorLog`s | A batch mute |
| `on_errors_batch_unmuted` | an Array of `ErrorLog`s | A batch unmute |
| `on_errors_batch_deleted` | an Array of the deleted IDs | A batch delete |
| `on_error_viewed` | the `ErrorLog` | Someone opens the error's page in the dashboard |

Two more methods are called on the plugin itself: `on_register`, once, when you register it, and
`enabled?`, before every hook.

Some changes call no hook:

- a batch resolve calls `on_errors_batch_resolved` only, never `on_error_resolved` for each error;
- changing an error's status to `resolved` with a `POST` to `update_status`;
- reopening an error when its linked issue is reopened;
- errors that storm protection only counts, errors deleted by `RetentionCleanupJob`, and errors
  that are ignored or sampled out.

### Where hooks run

Hooks run one plugin after another, in the order you registered them, in the same thread as the
event:

- **Capture hooks** (`on_error_logged`, `on_error_recurred`, `on_error_reopened`) run inside RED's
  capture: in the request or job that raised the error, or, with `config.async_logging` on, in the
  background job that saves it.
- **Dashboard hooks** (resolve, mute, unmute, batch actions, viewed) run in the dashboard request.

A slow hook slows down whatever it runs in. Hand slow work to a background job:

```ruby
def on_error_logged(error_log)
  SendErrorJob.perform_later(error_log.id)
end
```

---

## Plugin API

### The base class

```ruby
class RailsErrorDashboard::Plugin
  def name                 # required, and unique among your plugins
    raise NotImplementedError, "Plugin must implement #name"
  end

  def description = "No description provided"
  def version = "1.0.0"
  def on_register; end    # called once, at registration
  def enabled? = true      # checked before every hook

  # Event hooks, all optional
  def on_error_logged(error_log); end
  def on_error_recurred(error_log); end
  def on_error_reopened(error_log); end
  def on_error_resolved(error_log); end
  def on_error_muted(error_log); end
  def on_error_unmuted(error_log); end
  def on_errors_batch_resolved(error_logs); end
  def on_errors_batch_muted(error_logs); end
  def on_errors_batch_unmuted(error_logs); end
  def on_errors_batch_deleted(error_ids); end
  def on_error_viewed(error_log); end

  # Calls a hook and rescues what it raises (see "When a plugin fails")
  def safe_execute(method_name, *args); end
end
```

`name` is required. Without it, `register_plugin` raises `NotImplementedError`. If no other plugin
is registered yet, the nameless one is added before the error. Hooks still run, but until the app
restarts, `register_plugin`, `unregister_plugin` and the registry's `names`, `info` and `find` raise,
the Settings page fails with a 500, and any hook failure raises instead of being rescued.

### Registering

```ruby
RailsErrorDashboard.register_plugin(MyCustomPlugin.new)
# => true, or false when a plugin with the same name is already registered

RailsErrorDashboard.register_plugin(Object.new)
# => ArgumentError: Plugin must be an instance of RailsErrorDashboard::Plugin

RailsErrorDashboard.unregister_plugin("My Custom Plugin")
RailsErrorDashboard.plugins # => [#<MyCustomPlugin>, ...]

RailsErrorDashboard::PluginRegistry.names # => ["My Custom Plugin"]
RailsErrorDashboard::PluginRegistry.info
# => [{ name: "My Custom Plugin", version: "1.0.0", description: "...", enabled: true }]
RailsErrorDashboard::PluginRegistry.find("My Custom Plugin") # => #<MyCustomPlugin>
```

Register plugins in an initializer, so they are registered once, at boot.

### When a plugin fails

- An exception (a `StandardError`) raised inside a hook is rescued. The error is still recorded, and
  the other plugins still run.
- The failure is logged only when `config.log_level` is `:error` or lower; the default, `:silent`,
  logs nothing. The log lines look like this:

  ```text
  [RailsErrorDashboard] [RailsErrorDashboard] Plugin 'My Custom Plugin' failed in on_error_logged: Errno::ECONNREFUSED - Connection refused
  [RailsErrorDashboard] Plugin version: 1.0.0
  [RailsErrorDashboard] /app/config/initializers/error_dashboard_plugins.rb:12:in 'on_error_logged'
  ```

- **`enabled?` is not protected.** An exception raised in `enabled?` is not rescued. During capture,
  RED gives up on the rest of that capture after the error is saved. In the dashboard, the error page
  and the Resolve, Mute and Unmute actions fail with a 500; a batch action says "Batch operation
  failed", although the errors were already changed. Keep `enabled?` simple.
- **`on_register` is not protected either.** An exception there raises out of `register_plugin`, so
  from an initializer it stops the app booting.
- Exceptions that aren't `StandardError`s, such as `NotImplementedError`, aren't rescued anywhere.

---

## Example plugins

### Metrics (StatsD, Datadog)

```ruby
class ErrorMetricsPlugin < RailsErrorDashboard::Plugin
  def name
    "Error Metrics"
  end

  def on_error_logged(error_log)
    StatsD.increment("errors.new")
    StatsD.increment("errors.by_type.#{metric_name(error_log.error_type)}")
  end

  def on_error_resolved(error_log)
    StatsD.increment("errors.resolved")
    seconds = error_log.resolved_at - error_log.first_seen_at
    StatsD.timing("errors.time_to_resolve", (seconds * 1000).round) # timing takes milliseconds
  end

  private

  def metric_name(name)
    name.gsub("::", ".").downcase
  end
end

RailsErrorDashboard.register_plugin(ErrorMetricsPlugin.new)
```

### Audit log

```ruby
class ErrorAuditPlugin < RailsErrorDashboard::Plugin
  def initialize(logger: Rails.logger)
    @logger = logger
  end

  def name
    "Error Audit"
  end

  def on_error_resolved(error_log)
    @logger.info("[Audit] resolved #{error_log.id} by #{error_log.resolved_by_name}")
  end

  def on_error_muted(error_log)
    @logger.info("[Audit] muted #{error_log.id} by #{error_log.muted_by}: #{error_log.muted_reason}")
  end

  def on_errors_batch_deleted(error_ids)
    @logger.info("[Audit] deleted #{error_ids.size} errors: #{error_ids.join(', ')}")
  end
end

RailsErrorDashboard.register_plugin(ErrorAuditPlugin.new)
```

### Tickets in another tracker (Jira)

`ErrorLog` has no column for your own data, so keep the ticket key in a table of yours, here a
`JiraTicketLink` model with `error_hash` and `key` columns. Key it by `error_hash`, the error's
fingerprint: an error that keeps happening for more than 24 hours gets a new record with the same
fingerprint, and should reuse the ticket. Build the dashboard link with
`NotificationHelpers.dashboard_url`, which uses `config.dashboard_base_url` and the path the
dashboard is really mounted at.

```ruby
class JiraTicketsPlugin < RailsErrorDashboard::Plugin
  def initialize(jira_client:, project_key:)
    @jira = jira_client
    @project_key = project_key
  end

  def name
    "Jira Tickets"
  end

  def on_error_logged(error_log)
    return unless error_log.critical?
    return if JiraTicketLink.exists?(error_hash: error_log.error_hash)

    CreateJiraTicketJob.perform_later(error_log.id) # the job calls create_ticket
  end

  def create_ticket(error_log)
    issue = @jira.Issue.build
    issue.save("fields" => {
      "project" => { "key" => @project_key },
      "summary" => "[#{error_log.environment}] #{error_log.error_type}",
      "description" => "#{error_log.message}\n\n" \
                       "#{RailsErrorDashboard::Services::NotificationHelpers.dashboard_url(error_log)}",
      "issuetype" => { "name" => "Bug" }
    })
    JiraTicketLink.create!(error_hash: error_log.error_hash, key: issue.key)
  end

  def on_error_resolved(error_log)
    link = JiraTicketLink.find_by(error_hash: error_log.error_hash)
    CloseJiraTicketJob.perform_later(link.key) if link # the job calls close_ticket
  end

  def close_ticket(key)
    issue = @jira.Issue.find(key)
    done = issue.transitions.all.find { |transition| transition.name == "Done" }
    issue.transitions.build.save!("transition" => { "id" => done.id }) if done
  end
end
```

Both Jira calls run in your jobs, which get the plugin with
`RailsErrorDashboard::PluginRegistry.find("Jira Tickets")`. That keeps Jira's response time out of
capture and out of the Resolve button, and a failed call fails the job, where you see it and it can
be retried; inside a hook, RED would rescue it, and log nothing at the default `log_level`. Use the
transition name your Jira workflow has.

### Production only

```ruby
class ProductionAlertPlugin < RailsErrorDashboard::Plugin
  def name
    "Production Alerts"
  end

  def enabled?
    Rails.env.production?
  end

  def on_error_logged(error_log)
    ProductionAlertService.send_alert(error_log)
  end
end
```

---

## Built-in example plugins

The gem ships three plugins as starting points. They aren't loaded until you require them.

| Plugin | What it does |
|---|---|
| `Plugins::MetricsPlugin` | Writes a metric line for new, repeated and resolved errors and for batch resolves and deletes, through RED's own logger, which logs nothing unless `enable_internal_logging` is on and `log_level` is `:info` or lower. The StatsD and Datadog calls are commented out |
| `Plugins::AuditLogPlugin` | Writes a JSON line to the logger you pass for new, repeated, resolved and viewed errors and for batch resolves and deletes. Mute, unmute and reopen aren't logged |
| `Plugins::JiraIntegrationPlugin` | Logs what it would send to Jira for critical errors, through RED's own logger (silent by default, as above). The API call is commented out. It is enabled only when all four Jira settings are given |

```ruby
# config/initializers/error_dashboard_plugins.rb
require "rails_error_dashboard/plugins/metrics_plugin"
require "rails_error_dashboard/plugins/audit_log_plugin"
require "rails_error_dashboard/plugins/jira_integration_plugin"

RailsErrorDashboard.register_plugin(RailsErrorDashboard::Plugins::MetricsPlugin.new)

RailsErrorDashboard.register_plugin(
  RailsErrorDashboard::Plugins::AuditLogPlugin.new(
    logger: Logger.new(Rails.root.join("log", "error_audit.log"))
  )
)

if Rails.env.production?
  RailsErrorDashboard.register_plugin(
    RailsErrorDashboard::Plugins::JiraIntegrationPlugin.new(
      jira_url: ENV["JIRA_URL"],
      jira_username: ENV["JIRA_USERNAME"],
      jira_api_token: ENV["JIRA_API_TOKEN"],
      jira_project_key: ENV["JIRA_PROJECT_KEY"],
      only_critical: true
    )
  )
end
```

Copy one into your app and change it, rather than relying on it as is.

---

## Best practices

- **Keep hooks fast.** They run inside capture or a dashboard request. Use a job for anything slow.
- **Use the batch hooks for batches.** One call for the whole batch, not one per error.
- **Create clients when first used**, not in `on_register`: an exception there stops the app booting.
- **Check dependencies in `enabled?`**, simply. It must not raise:

  ```ruby
  def enabled?
    defined?(Datadog) && ENV["DATADOG_API_KEY"].present?
  end
  ```

- **Filter what you send out.** Error messages and backtraces can contain personal data or
  secrets.
- **Read credentials from the environment**, not from the source.

---

## Debugging plugins

### See what is registered

```ruby
RailsErrorDashboard::PluginRegistry.names
RailsErrorDashboard::PluginRegistry.info
RailsErrorDashboard::PluginRegistry.find("My Custom Plugin").enabled?
```

The Settings page lists the same under **Active Plugins**.

### Trigger a hook

Recording an error calls `on_error_logged` for you; don't dispatch it again by hand:

```ruby
RailsErrorDashboard.configuration.async_logging = false # this console only
RailsErrorDashboard::ManualErrorReporter.report(error_type: "PluginTestError", message: "plugin test")
```

To call one plugin's hook on an existing error, the way RED does (with the rescue):

```ruby
plugin = RailsErrorDashboard::PluginRegistry.find("My Custom Plugin")
plugin.safe_execute(:on_error_logged, RailsErrorDashboard::ErrorLog.last)
```

### See failures

Set `config.log_level = :error` and look for `Plugin '...' failed in` in the log.

---

## Testing plugins

```ruby
# spec/plugins/my_custom_plugin_spec.rb
require "rails_helper"

RSpec.describe MyCustomPlugin do
  let(:plugin) { described_class.new }
  let(:error_log) { RailsErrorDashboard::ErrorLog.new(error_type: "NoMethodError", message: "test") }

  it "has a name" do
    expect(plugin.name).to eq("My Custom Plugin")
  end

  it "logs the error type" do
    allow(Rails.logger).to receive(:info)
    plugin.on_error_logged(error_log)
    expect(Rails.logger).to have_received(:info).with("New error: NoMethodError")
  end
end
```

Call hooks directly, as above, so a hook that raises fails the spec. Through `safe_execute`, RED
rescues the exception and the spec passes anyway. An unsaved `ErrorLog.new` is enough for a hook
that only reads the error. For one that needs a saved error, create it with your own factory (the
gem's factories aren't part of the gem), or with `ManualErrorReporter` and `async_logging` off; if
you change the configuration in a spec, set it back afterwards, because it is global.

---

## FAQ

### Can a plugin change the error record?

It can update the error's existing columns, but `ErrorLog` has no column for your own data. Keep
plugin data in your own table, keyed by `error_log.id`.

### What happens if a plugin crashes?

See [When a plugin fails](#when-a-plugin-fails).

### Can plugins depend on each other?

No. Each is called on its own. Put shared logic in a class they both use.

### Is there a limit on plugins?

No, but every event calls every enabled plugin, in turn.

---

## Troubleshooting

### A plugin receives no events

1. Check it is registered: `RailsErrorDashboard::PluginRegistry.names`.
2. Check `enabled?` returns true:
   `RailsErrorDashboard::PluginRegistry.find("My Custom Plugin").enabled?`.
3. Check the event calls a hook at all (see [Event hooks](#event-hooks)).
4. Set `config.log_level = :error` and look for `failed in` in the log.

### Registering twice

A second plugin with the same name isn't registered: `register_plugin` returns `false`. RED logs a
warning about it only when `enable_internal_logging` is on and `log_level` is `:warn` or lower.

---

## Related Documentation

- [Documentation index](README.md) - All the guides
- [Notifications](guides/NOTIFICATIONS.md) - Built-in notification channels
- [Batch Operations](guides/BATCH_OPERATIONS.md) - What fires the batch hooks
- [API Reference](API_REFERENCE.md#callbacks-and-notifications) - Callbacks and `ActiveSupport::Notifications` events
