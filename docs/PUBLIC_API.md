---
layout: default
title: "Public API"
permalink: /docs/PUBLIC_API
---

# Public API

This is what 1.x keeps stable. Everything named here follows the [versioning policy](VERSIONING.md): it
changes only in a major version, and a deprecation warns first. Anything not named here is private
and can change in any release; [What's private](#whats-private) spells that out.

The page lists names and links the details, so each fact has one home. A spec compares each list
with the code, so it can't fall behind.

## Configuration options

Set these in `config/initializers/rails_error_dashboard.rb`. Types and defaults are in the
[Configuration Guide](guides/CONFIGURATION.md).

```text
accent_color
app_version
application_name
async_adapter  # deprecated, removed in 2.0
async_logging
authenticate_with
auto_issue_rate_limit_count
auto_issue_rate_limit_window_minutes
baseline_alert_cooldown_minutes
baseline_alert_severities
baseline_alert_threshold_std_devs
breadcrumb_buffer_size
breadcrumb_categories
context_sampling_keep_every
context_sampling_threshold_per_day
crash_capture_path
custom_fingerprint
custom_severity_rules
dashboard_base_url
dashboard_locale
dashboard_password
dashboard_username
database
detect_swallowed_exceptions
digest_frequency
digest_recipients
discord_webhook_url
enable_actioncable_tracking
enable_activestorage_tracking
enable_baseline_alerts
enable_breadcrumbs
enable_co_occurring_errors
enable_coverage_tracking
enable_crash_capture
enable_diagnostic_dump
enable_discord_notifications
enable_email_notifications
enable_error_cascades
enable_error_correlation
enable_error_subscriber
enable_git_blame
enable_instance_variables
enable_internal_logging
enable_issue_tracking
enable_live_updates
enable_llm_observability
enable_local_variables
enable_middleware
enable_missing_translation_tracking
enable_n_plus_one_detection
enable_occurrence_patterns
enable_otel_export
enable_pagerduty_notifications
enable_platform_comparison
enable_rack_attack_tracking
enable_rate_limiting
enable_scheduled_digests
enable_similar_errors
enable_slack_notifications
enable_source_code_integration
enable_storm_protection
enable_system_health
enable_telegram_notifications
enable_webhook_notifications
environment
filter_sensitive_data
git_branch_strategy
git_repository_url
git_sha
ignored_exceptions
instance_variable_filter_patterns
instance_variable_max_count
issue_tracker_api_url
issue_tracker_auto_create_severities
issue_tracker_labels
issue_tracker_provider
issue_tracker_repo
issue_tracker_token
issue_webhook_secret
llm_api_key
llm_max_output_tokens
llm_model
llm_observability_content_capture  # deprecated, removed in 2.0
llm_openai_endpoint
llm_pricing_overrides
llm_provider
llm_system_prompt
llm_timeout_seconds
local_variable_filter_patterns
local_variable_inspect_allowlist
local_variable_inspect_budget_ms
local_variable_max_array_items
local_variable_max_count
local_variable_max_depth
local_variable_max_hash_items
local_variable_max_string_length
log_level
max_backtrace_lines
n_plus_one_threshold
notification_burst_limit
notification_burst_window_seconds
notification_cooldown_minutes
notification_email_from
notification_email_recipients
notification_environments
notification_minimum_severity
notification_threshold_alerts
occurrence_context_limit
only_show_app_code_source
otel_service_name
otel_spans
pagerduty_integration_key
rack_attack_flush_interval
rack_attack_max_cache_size
rate_limit_per_minute
retention_days
sampling_rate
sensitive_data_patterns
slack_webhook_url
source_code_cache_ttl
source_code_context_lines
storm_cooldown_seconds
storm_fingerprint_full_per_minute
storm_flush_interval_seconds
storm_max_tracked_fingerprints
storm_notification
storm_occurrence_sample_keep_every
storm_open_threshold_per_second
storm_shedding_threshold_per_second
swallowed_exception_flush_interval
swallowed_exception_ignore_classes
swallowed_exception_max_cache_size
swallowed_exception_threshold
system_health_queue_stats
system_health_queue_stats_cache_seconds
telegram_api_base_url
telegram_bot_token
telegram_chat_id
total_users_for_impact
use_separate_database
user_model
webhook_signing_secret
webhook_urls
```

## Environment variables

```text
APPLICATION_NAME
APP_ID  # rake task input
APP_NAME  # rake task input
APP_VERSION
BASELINE_ALERT_COOLDOWN
BASELINE_ALERT_THRESHOLD
DASHBOARD_BASE_URL
DAYS  # rake task input
DISCORD_WEBHOOK_URL
ERROR_DASHBOARD_ENVIRONMENT
ERROR_DASHBOARD_NOTIFICATION_ENVIRONMENTS
ERROR_DASHBOARD_PASSWORD
ERROR_DASHBOARD_USER
ERROR_NOTIFICATION_EMAILS
ERROR_NOTIFICATION_FROM
GIT_REPOSITORY_URL
GIT_SHA
HEROKU_SLUG_COMMIT
ISSUE_TRACKER_TOKEN
ISSUE_WEBHOOK_SECRET
NOTE  # rake task input
PAGERDUTY_INTEGRATION_KEY
PERIOD  # rake task input
RED_BOT_TOKEN
RED_LLM_API_KEY
RED_LLM_MODEL
RED_LLM_OPENAI_ENDPOINT
RED_LLM_PROVIDER
RENDER_GIT_COMMIT
SLACK_WEBHOOK_URL
SOLID_QUEUE_CONFIG
TELEGRAM_API_BASE_URL
TELEGRAM_BOT_TOKEN
TELEGRAM_CHAT_ID
USE_SEPARATE_ERROR_DB  # deprecated, removed in 2.0
WEBHOOK_SIGNING_SECRET
WEBHOOK_URLS
```

## Ruby API

The [API Reference](API_REFERENCE.md#ruby-api) covers these in detail.

### Module methods

On `RailsErrorDashboard`.

```text
add_breadcrumb
configuration
configuration=
configure
detected_git_sha
on_critical_error
on_error_logged
on_error_resolved
plugins
register_plugin
resolved_application_name
unregister_plugin
```

### ManualErrorReporter.report

`RailsErrorDashboard::ManualErrorReporter.report` takes these keyword arguments.

```text
error_type  # required
message  # required
backtrace
platform
user_id
request_url
user_agent
ip_address
app_version
metadata
occurred_at
severity
source
```

### Plugin hooks

On `RailsErrorDashboard::Plugin`. See the [Plugin System Guide](PLUGIN_SYSTEM.md).

```text
on_error_logged(error_log)
on_error_muted(error_log)
on_error_recurred(error_log)
on_error_reopened(error_log)
on_error_resolved(error_log)
on_error_unmuted(error_log)
on_error_viewed(error_log)
on_errors_batch_deleted(error_ids)
on_errors_batch_muted(error_logs)
on_errors_batch_resolved(error_logs)
on_errors_batch_unmuted(error_logs)
on_register
```

## Command line

### Generators

```text
rails_error_dashboard:install
rails_error_dashboard:uninstall
```

### Install generator options

```text
--interactive
--slack
--email
--discord
--telegram
--pagerduty
--webhooks
--async_logging
--error_sampling
--separate_database
--database
--baseline_alerts
--similar_errors
--co_occurring_errors
--error_cascades
--error_correlation
--platform_comparison
--occurrence_patterns
--source_code_integration
--git_blame
--breadcrumbs
--system_health
--swallowed_exceptions
--crash_capture
--diagnostic_dump
--quick
```

### Uninstall generator options

```text
--keep_data
--skip_confirmation
--manual_only
```

### Rake tasks

The old `error_dashboard:` names run the same task and print a deprecation first.

```text
rails_error_dashboard:app_stats
rails_error_dashboard:backfill_application
rails_error_dashboard:backfill_environments
rails_error_dashboard:backfill_resolved_at
rails_error_dashboard:cleanup_resolved
rails_error_dashboard:db:drop
rails_error_dashboard:diagnostic_dump
rails_error_dashboard:digest_session_ids
rails_error_dashboard:install:migrations
rails_error_dashboard:list_applications
rails_error_dashboard:retention_cleanup
rails_error_dashboard:scrub_invalid_encoding
rails_error_dashboard:send_digest
rails_error_dashboard:verify
error_dashboard:app_stats  # deprecated, removed in 2.0
error_dashboard:backfill_application  # deprecated, removed in 2.0
error_dashboard:backfill_resolved_at  # deprecated, removed in 2.0
error_dashboard:cleanup_resolved  # deprecated, removed in 2.0
error_dashboard:diagnostic_dump  # deprecated, removed in 2.0
error_dashboard:digest_session_ids  # deprecated, removed in 2.0
error_dashboard:list_applications  # deprecated, removed in 2.0
error_dashboard:retention_cleanup  # deprecated, removed in 2.0
error_dashboard:scrub_invalid_encoding  # deprecated, removed in 2.0
error_dashboard:send_digest  # deprecated, removed in 2.0
error_dashboard:verify  # deprecated, removed in 2.0
```

## URLs

Paths are relative to where you mount the engine. Other systems depend on these three: uptime
monitors, issue trackers' webhooks, and the links in every notification. See the
[API Reference](API_REFERENCE.md#http-routes).

```text
GET /health
POST /webhooks/:provider
GET /errors/:id
```

### Health check fields

`GET /health` answers with these fields. `error` appears only when the health check itself failed.

```text
status
version
timestamp
checks
duration_ms
error
```

### Health checks

Each key of `checks`, with the fields it can answer with. Every check has a `status`. Which of the
others appear depends on the result: `reason`, `skipped` and `error` appear only when there's
something to report.

```text
database: status, adapter, separate_database, tables_present, latency_ms, reason, error
errors: status, last_error_at, last_24h, skipped, error
queue: status, async_logging, adapter, problems, error
storm_protection: status, enabled, state, error
active_storage: status, service, latency_ms, reason, error
```

### Health check statuses

```text
ok
degraded
down
skipped
```

## Integrations

### Webhooks

Everything RED posts to `config.webhook_urls` is in the [Webhook Contract](WEBHOOKS.md).

### OpenTelemetry spans

```text
rails_error_dashboard.capture_error
rails_error_dashboard.breadcrumb_collection
rails_error_dashboard.notification_dispatch
rails_error_dashboard.system_health_snapshot
```

### OpenTelemetry attributes

```text
error.type
error.message
rails_error_dashboard.version
rails_error_dashboard.service_name
rails_error_dashboard.environment
rails_error_dashboard.was_async
rails_error_dashboard.filtered
rails_error_dashboard.storm_degraded
rails_error_dashboard.application
rails_error_dashboard.error_id
rails_error_dashboard.deduplicated
rails_error_dashboard.severity
breadcrumb_count
bytes_serialized_estimate
channels
channel_count
```

## What's private

These can change in any release, without a deprecation:

- Database tables, columns and models.
- Job classes and their arguments.
- Classes and modules not named on this page.
- i18n keys.
- The dashboard's HTML, CSS and JavaScript.
- Every dashboard URL not listed under [URLs](#urls).
