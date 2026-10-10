---
layout: default
title: "Configuration Guide"
order: 1
---

# Configuration Guide

This guide covers all configuration options for Rails Error Dashboard, including advanced features for customization and extensibility.

## Table of Contents

- [Configuration Defaults Reference](#configuration-defaults-reference)
- [Opt-in Feature System](#opt-in-feature-system)
- [Basic Configuration](#basic-configuration)
- [Notification Features](#notification-features)
- [Performance Features](#performance-features)
- [Advanced Analytics Features](#advanced-analytics-features)
- [Source Code Integration](#source-code-integration-new)
- [Local Variable Capture](#local-variable-capture-v040)
- [Instance Variable Capture](#instance-variable-capture-v040)
- [Swallowed Exception Detection](#swallowed-exception-detection-v040)
- [Diagnostic Dump](#diagnostic-dump-v040)
- [Rack Attack Event Tracking](#rack-attack-event-tracking-v040)
- [Process Crash Capture](#process-crash-capture-v040)
- [Custom Severity Classification](#custom-severity-classification)
- [Ignored Exceptions](#ignored-exceptions)
- [Error Sampling](#error-sampling)
- [Storm Protection](#storm-protection)
- [Scheduled Digests](#scheduled-digests)
- [Notification Callbacks](#notification-callbacks)
- [ActiveSupport Notifications](#activesupport-notifications)
- [Backtrace Configuration](#backtrace-configuration)
- [Complete Configuration Example](#complete-configuration-example)

---

## Configuration Defaults Reference

Reference for the configuration options, with their defaults. Not listed here yet: AI help (`llm_*`) and OpenTelemetry export (`enable_otel_export`, `otel_service_name`, `otel_spans`), which the generated initializer documents; [LLM observability](https://github.com/AnjanJ/rails_error_dashboard/blob/main/docs/LLM_OBSERVABILITY.md); coverage tracking; `custom_fingerprint`; and the sensitive-data filter (`filter_sensitive_data`, `sensitive_data_patterns`).

### Authentication & Access

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dashboard_username` | String | `"gandalf"` | Username for HTTP Basic Auth (ENV: `ERROR_DASHBOARD_USER`) |
| `dashboard_password` | String | `"youshallnotpass"` | Password for HTTP Basic Auth (ENV: `ERROR_DASHBOARD_PASSWORD`) |
| `authenticate_with` | Lambda/Proc/Callable | `nil` | Custom auth lambda executed in controller context. When set, replaces HTTP Basic Auth. Return truthy to allow, falsy to deny (403). |
| `user_model` | String | `nil` (auto-detected) | Model name for user associations. The generated initializer sets `"User"` |

### Multi-App Support

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `application_name` | String | Auto-detected | Application identifier (ENV: `APPLICATION_NAME`) |
| `environment` | String | `Rails.env` | Environment errors are attributed to — `production`, `staging`, `uat`, any name (ENV: `ERROR_DASHBOARD_ENVIRONMENT`) |
| `database` | Symbol/String | `nil` | Name of the error database's entry in `config/database.yml`. Used only with `use_separate_database = true`, and then required: boot fails without it. The generated initializer sets `:error_dashboard` |
| `use_separate_database` | Boolean | `false` | Store errors in their own database. ENV: `USE_SEPARATE_ERROR_DB`, which only applies when the initializer doesn't set this option; the generated initializer always sets it |

### Dashboard UI

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `accent_color` | Symbol | `:crimson` | Dashboard accent colour — `:crimson`, `:ruby`, `:ember`, `:violet` |
| `dashboard_locale` | String | `"en"` | Locale the dashboard renders in, independent of the host app's locale. Ships `en`, `de`, `es`, `fr`, `pt-BR`, `ja`, `ru`, `uk`, `pl`, `it`, `zh-CN` — `fr` is **community-reviewed by a native speaker**, and everything but English and French is **machine-translated and unreviewed by a native speaker**, falling back to English per missing key. Users can override it per-session with the language picker. Unknown or wrong-cased values fall back to `"en"`. See [Translations](https://github.com/AnjanJ/rails_error_dashboard/blob/main/docs/guides/TRANSLATIONS.md) |

The dashboard sets its own locale for the duration of each request and restores
the previous value afterwards, so it neither inherits the host app's locale nor
leaks its own back into the host. This matters because Pagy stores its locale in
a thread-local it never resets — without this, a dashboard request landing on a
recycled Puma thread would render in whatever language the host app last used.

### Notifications - Slack

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_slack_notifications` | Boolean | `false` | Enable Slack webhooks |
| `slack_webhook_url` | String | `nil` | Slack webhook URL (ENV: `SLACK_WEBHOOK_URL`) |

### Notifications - Email

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_email_notifications` | Boolean | `false` | Enable email notifications |
| `notification_email_recipients` | Array | `[]` | Email recipients (ENV: `ERROR_NOTIFICATION_EMAILS`, comma-separated) |
| `notification_email_from` | String | `"errors@example.com"` | From address (ENV: `ERROR_NOTIFICATION_FROM`) |
| `dashboard_base_url` | String | `nil` | Base URL for links in emails (ENV: `DASHBOARD_BASE_URL`) |

### Notifications - Discord

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_discord_notifications` | Boolean | `false` | Enable Discord webhooks |
| `discord_webhook_url` | String | `nil` | Discord webhook URL (ENV: `DISCORD_WEBHOOK_URL`) |

### Notifications - PagerDuty

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_pagerduty_notifications` | Boolean | `false` | Enable PagerDuty (critical errors only) |
| `pagerduty_integration_key` | String | `nil` | PagerDuty integration key (ENV: `PAGERDUTY_INTEGRATION_KEY`) |

### Notifications - Webhooks

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_webhook_notifications` | Boolean | `false` | Enable custom webhooks |
| `webhook_urls` | Array | `[]` | Custom webhook URLs (ENV: `WEBHOOK_URLS`, comma-separated) |
| `webhook_signing_secret` | String | `nil` | HMAC-SHA256 signing secret for outbound webhooks (ENV: `WEBHOOK_SIGNING_SECRET`). When set, every POST to `webhook_urls` carries `X-Error-Dashboard-Signature-256` and `X-Error-Dashboard-Timestamp` headers — see the [Notifications Guide](/rails_error_dashboard/docs/guides/notifications/#signing-hmac-sha256) |

### Notifications - Environment Filter (v0.11.0)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `notification_environments` | Array | `nil` (all) | Only notify for these environments; applies to every channel plus storm and baseline alerts. An Array of Strings: Symbols fail boot (ENV: `ERROR_DASHBOARD_NOTIFICATION_ENVIRONMENTS`, comma-separated) |

### Notifications - Throttling

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `notification_minimum_severity` | Symbol | `:low` | For a new or reopened error, skip notifications below this severity (`:low`, `:medium`, `:high`, `:critical`). Milestone notifications (`notification_threshold_alerts`) are sent at any severity |
| `notification_cooldown_minutes` | Integer | `5` | Minimum gap between notifications for one error that keeps being reopened. Claimed in the database (`error_logs.last_notified_at`), so it holds across every worker and job process. `0` disables it. First occurrences and threshold milestones are never held back by it |
| `notification_threshold_alerts` | Array | `[10, 50, 100, 500, 1000]` | Occurrence counts that send a milestone notification |
| `notification_burst_limit` | Integer | `10` | Most notifications for **new** errors per window, **per process**. When it is exceeded, one summary message replaces the rest of the window. Every error is still recorded. `0` disables the cap |
| `notification_burst_window_seconds` | Integer | `60` | Length of that window |

The burst cap exists for the bad deploy that produces hundreds of *distinct* new errors: each is a first occurrence, so the per-error cooldown never applies to it. The cap is per process, so the worst case is `notification_burst_limit` × the number of processes per window. The summary goes to Slack, Discord and custom webhooks (event `new_error_notifications_suppressed`). A deployment with only email or PagerDuty enabled has no channel for it: the cap still applies and the summary is written to the Rails log at `warn`. With no notification channel enabled at all, the cap does nothing.

### Notifications - Scheduled Digests

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_scheduled_digests` | Boolean | `false` | Send a summary email of recent errors. Sent only when `RailsErrorDashboard::ScheduledDigestJob` runs, which you schedule: see [Scheduled Digests](#scheduled-digests) |
| `digest_recipients` | Array | `nil` | Who receives it. Falls back to `notification_email_recipients`; with neither, nothing is sent |
| `digest_frequency` | Symbol | `:daily` | Shown on the Settings page only. The job's `period:` argument and your schedule decide what is sent and when |

### Storm Protection Options

On by default. See [Storm Protection](#storm-protection) below.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_storm_protection` | Boolean | `true` | Limit RED's own database writes during an error flood |
| `storm_fingerprint_full_per_minute` | Integer | `30` | Full-detail captures per error per minute |
| `storm_occurrence_sample_keep_every` | Integer | `10` | Past that cap, keep every Nth occurrence row |
| `storm_shedding_threshold_per_second` | Integer | `10` | Errors per second at which RED stops storing per-event context |
| `storm_open_threshold_per_second` | Integer | `50` | Errors per second at which RED only counts. Must be at least `storm_shedding_threshold_per_second` |
| `storm_cooldown_seconds` | Integer | `60` | Time spent only counting before RED tries full capture again |
| `storm_max_tracked_fingerprints` | Integer | `1000` | Errors tracked in memory; the rest share one overflow count |
| `storm_flush_interval_seconds` | Integer | `30` | How often buffered counts are written to the error records |
| `storm_notification` | Boolean | `true` | Send one "storm in progress" notification per storm. Per-error notifications pause during a storm either way |
| `auto_issue_rate_limit_count` | Integer | `5` | Most issues created automatically per window, during a storm or not (only while storm protection is on) |
| `auto_issue_rate_limit_window_minutes` | Integer | `10` | Length of that window |
| `context_sampling_threshold_per_day` | Integer | `25` | Full-context captures per error per day. After that, context is kept every Nth time |
| `context_sampling_keep_every` | Integer | `10` | That N |

### Core Features

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_middleware` | Boolean | `true` | Enable error catching middleware |
| `enable_error_subscriber` | Boolean | `true` | Enable Rails.error subscriber |
| `retention_days` | Integer | `90` | Delete an error once it has **not been seen** for this many days (by `last_seen_at`, not by when it first occurred, so an error that is still happening is never deleted). Diagnostic dumps and swallowed-exception records older than this are pruned too. Deletes only when `RailsErrorDashboard::RetentionCleanupJob` runs, and nothing in the gem schedules it: see [Schedule the periodic jobs](/rails_error_dashboard/docs/production/#2-schedule-the-periodic-jobs) |

### Error Classification

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `custom_severity_rules` | Hash | `{}` | Exact error class name (a String) → severity. See [Custom Severity Classification](#custom-severity-classification) |
| `ignored_exceptions` | Array | `[]` | Exceptions to ignore: class-name Strings or Class objects (both cover subclasses), or Regexps matched against the class name. Class objects are matched since 0.14.4 |

### Performance Optimization

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `async_logging` | Boolean | `false` | Save errors in a background job. The generated initializer sets `true`. Needs a worker: see [Run a worker](/rails_error_dashboard/docs/production/#1-run-a-worker-for-reds-jobs) |
| `async_adapter` | Symbol | `:sidekiq` | Only checked for a valid value (`:sidekiq`, `:solid_queue`, `:async`). It doesn't choose the backend: RED's jobs run on your app's `config.active_job.queue_adapter` |
| `sampling_rate` | Float | `1.0` | Fraction of non-critical errors to log, from 0.0 to 1.0. Critical errors are always logged. Outside that range, boot fails |
| `max_backtrace_lines` | Integer | `100` | Maximum backtrace lines to store |

### Rate Limiting

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_rate_limiting` | Boolean | `false` | Rate-limit requests to the dashboard, per IP (opt-in). Counts are kept in `Rails.cache` |
| `rate_limit_per_minute` | Integer | `300` | Most requests per minute, per IP and per dashboard path. Applied since 0.14.4 (before that, ignored, with 300 fixed) |

### Enhanced Metrics

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `app_version` | String | `nil` | Application version. When nil: ENV `APP_VERSION`, then a `VERSION` file in the app root |
| `git_sha` | String | `nil` | Git commit SHA. When nil: ENV `GIT_SHA`, `HEROKU_SLUG_COMMIT` or `RENDER_GIT_COMMIT`, then the app's `.git` directory |
| `git_repository_url` | String | `nil` | Git repository URL for commit links (ENV: `GIT_REPOSITORY_URL`) |
| `total_users_for_impact` | Integer | `nil` | Total users for impact % calculation (auto-detected if nil) |

### Advanced Analytics - Error Analysis

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_similar_errors` | Boolean | `false` | Fuzzy error matching with Jaccard/Levenshtein similarity |
| `enable_co_occurring_errors` | Boolean | `false` | Detect errors happening together |
| `enable_error_cascades` | Boolean | `false` | Detect parent→child error relationships |
| `enable_error_correlation` | Boolean | `false` | Version/user/time correlation analysis |
| `enable_platform_comparison` | Boolean | `false` | iOS vs Android vs API health comparison |
| `enable_occurrence_patterns` | Boolean | `false` | Cyclical and burst pattern detection |

### Advanced Analytics - Baseline Monitoring

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_baseline_alerts` | Boolean | `false` | Statistical anomaly detection and alerts |
| `baseline_alert_threshold_std_devs` | Float | `2.0` | Standard deviations above the baseline at which a count is an anomaly (ENV: `BASELINE_ALERT_THRESHOLD`) |
| `baseline_alert_severities` | Array | `[:critical, :high]` | Error severities that send a baseline alert. Since 0.14.4 this is the error's own severity, so alerts start at the threshold; before, it was compared with the anomaly's level and the default started at 3 standard deviations. Needs `BaselineCalculationJob`: see [Baseline Anomaly Alerts](#baseline-anomaly-alerts) |
| `baseline_alert_cooldown_minutes` | Integer | `120` | Minutes between alerts for same error (ENV: `BASELINE_ALERT_COOLDOWN`) |

### Source Code Integration (NEW!)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_source_code_integration` | Boolean | `false` | View source code directly in error details |
| `source_code_context_lines` | Integer | `5` | Lines of context before/after error line |
| `enable_git_blame` | Boolean | `false` | Show git blame info (author, commit, timestamp) |
| `source_code_cache_ttl` | Integer | `3600` | Cache TTL in seconds (1 hour default) |
| `only_show_app_code_source` | Boolean | `true` | Hide gem/vendor code (security) |
| `git_branch_strategy` | Symbol | `:commit_sha` | Branch strategy (`:commit_sha`, `:current_branch`, `:main`) |

### Breadcrumbs — Request Activity Trail (NEW!)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_breadcrumbs` | Boolean | `false` | Capture request activity trail (SQL, controller, cache, etc.) |
| `breadcrumb_buffer_size` | Integer | `40` | Max breadcrumbs per request (ring buffer) |
| `breadcrumb_categories` | Array/nil | `nil` | Categories to capture (`nil` = all; or a subset of `[:sql, :controller, :cache, :job, :mailer, :deprecation, :custom, :action_cable, :active_storage, :rack_attack, :llm, :llm_tool]`). Symbols only: with Strings, no breadcrumb matches |
| `enable_n_plus_one_detection` | Boolean | `true` | Detect N+1 query patterns in SQL breadcrumbs (display-time analysis) |
| `n_plus_one_threshold` | Integer | `3` | Min repetitions to flag as N+1 (min: 2) |

### System Health Snapshot

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_system_health` | Boolean | `false` | Capture GC, memory, threads, connection pool, RubyVM cache, YJIT stats at error time |
| `system_health_queue_stats` | Boolean | `true` | Include job-queue depth counts (Sidekiq/Solid Queue/GoodJob) in the snapshot. These are queries against the queue store, not in-process reads |
| `system_health_queue_stats_cache_seconds` | Integer | `10` | Reuse the queue counts for this long per process, so an error burst runs them once per interval. `0` runs them on every error |

### Local Variable Capture (v0.4.0)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_local_variables` | Boolean | `false` | Capture local variables at exception raise point via TracePoint |
| `local_variable_max_count` | Integer | `15` | Maximum number of local variables to capture per exception |
| `local_variable_max_depth` | Integer | `3` | Maximum object nesting depth for serialization |
| `local_variable_max_string_length` | Integer | `200` | Truncate string values beyond this length |
| `local_variable_max_array_items` | Integer | `10` | Maximum array items to serialize |
| `local_variable_max_hash_items` | Integer | `20` | Maximum hash entries to serialize |
| `local_variable_filter_patterns` | Array | `[]` | Additional sensitive variable name patterns to filter (beyond Rails `filter_parameters`) |
| `local_variable_inspect_allowlist` | Array | `[]` | Class names whose `#inspect` may run. Empty by default: an unknown object gets a safe structural summary instead, because `#inspect` is arbitrary application code on the failure path. **Adding a type here opts it in to unbounded execution** — there is no safe way to interrupt arbitrary Ruby mid-call. Structs are serialized member-wise and need no entry. |
| `local_variable_inspect_budget_ms` | Integer | `5` | Wall-clock threshold for an allowlisted `#inspect`. Output-selection only: it decides whether the result is *stored*, after the call has already completed. It does not bound execution. |

### Instance Variable Capture (v0.4.0)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_instance_variables` | Boolean | `false` | Capture instance variables from the object that raised the exception |
| `instance_variable_max_count` | Integer | `20` | Maximum instance variables to capture per exception |
| `instance_variable_filter_patterns` | Array | `[]` | Additional sensitive instance variable name patterns to filter |

### Swallowed Exception Detection (v0.4.0)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `detect_swallowed_exceptions` | Boolean | `false` | Detect exceptions that are raised but silently rescued. **Requires Ruby 3.3+** |
| `swallowed_exception_max_cache_size` | Integer | `1000` | Maximum entries per thread-local raise/rescue tracking cache |
| `swallowed_exception_flush_interval` | Integer | `60` | Seconds between database flushes of accumulated data |
| `swallowed_exception_threshold` | Float | `0.95` | Rescue ratio (0.0-1.0) to flag a location as "swallowed" |
| `swallowed_exception_ignore_classes` | Array | `[]` | Additional exception classes to skip during tracking |

### Diagnostic Dump (v0.4.0)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_diagnostic_dump` | Boolean | `false` | Enable on-demand system state snapshots via dashboard or rake task |

### Rack Attack Event Tracking (v0.4.0)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_rack_attack_tracking` | Boolean | `false` | Record Rack::Attack throttle/blocklist/track events to their own table |
| `rack_attack_max_cache_size` | Integer | `1000` | Max buffered event keys per thread before LRU eviction |
| `rack_attack_flush_interval` | Integer | `5` | Maximum age of buffered events before they are written to the database |

### Missing Translation Tracking

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_missing_translation_tracking` | Boolean | `false` | Count the app's I18n misses by locale and key in their own table (`rails rails_error_dashboard:install:migrations` adds it). Wraps `I18n.exception_handler`, delegating to the handler the app already had; does not require breadcrumbs |

### ActionCable Connection Monitoring (v0.5.0)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_actioncable_tracking` | Boolean | `false` | Track ActionCable channel actions, transmissions, and subscription events as breadcrumbs. Requires `enable_breadcrumbs = true` |

### ActiveStorage Service Health (v0.5+)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_activestorage_tracking` | Boolean | `false` | Track ActiveStorage service operations (uploads, downloads, deletes, existence checks) as breadcrumbs. Works with any backend (Disk, S3, GCS, Azure). Requires `enable_breadcrumbs = true` |

### Issue Tracking — GitHub/GitLab/Codeberg (v0.5.8+)

One switch enables all platform integration: issue creation, auto-create, lifecycle sync, platform state mirroring, and comment display. When enabled, workflow controls (Resolve, Assign, Priority) are replaced by platform state.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_issue_tracking` | Boolean | `false` | Master switch — enables all issue tracking features |
| `issue_tracker_token` | String/Lambda | `ENV["RED_BOT_TOKEN"] \|\| ENV["ISSUE_TRACKER_TOKEN"]` | API token. Supports lambda: `-> { Rails.application.credentials.dig(:github, :token) }` |
| `issue_tracker_provider` | Symbol | auto-detected | `:github`, `:gitlab`, `:codeberg` or `:linear`. Auto-detected from `git_repository_url`, except `:linear`, which you set yourself |
| `issue_tracker_repo` | String | auto-detected | `"owner/repo"`. Auto-extracted from `git_repository_url` |
| `issue_tracker_labels` | Array | `["bug"]` | Labels added to new issues |
| `issue_tracker_api_url` | String | auto-detected | Custom API URL for self-hosted GitLab/Gitea/Forgejo |
| `issue_tracker_auto_create_severities` | Array | `[:critical, :high]` | Auto-create issues for these severities |
| `issue_webhook_secret` | String | `ENV["ISSUE_WEBHOOK_SECRET"]` | HMAC secret — webhooks activate when set |

Minimal setup:

```ruby
config.enable_issue_tracking = true
config.issue_tracker_token = ENV["RED_BOT_TOKEN"]
```

### Process Crash Capture (v0.4.0)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_crash_capture` | Boolean | `false` | Capture unhandled exceptions that crash the Ruby process via at_exit hook |
| `crash_capture_path` | String | `nil` | Directory for crash files. If nil, uses `Dir.tmpdir`. Created if missing |

### Internal Logging & Debugging

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_internal_logging` | Boolean | `false` | Turns on RED's debug, info and warn messages, at or above `log_level` |
| `log_level` | Symbol | `:silent` | `:debug`, `:info`, `:warn`, `:error`, `:fatal` or `:silent`. RED's error messages are logged at `:error` and below, with or without `enable_internal_logging`. The default, `:silent`, silences RED's internal logger. Some messages, such as job failures and boot warnings, go straight to the Rails log whatever this says |

### Read-Only Attributes

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `notification_callbacks` | Hash | See below | Notification callback registry (use helper methods, not direct assignment) |

---

### Environment Variables Quick Reference

All environment variables that can be used instead of or alongside configuration:

```bash
# Authentication. Not needed in development and test. Everywhere else,
# set both (see Dashboard Credentials). Generate the password with:
#   openssl rand -base64 32
# ERROR_DASHBOARD_USER=admin
# ERROR_DASHBOARD_PASSWORD=

# Multi-App
APPLICATION_NAME=my-api
ERROR_DASHBOARD_ENVIRONMENT=staging                 # Defaults to Rails.env
ERROR_DASHBOARD_NOTIFICATION_ENVIRONMENTS=production  # Comma-separated; unset = notify everywhere

# Database: only when the initializer doesn't set use_separate_database
# (the generated one does), and config.database must be set too
USE_SEPARATE_ERROR_DB=true

# Notifications
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...
ERROR_NOTIFICATION_EMAILS=team@example.com,ops@example.com
ERROR_NOTIFICATION_FROM=errors@myapp.com
DASHBOARD_BASE_URL=https://dashboard.example.com
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
PAGERDUTY_INTEGRATION_KEY=abc123...
WEBHOOK_URLS=https://hook1.example.com,https://hook2.example.com
WEBHOOK_SIGNING_SECRET=...     # Optional: HMAC-SHA256 signature headers on every custom webhook

# Enhanced Metrics
APP_VERSION=1.2.3
GIT_SHA=abc123def456
GIT_REPOSITORY_URL=https://github.com/user/repo

# Baseline Alerts
BASELINE_ALERT_THRESHOLD=2.0  # Standard deviations
BASELINE_ALERT_COOLDOWN=120   # Minutes

# Issue tracking
RED_BOT_TOKEN=...             # or ISSUE_TRACKER_TOKEN
ISSUE_WEBHOOK_SECRET=...

# AI help
RED_LLM_PROVIDER=openai       # openai or anthropic; any other value fails boot
RED_LLM_API_KEY=...
RED_LLM_MODEL=gpt-5
RED_LLM_OPENAI_ENDPOINT=auto  # auto, responses or chat_completions

# Never set this at runtime: it turns off error capture. Docker images set it
# on the assets:precompile command only (see Running in Production).
# SECRET_KEY_BASE_DUMMY=1
```

---

### Practical Defaults Guidance

**For Development:**
```ruby
config.async_logging = false          # Sync for easier debugging
config.sampling_rate = 1.0             # Log all errors
config.enable_internal_logging = true  # See what's happening
config.log_level = :debug             # Verbose logging
```

**For Production (Low Traffic):**
```ruby
config.async_logging = true           # Background jobs (run a worker)
config.sampling_rate = 1.0            # Log all errors
config.retention_days = 90            # 3 months (schedule RetentionCleanupJob)
config.max_backtrace_lines = 100      # The default
```

**For Production (High Traffic >1000 errors/day):**
```ruby
config.async_logging = true           # REQUIRED (run a worker)
config.sampling_rate = 0.1            # 10% (critical always logged)
config.retention_days = 30            # 1 month (schedule RetentionCleanupJob)
config.max_backtrace_lines = 20       # Reduce storage
config.use_separate_database = true   # Isolate errors
config.database = :error_dashboard    # Its config/database.yml entry
```

---

## Opt-in Feature System

Rails Error Dashboard uses an **opt-in architecture**. Core features are always enabled, while everything else is disabled by default.

**Tier 1 Features (Always ON):**
- ✅ Error capture (controllers, jobs, middleware)
- ✅ Dashboard UI with search and filtering
- ✅ Real-time updates via Turbo Streams (needs Action Cable with a cross-process adapter, such as Solid Cable or Redis)
- ✅ Analytics and trend charts

**Optional Features (17 total):**
- 📧 **5 Notification Channels** (Slack, Email, Discord, PagerDuty, Webhooks)
- ⚡ **3 Performance Features** (Async Logging, Error Sampling, Separate Database)
- 📊 **7 Advanced Analytics** (Baseline Alerts, Fuzzy Matching, Co-occurring Errors, Error Cascades, Correlation, Platform Comparison, Occurrence Patterns)
- 🔍 **2 Developer Tools** (Source Code Integration, Git Blame)

All features can be enabled during installation via the interactive installer, or toggled on/off at any time in the initializer.

---

## Basic Configuration

Create an initializer at `config/initializers/rails_error_dashboard.rb`:

```ruby
RailsErrorDashboard.configure do |config|
  # Dashboard credentials come from the ERROR_DASHBOARD_USER and
  # ERROR_DASHBOARD_PASSWORD environment variables. Don't set them here.

  # Data retention (days)
  config.retention_days = 90

  # User model for error association
  config.user_model = "User"

  # Enable/disable middleware and error subscriber
  config.enable_middleware = true
  config.enable_error_subscriber = true
end
```

### Dashboard Credentials

Unless you configure `authenticate_with` (see [Custom Authentication](#custom-authentication)), the dashboard is protected by HTTP Basic Auth. The gem reads the credentials from two environment variables itself, so you don't need to set them in the initializer:

| Variable | Default |
|----------|---------|
| `ERROR_DASHBOARD_USER` | `gandalf` |
| `ERROR_DASHBOARD_PASSWORD` | `youshallnotpass` |

**In development and test**, the defaults work. There is nothing to set.

**In every other environment** (`production`, `staging`, `uat`, or any other name), the defaults are refused, because they are published. Set both variables before you deploy:

```bash
# Generate a strong password
openssl rand -base64 32
```

Put the values wherever your platform keeps secrets or environment variables: Kamal secrets, Heroku config vars, Fly.io secrets, Render environment variables, or the `environment:` section of a Compose file. Don't commit them.

If you set only `ERROR_DASHBOARD_PASSWORD`, the username stays `gandalf`. That works, but set both. If you set only `ERROR_DASHBOARD_USER`, the password stays the published default and the app refuses to boot.

#### What is checked at boot

Outside development and test, the app refuses to boot and raises `RailsErrorDashboard::ConfigurationError` when either of these is true:

- the username or password is blank, including whitespace only;
- the password is the published default (`youshallnotpass`) and did not come from `ERROR_DASHBOARD_PASSWORD`.

The message says which one it was. The login applies the same rule on every request, so these credentials are refused even when the boot check is skipped.

The check runs every time the app boots in that environment, which includes `bin/rails db:migrate`, `bin/rails console` and `bin/rails assets:precompile`. So the two variables must also be present wherever those commands run: a release phase, a migration job, a one-off console.

Two exceptions:

- **Docker asset builds.** A build step has no secrets. When `SECRET_KEY_BASE_DUMMY=1` is set, the check is skipped. The Dockerfile that Rails 7.1+ generates already runs `SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile`. If yours precompiles without it, add it. Set it on that command only, never in the runtime environment: while it is set, RED skips its error subscriber and captures no errors at all. (It wouldn't reopen the default credentials, because the login still refuses them.)
- **A deliberately public dashboard.** Setting `ERROR_DASHBOARD_PASSWORD=youshallnotpass` explicitly counts as a choice, and is allowed. That is how the public demo runs. Never do it for an app with real data.

#### Patterns to avoid

| In the initializer | What goes wrong |
|--------------------|-----------------|
| `config.dashboard_password = ENV.fetch("ERROR_DASHBOARD_PASSWORD", "changeme")` | If the variable is missing, the app boots with `changeme`. The boot check only knows the gem's own default, so it can't catch this. |
| `config.dashboard_password = "s3cret"` | Hardcoded credentials end up in source control. |
| `config.dashboard_username = ENV["ERROR_DASHBOARD_USER"]` | Where the variable is unset, the value is `nil`. In development every login is then denied; elsewhere the app refuses to boot. |
| `config.dashboard_password = ENV.fetch("ERROR_DASHBOARD_PASSWORD")` | Raises `KeyError` wherever the variable is unset, including development and CI. |
| `config.username = ...` or `config.password = ...` | These settings don't exist (`NoMethodError`). The names are `dashboard_username` and `dashboard_password`. |

`config.authenticate_with = false` does not turn authentication off. Any falsy value, including `Rails.env.production? && -> { ... }` outside production, falls back to HTTP Basic Auth.

#### Using Rails credentials instead

```ruby
RailsErrorDashboard.configure do |config|
  # Development and test keep the built-in defaults.
  unless Rails.env.development? || Rails.env.test?
    config.dashboard_username = Rails.application.credentials.dig(:error_dashboard, :username)
    config.dashboard_password = Rails.application.credentials.dig(:error_dashboard, :password)
  end
end
```

If an entry is missing, its value is `nil` and the app refuses to boot, saying the credentials are blank.

#### Checking your setup

`bin/rails error_dashboard:verify` reports whether the app is using custom, default or blank credentials, using the same rule as the boot check.

#### Upgrading to 0.14.2

0.14.2 closed several ways around the boot check ([GHSA-qh4g-qc9x-9f83](https://github.com/AnjanJ/rails_error_dashboard/security/advisories/GHSA-qh4g-qc9x-9f83)). An app that relied on one of them now refuses to boot outside development and test. The common causes are:

- only `ERROR_DASHBOARD_USER` was set;
- the initializer hardcoded the default password;
- a variable was passed through empty, for example by a Compose file;
- `authenticate_with` evaluated to `false`.

To fix it, set both variables to real values and make sure the initializer doesn't overwrite them, or configure an `authenticate_with` lambda.

### Custom Authentication

If you use Devise, Warden, or any other auth system, you can replace HTTP Basic Auth with a lambda that runs in controller context via `instance_exec`:

```ruby
RailsErrorDashboard.configure do |config|
  # Devise/Warden — use warden directly (recommended)
  config.authenticate_with = -> {
    if warden.authenticated?
      true
    else
      redirect_to main_app.new_user_session_path, allow_other_host: true
    end
  }

  # Warden with admin scope
  config.authenticate_with = -> { warden.authenticated?(:admin) }

  # Session-based
  config.authenticate_with = -> { session[:dashboard_admin] == true }
end
```

> **Important: Engine controller context.** The lambda runs inside the engine's controller, which inherits from `ActionController::Base` — not your app's `ApplicationController`. This means Devise helpers like `current_user` and `authenticate_user!` are **not available**. Use `warden` (the underlying Rack middleware) instead:
>
> | Works | Doesn't work |
> |-------|-------------|
> | `warden.authenticated?` | `current_user` |
> | `warden.user` | `authenticate_user!` |
> | `warden.authenticate(:scope => :user)` | `user_signed_in?` |
> | `session`, `cookies`, `request`, `params` | Devise helper methods |

**How it works:**
- The lambda has access to `warden`, `session`, `request`, `params`, `cookies`, `redirect_to`, etc.
- **Truthy return** → access granted
- **Falsy return** (including `nil`) → 403 Forbidden
- **Lambda raises** → rescued, logged, 403 (fail closed)
- **Lambda calls `redirect_to`** → redirect honored (e.g. to your login page)
- **`authenticate_with` is `nil`** (the default) **or `false`** → HTTP Basic Auth is used (see [Dashboard Credentials](#dashboard-credentials))

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
  # Optional: sign every POST (HMAC-SHA256 over timestamp + body) so the
  # receiver can reject forged or replayed requests.
  config.webhook_signing_secret = ENV['WEBHOOK_SIGNING_SECRET']
end
```

**Dashboard Base URL** (for notification links):
```ruby
config.dashboard_base_url = ENV['DASHBOARD_BASE_URL']  # e.g., "https://yourapp.com"
```

See [Notifications Guide](/rails_error_dashboard/docs/guides/notifications/) for detailed setup instructions.

---

## Performance Features

Optimize performance and reduce database load with these features.

### Async Error Logging

Save errors in a background job, so the request that raised them doesn't wait for the database
write. The generated initializer turns this on.

```ruby
RailsErrorDashboard.configure do |config|
  config.async_logging = true
end
```

The job runs on your app's Active Job adapter (`config.active_job.queue_adapter`): Solid Queue
(the default since Rails 8.0), Sidekiq, GoodJob, or Rails' in-process `:async` adapter. RED's
`config.async_adapter` is only checked for a valid value; it doesn't choose the backend.

A worker has to process RED's two queues, `default` and `error_notifications`. Without a worker,
set `config.async_logging = false`; notifications still need one. See [Run a worker for RED's jobs](/rails_error_dashboard/docs/production/#1-run-a-worker-for-reds-jobs).

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
  config.database = :error_dashboard  # must match an entry in config/database.yml
end
```

Boot fails if `config.database` is missing. Every environment the app boots in also needs that
entry in `config/database.yml`. See the [Database Options Guide](/rails_error_dashboard/docs/guides/database-options/) for setup instructions.

---

## Advanced Analytics Features

Powerful analytics features for deep error insights, all disabled by default.

### Baseline Anomaly Alerts

Automatically detect when error rates exceed normal patterns using statistical analysis.

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_baseline_alerts = true
  config.baseline_alert_threshold_std_devs = 2.0  # An anomaly starts 2 std devs above baseline
  config.baseline_alert_severities = [:critical, :high]  # Error severities that alert
  config.baseline_alert_cooldown_minutes = 120  # 2 hours between alerts for same error
end
```

Nothing alerts until `RailsErrorDashboard::BaselineCalculationJob` has calculated the baselines,
and nothing in the gem schedules it. Run it daily: see
[Schedule the periodic jobs](/rails_error_dashboard/docs/production/#2-schedule-the-periodic-jobs).

`baseline_alert_severities` lists error severities: an anomaly in a `:critical` or `:high` error
alerts as soon as it passes the threshold. Before 0.14.4 the option was compared with the anomaly's
level (elevated, high, critical) instead, so with the defaults alerts started at 3 standard
deviations, and `:medium` or `:low` never matched. PagerDuty still receives only anomalies 2 or
more standard deviations past the threshold (the `:critical` level).

See [Baseline Monitoring Guide](/rails_error_dashboard/docs/features/baseline-monitoring/) for details.

### Fuzzy Error Matching

Find similar errors even with different error_hashes using backtrace signatures and message similarity.

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_similar_errors = true
end
```

See [Advanced Error Grouping Guide](/rails_error_dashboard/docs/features/advanced-error-grouping/) for details.

### Co-occurring Errors

Detect errors that happen together in time (within 5-minute windows).

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_co_occurring_errors = true
end
```

See [Advanced Error Grouping Guide](/rails_error_dashboard/docs/features/advanced-error-grouping/) for details.

### Error Cascades

Identify parent→child error relationships (error A causes error B).

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_error_cascades = true
end
```

See [Advanced Error Grouping Guide](/rails_error_dashboard/docs/features/advanced-error-grouping/) for details.

### Error Correlation

Correlate errors with app versions, users, and time patterns.

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_error_correlation = true
end
```

See [Error Correlation Guide](/rails_error_dashboard/docs/features/error-correlation/) for details.

### Platform Comparison

Compare iOS vs Android vs API health metrics and platform-specific error rates (a desktop browser request is classed as API; `Web` only appears when you report it manually).

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_platform_comparison = true
end
```

See [Platform Comparison Guide](/rails_error_dashboard/docs/features/platform-comparison/) for details.

### Occurrence Patterns

Detect cyclical patterns (daily/weekly rhythms) and error bursts.

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_occurrence_patterns = true
end
```

See [Occurrence Patterns Guide](/rails_error_dashboard/docs/features/occurrence-patterns/) for details.

---

## Source Code Integration (NEW!)

View source code directly in the error dashboard with git blame information and repository links.

### Basic Configuration

```ruby
RailsErrorDashboard.configure do |config|
  # Enable source code viewer
  config.enable_source_code_integration = true

  # Optional: Enable git blame integration
  config.enable_git_blame = true
end
```

### Advanced Configuration

```ruby
RailsErrorDashboard.configure do |config|
  # Enable source code viewer
  config.enable_source_code_integration = true

  # Enable git blame
  config.enable_git_blame = true

  # Context lines (±N lines around error)
  config.source_code_context_lines = 5  # Default: 5

  # Cache TTL in seconds
  config.source_code_cache_ttl = 3600  # Default: 1 hour

  # Security: only show app code (hide gems/vendor)
  config.only_show_app_code_source = true  # Default: true

  # Branch strategy for repository links
  config.git_branch_strategy = :commit_sha  # Options: :commit_sha, :current_branch, :main
end
```

### Features

- **Source Code Viewer**: View actual source code lines around the error
- **Git Blame Integration**: See who last modified the code and when
- **Repository Links**: Direct links to GitHub, GitLab, or Bitbucket
- **Repository URL**: set `config.git_repository_url` (or `GIT_REPOSITORY_URL`); it isn't read from your git remote
- **Security**: Only reads files within application root directory

### Requirements

- Application must be a git repository
- Git must be installed (for git blame functionality)
- Dashboard must have read access to application source files

### Use Cases

```ruby
# Development: Full visibility
config.enable_source_code_integration = true
config.enable_git_blame = true

# Production: Source code only (no git blame for performance)
config.enable_source_code_integration = true
config.enable_git_blame = false

# Staging: Enable both for debugging
if Rails.env.staging?
  config.enable_source_code_integration = true
  config.enable_git_blame = true
end
```

### Privacy & Security

- **Self-hosted**: Source code never leaves your infrastructure
- **Read-only**: Dashboard only reads files, never modifies
- **Path validation**: Only files within app root can be accessed
- **No external calls**: All processing happens locally

---

## Breadcrumbs — Request Activity Trail (NEW!)

Breadcrumbs capture a timeline of events (SQL queries, controller actions, cache operations, etc.) during a request, then store them with the error for instant debugging context.

### Basic Configuration

```ruby
RailsErrorDashboard.configure do |config|
  # Enable breadcrumbs
  config.enable_breadcrumbs = true
end
```

### Advanced Configuration

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_breadcrumbs = true

  # Max events per request (default: 40, ring buffer drops oldest when full)
  config.breadcrumb_buffer_size = 40

  # Limit which categories are captured (default: nil = all)
  # Options: :sql, :controller, :cache, :job, :mailer, :deprecation, :custom,
  # :action_cable, :active_storage, :rack_attack, :llm, :llm_tool (Symbols, not Strings)
  config.breadcrumb_categories = [ :sql, :controller ]  # Only SQL and controller events

  # N+1 query detection (analyzes SQL breadcrumbs at display time)
  config.enable_n_plus_one_detection = true  # Default: true
  config.n_plus_one_threshold = 3            # Min repetitions to flag (default: 3, min: 2)
end
```

### Manual Breadcrumbs

Add custom breadcrumbs from anywhere in your application code:

```ruby
RailsErrorDashboard.add_breadcrumb("checkout started", { cart_id: 123 })
RailsErrorDashboard.add_breadcrumb("payment processed", { provider: "stripe", amount: 99.99 })
```

### Captured Events

| Event | Category | What's Captured |
|-------|----------|----------------|
| `sql.active_record` | `sql` | SQL query (first 200 chars) + duration. Skips SCHEMA queries and internal gem queries |
| `process_action.action_controller` | `controller` | `ControllerName#action` + duration |
| `cache_read.active_support` | `cache` | `cache read: key` |
| `cache_write.active_support` | `cache` | `cache write: key` |
| `perform.active_job` | `job` | Job class name + duration |
| `deliver.action_mailer` | `mailer` | `MailerClass to: [recipients]` |
| `deprecation.rails` | `deprecation` | Deprecation warning message + caller location |

### N+1 Query Detection

When breadcrumbs and N+1 detection are both enabled, the error detail page automatically analyzes SQL breadcrumbs for repeated query patterns. A yellow warning card appears when the same normalized query shape is repeated above the threshold:

```ruby
config.enable_n_plus_one_detection = true  # ON by default
config.n_plus_one_threshold = 3            # Flag when same pattern appears 3+ times
```

The detector normalizes SQL by replacing literal values (`WHERE id = 42` → `WHERE id = ?`) and IN lists (`IN (1, 2, 3)` → `IN (?)`) while preserving PostgreSQL double-quoted identifiers. Analysis runs at display time only — zero overhead on requests.

### Use Cases

```ruby
# Development: Full breadcrumb visibility
config.enable_breadcrumbs = true

# Production: Enable with conservative buffer
config.enable_breadcrumbs = true
config.breadcrumb_buffer_size = 25

# High-traffic: Only capture SQL and controller events
config.enable_breadcrumbs = true
config.breadcrumb_categories = [ :sql, :controller ]
```

### Safety

- **Default OFF** — opt-in only
- **Fixed-size ring buffer** — no unbounded memory growth
- **Thread-local** — no mutex/lock, each request isolated
- **Cleanup in ensure** — buffer cleared even on exceptions (Puma thread reuse safe)
- **Every subscriber wrapped in rescue** — never raises, never blocks
- **Sensitive data filtered** — passwords, tokens, secrets scrubbed before storage
- **< 0.1ms/request overhead** — events already fired by Rails

---

## System Health Snapshot (NEW!)

Capture runtime health metrics (GC stats, memory, threads, connection pool, Puma) at the moment of every error. Displayed in the error detail sidebar.

### Quick Start

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_system_health = true
end
```

### What Gets Captured

| Metric | Source | Notes |
|--------|--------|-------|
| GC stats | `GC.stat` | heap_live_slots, heap_free_slots, major_gc_count, total_allocated_objects |
| Process memory | `/proc/self/status` | RSS in MB, Linux only (nil on macOS) |
| Thread count | `Thread.list.count` | O(1), safe |
| Connection pool | `ActiveRecord::Base.connection_pool.stat` | size, busy, idle, dead, waiting |
| Puma stats | `Puma.stats` | running, max_threads, pool_capacity, backlog (when available) |
| RubyVM cache | `RubyVM.stat` | constant_cache invalidations, class serial, global state (when available) |
| YJIT stats | `RubyVM::YJIT.runtime_stats` | compiled ISEQs, code region size, inline/outlined bytes (when YJIT enabled) |
| Job queue depth | Sidekiq, Solid Queue or GoodJob | queries against the queue store, cached per process for `system_health_queue_stats_cache_seconds` (10). Off with `system_health_queue_stats = false` |

### Safety

- **Default OFF** — opt-in only
- **Sub-millisecond**, except the job-queue counts, which are database or Redis queries (cached per process)
- **Every metric individually wrapped** in `rescue => nil`
- **Top-level rescue** — returns `{ captured_at: ... }` if everything fails (never raises)
- **No ObjectSpace scanning** — never calls `each_object` or `count_objects`
- **No Thread backtraces** — only `.count`, never `.map(&:backtrace)`
- **No subprocess** — memory via procfs only, no `ps`, no fork, no backtick
- **No Thread.current** — the only shared state is the per-process cache of queue counts, refreshed by one thread at a time

---

## Local Variable Capture (v0.4.0)

Capture local variables when an exception is raised via `TracePoint(:raise)`. The most valuable debugging context possible. The snapshot is one level deep: strings, arrays and hashes are copied at raise time, while nested containers and other objects are retained by reference and show their state at serialization time.

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_local_variables = true

  # Serialization limits (all have sensible defaults)
  config.local_variable_max_count = 15          # Max variables per exception
  config.local_variable_max_depth = 3           # Max object nesting depth
  config.local_variable_max_string_length = 200 # Truncate strings beyond this
  config.local_variable_max_array_items = 10    # Max array items
  config.local_variable_max_hash_items = 20     # Max hash entries

  # Additional sensitive patterns (beyond Rails filter_parameters)
  config.local_variable_filter_patterns = [ /secret/, /token/ ]
end
```

### Safety

- **Never stores Binding objects** — values extracted immediately, Binding is GC'd
- **Sensitive data auto-filtered** — Rails `filter_parameters` applied automatically
- **Configurable limits** — all size limits enforced during serialization
- **Opt-in only** — disabled by default

---

## Instance Variable Capture (v0.4.0)

Capture instance variables from the object that raised the exception (`tp.self` on the TracePoint).

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_instance_variables = true
  config.instance_variable_max_count = 20          # Max variables (default: 20)
  config.instance_variable_filter_patterns = []    # Additional sensitive patterns
end
```

Shares the same TracePoint handler as local variable capture — minimal overhead when both are enabled. Includes `_self_class` metadata showing the receiver's class name.

---

## Swallowed Exception Detection (v0.4.0)

Detect exceptions that are raised but silently rescued — the hardest bugs to find. **Requires Ruby 3.3+** (TracePoint `:rescue` event, Feature #19572).

```ruby
RailsErrorDashboard.configure do |config|
  config.detect_swallowed_exceptions = true

  config.swallowed_exception_max_cache_size = 1000  # Thread-local cache size
  config.swallowed_exception_flush_interval = 60    # Seconds between DB flushes
  config.swallowed_exception_threshold = 0.95       # 95% rescue ratio = "swallowed"
  config.swallowed_exception_ignore_classes = []    # Exception classes to skip
end
```

Dashboard page at `/errors/swallowed_exceptions`. Auto-disabled on Ruby < 3.3 with a warning (no crash).

---

## Diagnostic Dump (v0.4.0)

On-demand system state snapshots — environment, GC stats, threads, connection pool, memory, job queue health.

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_diagnostic_dump = true
end
```

Trigger via dashboard button or `rails error_dashboard:diagnostic_dump NOTE="deploy check"`. Dashboard page at `/errors/diagnostic_dumps`.

---

## Rack Attack Event Tracking (v0.4.0)

Record Rack::Attack throttle, blocklist, and track events to their own table, aggregated hourly. Requires the `rack-attack` gem to be installed and configured in your app. Breadcrumbs are **not** required.

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_rack_attack_tracking = true
  config.rack_attack_max_cache_size = 1000      # Buffered keys per thread (LRU)
  config.rack_attack_flush_interval = 5         # Max age of buffered events before a write
end
```

Buffered events are written out at the end of the request or job that fills the
buffer once `rack_attack_flush_interval` has elapsed, and again when the process
exits. The interval is therefore an upper bound on how stale the Rate Limits page
can be, not a delay you have to wait out — a rule that matches once still appears.
Raising it reduces write volume under sustained rate-limiting; lowering it makes
the page more immediate.

If `rack-attack` is not loaded, a startup warning is logged and no events are recorded. Enabling breadcrumbs as well adds the event to the activity trail on error detail pages. Dashboard page at `/errors/rack_attack_summary`.

### Measuring AI crawler traffic (v0.10.0)

Events record the client's user agent, and known AI agents are named on the dashboard — `GPTBot`, `ChatGPT-User`, `OAI-SearchBot`, `ClaudeBot`, `Claude-User`, `Claude Code`, `PerplexityBot`, `GitHub Copilot`, `Bytespider`, `CCBot` and others, alongside ordinary crawlers such as Googlebot so the two can be told apart. The page shows an **AI Agent Requests** total and a **Top Agent** column per rule.

`Rack::Attack.track` rules are the way to feed it. They count matching requests without blocking or throttling anything:

```ruby
# Who is reading the site, regardless of the format they ask for
Rack::Attack.track("ai agents") do |req|
  ua = req.user_agent.to_s
  req.ip if ua.match?(/GPTBot|ChatGPT-User|OAI-SearchBot|ClaudeBot|Claude-User|Claude-Code|PerplexityBot|GitHubCopilot/i)
end

# Who specifically wants Markdown
Rack::Attack.track("requests accepting markdown") do |req|
  req.ip if req.get? && req.env["HTTP_ACCEPT"].to_s.include?("text/markdown")
end
```

Run together, the two answer different questions — how many agents read the site, versus how many prefer Markdown. A rule keyed only on `Accept: text/markdown` will undercount badly: agents differ enormously in whether they use content negotiation at all, so a low Markdown figure means "this agent doesn't ask for it", not "no agent wants it".

`path` is recorded per event, so `.md` routes and `/llms.txt` hits appear in the per-rule breakdown without extra configuration.

> **Don't add `limit:`/`period:` to a `track` rule.** Rack::Attack routes a counted track through `Throttle`, which only emits a notification once `count > limit` — so the rule stays silent *below* its limit, the opposite of what adding a limit suggests. Leave track rules uncounted.

### Buffer overflow

Events are buffered per thread, keyed on rule, match type, discriminator, path, method and user agent, and capped by `rack_attack_max_cache_size`. Past the cap the oldest entry is evicted, and its count is added to an overflow total rather than discarded — the dashboard reports it instead of silently showing a smaller number.

Tracking many clients (a crawler fleet on rotating IPs generates a distinct key per address) makes eviction more likely. Raise the cap if the page reports overflow:

```ruby
config.rack_attack_max_cache_size = 5000
```

Buffered counts are flushed on the interval above, and also at process exit, so a deploy does not discard whatever a thread was still holding.

---

## Process Crash Capture (v0.4.0)

Capture unhandled exceptions that crash the Ruby process via an `at_exit` hook.

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_crash_capture = true
  config.crash_capture_path = nil    # nil = Dir.tmpdir; a custom path is created if missing
end
```

Writes crash data to JSON on disk (database may be unavailable during shutdown). Imported automatically on next boot. Honeybadger, Bugsnag and AppSignal have `at_exit` reporters too; RED's difference is that the crash lands in your own database rather than a SaaS.

---

## Custom Severity Classification

Override default severity levels for specific error types. This is useful when you want to treat certain errors differently than the defaults.

### Default Severity Levels

- **Critical**: `SecurityError`, `NoMemoryError`, `SystemStackError`, `SignalException`, `ActiveRecord::StatementInvalid`, `LoadError`, `SyntaxError`, `ActiveRecord::ConnectionNotEstablished`, `Redis::ConnectionError`, `OpenSSL::SSL::SSLError`
- **High**: `ActiveRecord::RecordNotFound`, `ArgumentError`, `TypeError`, `NoMethodError`, `NameError`, `ZeroDivisionError`, `FloatDomainError`, `IndexError`, `KeyError`, `RangeError`
- **Medium**: `ActiveRecord::RecordInvalid`, `Timeout::Error`, `Net::ReadTimeout`, `Net::OpenTimeout`, `ActiveRecord::RecordNotUnique`, `JSON::ParserError`, `CSV::MalformedCSVError`, `Errno::ECONNREFUSED`
- **Low**: All other errors

Each list matches the exact class name only, not subclasses.

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

Each key is the exact class name, as a String. A Regexp or Symbol key never matches, a rule
doesn't cover subclasses, and the order of the rules doesn't matter. A rule mapping to `:critical`
also exempts that error from [sampling](#error-sampling).

To check how an error type is classified:

```ruby
RailsErrorDashboard::Services::SeverityClassifier.classify("Stripe::CardError")  # => :critical
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

- **Class names or classes**: `"ActiveRecord::RecordNotFound"` or `ActiveRecord::RecordNotFound`,
  either way including its subclasses. (Before 0.14.4 a class object was not matched; quote the
  name if your app still runs an older version.)
- **Regex Patterns**: matched against the exception's class name only, so they don't cover subclasses
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
- **0.1 (10%)**: Log about 10% of non-critical errors, and every critical error
- **0.0 (0%)**: Skip all non-critical errors, log only critical errors
- **Above 1.0 or below 0.0**: rejected; the app fails to boot with `RailsErrorDashboard::ConfigurationError`

Between 0.0 and 1.0, the first occurrence of each error in each process is always logged, so
sampling can't hide that an error exists. ("Each error" here means the exception class plus the
first line of your app's code in the backtrace.)

### Critical Errors (Always Logged)

Critical errors bypass sampling: the ten types listed under
[Default Severity Levels](#default-severity-levels), and any type you map to `:critical` in
`custom_severity_rules`.

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

## Storm Protection

When the error rate spikes, after a bad deploy or during a dependency outage, storm protection
limits RED's own database writes so that error tracking doesn't add to the incident. It is on by
default. Occurrence counts stay exact; what is sampled is per-event detail:

1. Past `storm_fingerprint_full_per_minute` captures of one error in a minute, RED stops storing
   context for it, then keeps only every `storm_occurrence_sample_keep_every`th occurrence row.
2. Past `storm_shedding_threshold_per_second` errors per second, RED stops storing per-event
   context for every error. Past `storm_open_threshold_per_second`, it only counts. After
   `storm_cooldown_seconds`, once the rate is back below the shedding threshold, it captures a
   sample of events without context, and returns to full capture when the rate stays low.
3. Per-error notifications pause; with `storm_notification` on, one "storm in progress"
   notification goes out instead.
4. The buffered counts are written to the error records every `storm_flush_interval_seconds`.

An error first seen while RED only counts gets a minimal record, with no callbacks, events or
notifications. Past `storm_max_tracked_fingerprints` distinct errors in one process, further
events are added to one overflow total that isn't attached to any error.

Every threshold is per process: each Puma worker and job process keeps its own counts. While
storm protection is on, every option in the table must be a positive integer, and
`storm_open_threshold_per_second` must be at least `storm_shedding_threshold_per_second`;
otherwise the app fails to boot. With `enable_storm_protection = false`, none of this applies,
including the cap on automatically created issues.

---

## Scheduled Digests

A daily or weekly summary email of error activity. It is off by default, and nothing sends it
until you schedule `RailsErrorDashboard::ScheduledDigestJob`.

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_scheduled_digests = true
  config.digest_recipients = ["team@example.com"]  # default: notification_email_recipients
end
```

The job takes the period as an argument: `period: "daily"` (the default) or `period: "weekly"`.
`digest_frequency` doesn't change what it sends. See
[Schedule the periodic jobs](/rails_error_dashboard/docs/production/#2-schedule-the-periodic-jobs) for a Solid Queue
schedule and a cron line. The email goes through your app's Action Mailer setup, from
`notification_email_from`. To send one now, `bin/rails error_dashboard:send_digest PERIOD=daily`
queues the job for your worker.

---

## Notification Callbacks

Register custom Ruby blocks that execute when errors are logged or resolved. Perfect for integrating with external services.

### Available Callbacks

#### 1. `on_error_logged` - Any Error Logged

```ruby
RailsErrorDashboard.on_error_logged do |error_log|
  # Called when an error is first logged, and when a resolved error reopens.
  # Not called for the other recurrences.

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
  # Called ONLY for critical errors (in addition to on_error_logged), at the same moments

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
  # Called when one error is resolved (the Resolve button, or ResolveError).
  # Not called for a batch resolve, or for a status change to "resolved".

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

Callbacks are fail-safe - if one callback raises an error, it won't break error logging or prevent other callbacks from running. The failure is logged at error level, which you only see when `config.log_level` isn't `:silent` (the default):

```ruby
RailsErrorDashboard.on_error_logged do |error_log|
  raise "Callback error"  # Logged at error level, other callbacks still run
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

Emitted when an error is first logged, and when a resolved error reopens. Not emitted for the other recurrences.

```ruby
ActiveSupport::Notifications.subscribe("error_logged.rails_error_dashboard") do |name, start, finish, id, payload|
  # Payload contains:
  # - error_log: Full ErrorLog record (payload[:error_log].environment has the environment)
  # - error_id: Error ID
  # - error_type: Exception class name
  # - message: Error message
  # - severity: Error severity (:critical, :high, :medium, :low)
  # - platform: Platform (iOS, Android, API)
  # - occurred_at: Timestamp

  StatsD.increment("errors.logged", tags: ["type:#{payload[:error_type]}"])
end
```

The events are sent after the error is saved, not around the save, so their duration is always
about zero: they can't be used to time error logging.

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
      environment: event.payload[:error_log].environment
    }
  )
end
```

---

## Async Error Logging (Revisited)

See [Async Error Logging](#async-error-logging) above. For quick reference:

```ruby
RailsErrorDashboard.configure do |config|
  # Save errors in a background job on your app's Active Job adapter.
  # A worker must process the default and error_notifications queues.
  config.async_logging = true
end
```

---

## Backtrace Configuration

Control how many lines of backtrace are stored:

```ruby
RailsErrorDashboard.configure do |config|
  # Limit backtrace to 100 lines (default)
  config.max_backtrace_lines = 100

  # Store less for high-volume apps
  config.max_backtrace_lines = 50

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
  # Credentials come from ERROR_DASHBOARD_USER and ERROR_DASHBOARD_PASSWORD.
  # Don't set them here (see Dashboard Credentials).

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

  # Each channel is switched on only when its setting is present. A channel
  # that is on without its URL, key or recipients stops the app booting.

  # Slack Notifications
  config.slack_webhook_url = ENV["SLACK_WEBHOOK_URL"]
  config.enable_slack_notifications = config.slack_webhook_url.present?

  # Email Notifications
  config.notification_email_recipients = ENV.fetch("ERROR_NOTIFICATION_EMAILS", "").split(",").map(&:strip).reject(&:empty?)
  config.notification_email_from = ENV.fetch("ERROR_NOTIFICATION_FROM", "errors@example.com")
  config.enable_email_notifications = config.notification_email_recipients.any?

  # Discord Notifications
  config.discord_webhook_url = ENV["DISCORD_WEBHOOK_URL"]
  config.enable_discord_notifications = config.discord_webhook_url.present?

  # PagerDuty Integration (critical errors only)
  config.pagerduty_integration_key = ENV["PAGERDUTY_INTEGRATION_KEY"]
  config.enable_pagerduty_notifications = config.pagerduty_integration_key.present?

  # Generic Webhook Notifications
  config.webhook_urls = ENV.fetch("WEBHOOK_URLS", "").split(",").map(&:strip).reject(&:empty?)
  config.enable_webhook_notifications = config.webhook_urls.any?

  # Dashboard base URL (used in notification links)
  config.dashboard_base_url = ENV["DASHBOARD_BASE_URL"]

  # ============================================================================
  # PERFORMANCE & SCALABILITY
  # ============================================================================

  # Async Error Logging (on your app's Active Job adapter; run a worker
  # for the default and error_notifications queues)
  config.async_logging = true

  # Backtrace size limiting (default: 100)
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
  # With true, also set config.database = :error_dashboard (its database.yml entry)

  # ============================================================================
  # ADVANCED ANALYTICS
  # ============================================================================

  # Baseline Anomaly Alerts (schedule RailsErrorDashboard::BaselineCalculationJob)
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
  # SOURCE CODE INTEGRATION (NEW!)
  # ============================================================================

  # Enable source code viewer
  config.enable_source_code_integration = true

  # Context lines around error (default: 5)
  config.source_code_context_lines = 5

  # Enable git blame integration
  config.enable_git_blame = true

  # Cache TTL in seconds (default: 3600 = 1 hour)
  config.source_code_cache_ttl = 3600

  # Security: only show app code (default: true)
  config.only_show_app_code_source = true

  # Branch strategy for repository links (default: :commit_sha)
  config.git_branch_strategy = :commit_sha

  # ============================================================================
  # BREADCRUMBS (NEW!)
  # ============================================================================

  # Enable breadcrumbs (request activity trail)
  config.enable_breadcrumbs = true

  # Max events per request (default: 40)
  config.breadcrumb_buffer_size = 40

  # Capture all categories (default: nil = all)
  # config.breadcrumb_categories = [:sql, :controller, :cache, :job, :mailer, :custom]

  # ============================================================================
  # SYSTEM HEALTH SNAPSHOT (NEW!)
  # ============================================================================

  # Capture GC, memory, threads, connection pool, RubyVM, YJIT at error time
  config.enable_system_health = true

  # ============================================================================
  # DEEP DEBUGGING (v0.4.0)
  # ============================================================================

  # Local variable capture via TracePoint(:raise)
  config.enable_local_variables = true
  config.local_variable_max_count = 15
  config.local_variable_max_depth = 3
  config.local_variable_max_string_length = 200

  # Instance variable capture from raising object
  config.enable_instance_variables = true
  config.instance_variable_max_count = 20

  # Swallowed exception detection (Ruby 3.3+ required)
  config.detect_swallowed_exceptions = true
  config.swallowed_exception_threshold = 0.95

  # On-demand diagnostic dump
  config.enable_diagnostic_dump = true

  # Rack Attack event tracking (needs the rack-attack gem)
  config.enable_rack_attack_tracking = true

  # ActionCable connection monitoring (requires breadcrumbs)
  config.enable_actioncable_tracking = true

  # ActiveStorage service health (requires breadcrumbs)
  config.enable_activestorage_tracking = true

  # Process crash capture via at_exit hook
  config.enable_crash_capture = true
  # config.crash_capture_path = "/var/log/myapp/crashes"  # default: Dir.tmpdir

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
   # In rails console: read the options you changed, one by one
   RailsErrorDashboard.configuration.async_logging
   RailsErrorDashboard.configuration.sampling_rate
   ```
   Don't print the whole `RailsErrorDashboard.configuration` object, or paste it into an issue:
   it includes the dashboard password, webhook URLs and API keys.

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

4. **Check background jobs are running, on both queues**
   ```bash
   # With Sidekiq: Slack and email jobs use the error_notifications queue
   bundle exec sidekiq -q default -q error_notifications

   # With Solid Queue
   bin/jobs
   ```

5. **Check what holds notifications back**
   - `notification_minimum_severity` (default `:low`): new and reopened errors below it don't
     notify. Milestone notifications ignore it.
   - A recurring error notifies only at the `notification_threshold_alerts` counts
     (10, 50, 100, 500, 1000), and a reopened one at most every `notification_cooldown_minutes` (5).
   - `notification_burst_limit` (10 per 60 seconds, per process) replaces the rest of a burst of
     new errors with one summary.
   - `notification_environments`, when set, limits notifications to those environments.
   - Muted errors, errors marked "Won't fix" and errors during an error storm don't notify.
   - PagerDuty only receives critical errors, and baseline alerts at the `:critical` level.

### Custom Severity Rules Not Working

**Problem**: Custom severity rules aren't being applied.

**Solutions**:
1. **Check rule format** - Keys are exact class names, as Strings
   ```ruby
   # Correct
   config.custom_severity_rules = {
     "ActiveRecord::RecordNotFound" => :low,
     "Net::ReadTimeout" => :high
   }

   # Incorrect: Regexp and Symbol keys never match
   config.custom_severity_rules = {
     /ActiveRecord::RecordNotFound/ => :low,
     :timeout_error => :high
   }
   ```

2. **Check the class name** - A rule covers that exact class only, not its subclasses, and the
   order of the rules doesn't matter. To see how a type is classified:
   ```ruby
   # In rails console
   RailsErrorDashboard::Services::SeverityClassifier.classify("ActiveRecord::RecordNotFound")
   # => :low with the rule above
   ```

3. **Restart the app** - The rules are read when each error is classified, but the initializer
   only runs at boot.

### Background Jobs Not Processing

**Problem**: Async logging enabled but errors not appearing.

**Solutions**:
1. **Check which backend runs the jobs** - RED uses your app's Active Job adapter
   ```ruby
   # In rails console
   ActiveJob::Base.queue_adapter
   # (RailsErrorDashboard.configuration.async_adapter doesn't choose it)
   ```

2. **Verify job processor is running, on both queues**
   ```bash
   # Sidekiq (must process default and error_notifications)
   ps aux | grep sidekiq

   # Solid Queue (process titles start with solid-queue)
   ps aux | grep solid-queue
   ```

3. **Check queued and failed jobs**
   ```ruby
   # Sidekiq
   require 'sidekiq/api'
   Sidekiq::Queue.new("default").size
   Sidekiq::RetrySet.new.size
   Sidekiq::DeadSet.new.size

   # Solid Queue
   SolidQueue::ReadyExecution.count
   SolidQueue::FailedExecution.count
   ```
   Most of RED's jobs retry three times and are then dropped with a log line ("discarded after 3
   attempts"), so they don't stay in the failed set. The issue-tracker jobs are the exception.

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
   RailsErrorDashboard::Services::SeverityClassifier.critical?("MyError")
   ```

3. **Adjust rate** - Start higher, tune down
   ```ruby
   config.sampling_rate = 0.5  # Start with 50%
   ```

4. **Always keep specific errors** - There is no per-exception sampling hook. Map the types you
   always want to `:critical`, which bypasses sampling:
   ```ruby
   config.custom_severity_rules = { "Stripe::CardError" => :critical }
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
   config.use_separate_database = true
   config.database = :error_dashboard  # must match an entry in config/database.yml
   ```
   See the [Database Options Guide](/rails_error_dashboard/docs/guides/database-options/).

3. **Add database indexes** - Already included in migrations

4. **Reduce backtrace limit**
   ```ruby
   config.max_backtrace_lines = 20  # Default is 100
   ```

5. **Configure retention policy**
   ```ruby
   config.retention_days = 30  # Deletes errors unseen for 30 days...
   ```
   ...when `RailsErrorDashboard::RetentionCleanupJob` runs. Nothing schedules it for you: see
   [Schedule the periodic jobs](/rails_error_dashboard/docs/production/#2-schedule-the-periodic-jobs).

See [Database Optimization Guide](/rails_error_dashboard/docs/guides/database-optimization/) for more.

### Authentication Not Working

**Problem**: Can't access dashboard even with correct credentials.

**Solutions**:
1. **Check username and password are set**
   ```ruby
   # In rails console
   RailsErrorDashboard.configuration.dashboard_username
   RailsErrorDashboard.configuration.dashboard_password
   ```

2. **Check neither value is blank**
   A blank or `nil` username or password denies every login, in development too. The usual cause is
   `config.dashboard_username = ENV["ERROR_DASHBOARD_USER"]` in the initializer with the variable unset.
   See [Dashboard Credentials](#dashboard-credentials).

3. **Test credentials**
   ```bash
   curl -u admin:password http://localhost:3000/red
   ```

4. **Check for proxy/load balancer issues**
   - Some proxies strip Authorization headers
   - May need to configure pass-through

5. **Clear browser cache** - Old credentials may be cached

### Multi-App Configuration Issues

**Problem**: Errors from multiple apps not showing correctly.

**Solutions**:
1. **Set the APPLICATION_NAME environment variable**
   ```bash
   APPLICATION_NAME=my-api rails server
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

See [Multi-App Support Guide](/rails_error_dashboard/docs/features/multi-app-performance/) for more.

---

## Resetting Configuration

For tests only. `reset_configuration!` also drops every registered callback and the issue-tracker
hooks, and the new values are not validated. Middleware and subscribers are set up at boot, so
resetting doesn't change them in a running app.

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
