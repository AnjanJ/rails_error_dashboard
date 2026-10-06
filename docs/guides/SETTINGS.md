---
layout: default
title: "Settings Dashboard"
permalink: /docs/guides/SETTINGS
---

# Settings Dashboard

The Settings page shows the configuration your running app loaded, read-only. Use it to check
which features are on after a deploy, without reading the initializer and the environment
variables it uses.

---

## Opening the page

Click **Settings**, with the sliders icon, at the bottom of the dashboard's sidebar (on a phone, it
is in the menu). Or open `/red/settings`. Like the rest of the dashboard, it needs the dashboard
login.

---

## What the page shows

The page lists options by group. Each row has the option's name as you write it in the initializer,
its current value, and a one-line description. Click a group's heading to fold it; the first time,
it takes two clicks.

The values are the ones the app loaded at boot: your initializer, the environment variables it
reads, and RED's defaults for everything you didn't set. After you change the initializer or an
environment variable, restart the app before checking here.

Some rows appear only when their feature is on. For example, `slack_webhook_url` appears only
while `enable_slack_notifications` is on.

Some rows show what RED worked out rather than what you wrote: `application_name`, `user_model` and
`total_users_for_impact` are detected when you leave them unset (the last from a live count of your
users), and the issue tracker's provider and repository come from `git_repository_url` when you
leave them unset.

| Group | Options |
|---|---|
| Core Features | `enable_middleware`, `enable_error_subscriber`, `retention_days`, `max_backtrace_lines`, `sampling_rate` |
| Multi-App Support | `application_name`, `environment`, `database`, `use_separate_database` |
| User Integration | `user_model`, `total_users_for_impact` |
| Performance Settings | `async_logging`, `async_adapter`, `enable_rate_limiting`, `rate_limit_per_minute` |
| Notification Channels | `notification_environments`, `notification_burst_limit`, `notification_burst_window_seconds`, and for each channel (Slack, email, Discord, PagerDuty, webhooks) its switch and its URL, key or recipients (for email, also `notification_email_from`); then `enable_scheduled_digests`, `digest_frequency`, `digest_recipients` |
| Advanced Analytics Features | `enable_similar_errors`, `enable_co_occurring_errors`, `enable_error_cascades`, `enable_error_correlation`, `enable_platform_comparison`, `enable_occurrence_patterns`, `enable_baseline_alerts`, `baseline_alert_threshold_std_devs`, `baseline_alert_severities`, `baseline_alert_cooldown_minutes` |
| Source Code Integration | `enable_source_code_integration`, `source_code_context_lines`, `enable_git_blame`, `source_code_cache_ttl`, `only_show_app_code_source`, `git_branch_strategy` |
| Breadcrumbs | `enable_breadcrumbs`, `breadcrumb_buffer_size`, `enable_n_plus_one_detection`, `n_plus_one_threshold` |
| System Health | `enable_system_health` |
| Enhanced Metrics | `app_version`, `git_sha`, `git_repository_url`, `dashboard_base_url` |
| Issue Tracking | `enable_issue_tracking`, `issue_tracker_token`, `issue_tracker_provider`, `issue_tracker_repo`, `issue_tracker_labels`, `issue_webhook_secret` |
| Deep Debugging | `enable_local_variables`, `enable_instance_variables`, `detect_swallowed_exceptions`, `enable_diagnostic_dump`, `enable_crash_capture`, `enable_coverage_tracking` |
| Event Tracking | `enable_rack_attack_tracking`, `enable_actioncable_tracking`, `enable_activestorage_tracking` |
| Advanced Configuration | `custom_severity_rules`, `ignored_exceptions` |
| Internal Logging | `enable_internal_logging`, `log_level` |

Not every option is on the page. The LLM observability options, for one, aren't shown. The
[Configuration Guide](CONFIGURATION.md) has them all.

After the groups come two cards:

- **Active Plugins** lists the plugins you registered, with their name, version, description, and
  whether each is active. See the [Plugin System](../PLUGIN_SYSTEM.md).
- **Test Notifications** has a **Send Test Error** button. After you confirm, it records a
  `RailsErrorDashboard::TestError`, which is notified like any new error: through Slack, email,
  Discord and webhooks, subject to `notification_minimum_severity` and `notification_environments`.
  PagerDuty doesn't get it, because PagerDuty only takes critical errors. Only the first click
  notifies: a second test error counts as a repeat of the first, so delete the test error before
  testing again.

### How values are shown

| Kind | Shown as |
|---|---|
| Switches | **Enabled** or **Disabled** |
| Numbers | The number, with its unit where it has one: "100 lines", "3600 seconds", "2.0σ" |
| Lists and rules | A count: "3 items", "2 rules" |
| Symbols and strings | The value, such as `:silent` |
| Unset values | **Not set**; an empty list shows **Empty** |
| `issue_tracker_token`, `issue_webhook_secret` | Only **Set** or **Not set** |

> **Webhook URLs and the PagerDuty key are shown in full.** `slack_webhook_url`,
> `discord_webhook_url` and `pagerduty_integration_key` appear as written whenever their channel is
> on, and anyone who can log in to the dashboard can read them. A long URL looks cut off on screen,
> but the full value is in the page. Give the dashboard login only to people who may see these.

### Rows that need a second look

- **`retention_days`** shows the number of days, "Manual cleanup required", and a
  `rails error_dashboard:cleanup_resolved` command. That task is a different rule: it deletes
  *resolved* errors by when they were resolved. Retention deletes errors not seen for that many days,
  and only when you schedule `RetentionCleanupJob`. See
  [Schedule the periodic jobs](../PRODUCTION.md#2-schedule-the-periodic-jobs).
- **`async_adapter`** is only checked for a valid value. RED's jobs run on your app's Active Job
  adapter. See [Run a worker for RED's jobs](../PRODUCTION.md#1-run-a-worker-for-reds-jobs).
- **`digest_frequency`** is shown, but the digest job doesn't read it. Digests go out as often as you
  schedule `ScheduledDigestJob`.
- **Enabled doesn't mean working.** A switch can be on while its jobs never run, or before there is
  enough data to show. To check the setup itself, run `bin/rails error_dashboard:verify`.

---

## Reading the configuration in code

```ruby
config = RailsErrorDashboard.configuration
config.async_logging   # => true
config.retention_days  # => 90
```

There is no JSON endpoint for it. Inspecting the configuration object (`p config`) shows `[FILTERED]`
in place of passwords, tokens, keys and webhook URLs.

---

## Troubleshooting

### The page shows a different value than the initializer

The initializer probably reads an environment variable, and the page shows what that variable held
when the app booted:

```ruby
config.slack_webhook_url = ENV["SLACK_WEBHOOK_URL"]
```

Check the variable in the environment the app runs in, then restart the app.

### A feature shows Enabled but does nothing

- **Jobs aren't running.** Saving errors with `async_logging`, notifications and the periodic jobs
  need a worker. See [Running in Production](../PRODUCTION.md).
- **A channel has no URL.** A channel's row for its URL or key shows **Not set**.
- **Not enough data yet.** Analytics pages say so when they have too little to show.

### You can't open the page

- **401:** the HTTP Basic login is wrong. Check `ERROR_DASHBOARD_USER` and
  `ERROR_DASHBOARD_PASSWORD` in the environment the app runs in; see
  [Dashboard Credentials](CONFIGURATION.md#dashboard-credentials). A browser can keep an old login:
  try a private window.
- **403:** your `authenticate_with` block returned false. If the log has
  `[RailsErrorDashboard] authenticate_with lambda raised`, the block itself fails. See
  [Custom Authentication](CONFIGURATION.md#custom-authentication).

---

## Related Documentation

- **[Configuration Guide](CONFIGURATION.md)** - Every option
- **[Configuration Defaults Reference](CONFIGURATION.md#configuration-defaults-reference)** - All defaults in one table
- **[Running in Production](../PRODUCTION.md)** - Workers and scheduled jobs
