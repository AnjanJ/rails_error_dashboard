---
layout: default
title: "API Reference"
order: 1
---

# API Reference

RED has no JSON API, and no HTTP endpoint that accepts errors. Its HTTP routes are the dashboard
itself: HTML pages, and the forms on them that post back. This page lists those routes, for when you
script the dashboard, put it behind a proxy, or want to know why a request was refused. Errors reach
RED from Ruby code running in your app; the [Ruby API](#ruby-api) covers that.

1. [Sending errors to RED](#sending-errors-to-red)
2. [HTTP routes](#http-routes)
3. [Ruby API](#ruby-api)

---

## Sending errors to RED

- **Unhandled exceptions** in requests and background jobs are captured without any code.
- **From your own Ruby code:** report a rescued exception with
  [`Rails.error.report`](#railserrorreport). Report something that isn't a Ruby exception with
  [`ManualErrorReporter.report`](#manualerrorreporterreport).
- **From a browser or a mobile app:** RED has no endpoint for them. Add a route to your own app that
  receives the error and calls `ManualErrorReporter.report`. The
  [Mobile App Integration guide](/rails_error_dashboard/docs/guides/mobile-app-integration/) has a complete controller.

---

## HTTP routes

### Mount path

The installer mounts the dashboard at `/red`, and every path below is relative to that mount:
`/errors` means `/red/errors`. Apps first installed before 0.5.8 are mounted at `/error_dashboard`
instead (see [Old mount path](/rails_error_dashboard/docs/upgrading/#old-mount-path-for-apps-installed-before-058)). Your
`config/routes.rb` has the real value:

```ruby
mount RailsErrorDashboard::Engine => "/red"
```

### Authentication

Every route except the [issue-tracker webhooks](#issue-tracker-webhooks) needs the dashboard's
authentication:

- **HTTP Basic** with the dashboard credentials, `ERROR_DASHBOARD_USER` and
  `ERROR_DASHBOARD_PASSWORD` (see [Dashboard Credentials](/rails_error_dashboard/docs/guides/configuration/#dashboard-credentials)).
  A missing or wrong login gets `401`.
- **Your `config.authenticate_with` block**, when you set one. It replaces HTTP Basic. A false
  result gets `403` with the body `Access Denied`, and so does a block that raises.

### Formats

Pages render HTML only. Asking a page for another format, with `.json` on the path or an
`Accept: application/json` header, gets `406`. The actions that change something are form POSTs
that answer with a redirect. Two routes differ: `ai_help` streams
[server-sent events](#actions-on-one-error), and the webhooks answer with an empty body.

### Posting from a script

The dashboard's forms are protected against cross-site request forgery. A POST needs the session
cookie and the token from a page the same session loaded, so a plain `curl -X POST -u ...` gets
`422`. To script an action, load a page first, keep its cookie, and send its token:

```bash
BASE=https://your-app.example.com/red
JAR=$(mktemp)

# 1. Load a page: it sets the session cookie and carries the token
TOKEN=$(curl -s -u "$RED_USER:$RED_PASSWORD" -c "$JAR" "$BASE/errors" \
  | sed -n 's/.*name="csrf-token" content="\([^"]*\)".*/\1/p')

# 2. Post with the same cookie and the token
curl -s -o /dev/null -w '%{http_code}\n' -u "$RED_USER:$RED_PASSWORD" -b "$JAR" \
  --data-urlencode "authenticity_token=$TOKEN" \
  --data-urlencode "resolved_by_name=deploy-bot" \
  "$BASE/errors/42/resolve"
# => 302
```

### Rate limiting

Rate limiting is off by default. Turn it on in the initializer; it takes effect at boot:

```ruby
config.enable_rate_limiting = true
config.rate_limit_per_minute = 300 # the default
```

- **What is counted:** each client IP gets `rate_limit_per_minute` requests per minute to each
  path, counted per exact path, so `/red/errors/1` and `/red/errors/2` have separate counts.
  Webhooks and requests that fail authentication count too, because the limit runs before
  authentication.
- **Which paths:** every path that starts with the mount path. With `/red`, that includes your
  app's own paths that start with the same letters, such as `/redirect`.
- **Over the limit:** `429` with an HTML page, `Retry-After: 60`, `X-RateLimit-Limit` and
  `X-RateLimit-Period`. There is no JSON variant.
- **Where counts live:** in `Rails.cache`. With `:null_store`, nothing is ever limited. With more
  than one process (Puma workers, or several servers), each process counts on its own unless the
  cache store is shared, such as Redis, Solid Cache or Memcached.

### Response codes

| Code | When |
|---|---|
| `200` | A page; `ai_help`'s event stream; a webhook that passed its signature check |
| `302` | Every form POST. Also a page whose feature is off: it redirects to `/errors` with a message naming the option to turn on |
| `303` | A `per_page` that isn't a positive number, or a `page` past the end of the error list: it redirects to the same page without `page` and `per_page`, keeping the other parameters |
| `400` | A malformed request |
| `401` | No or wrong HTTP Basic login. For webhooks: a missing or wrong signature, or an unknown provider |
| `403` | Your `authenticate_with` block returned false or raised |
| `404` | No error with that ID. Webhooks while issue tracking or the webhook secret isn't set. `ai_help` with no LLM configured |
| `406` | A page asked for in a format other than HTML |
| `422` | A POST without a valid CSRF token. `ai_help` with a blank question or one over 4,000 characters |
| `429` | Over the [rate limit](#rate-limiting) |
| `500` | Anything else that fails inside the dashboard. It renders a "Something went wrong" page; your app is unaffected |

Until a request is authenticated, these error responses are plain text with no details.

### Pages

All are `GET`. Pages that take `days` accept 1 to 365 and default to 30, except Platform Comparison
(7). Pages that list rows take `page` and `per_page` (default 25, at most 100). `application_id`
limits most pages to one application.

| Path | Page | Takes | Needs |
|---|---|---|---|
| `/` and `/overview` | Overview | | |
| `/errors` | The error list ([filters](#filtering-the-error-list)) | `page`, `per_page` | |
| `/errors/:id` | One error | | |
| `/errors/analytics` | Analytics | `days` | |
| `/errors/platform_comparison` | Platform comparison | `days` | `enable_platform_comparison` |
| `/errors/correlation` | Error correlation | `days` | `enable_error_correlation` |
| `/errors/releases` | Releases | `days`, `page`, `per_page` | |
| `/errors/storms` | Error storms | | |
| `/errors/user_impact` | User impact | `days`, `page`, `per_page` | |
| `/errors/deprecations` | Deprecations | `days`, `page`, `per_page` | `enable_breadcrumbs` |
| `/errors/n_plus_one_summary` | N+1 queries | `days`, `page`, `per_page` | `enable_breadcrumbs` |
| `/errors/cache_health_summary` | Cache health | `days`, `page`, `per_page` | `enable_breadcrumbs` |
| `/errors/job_health_summary` | Job health | `days`, `page`, `per_page` | `enable_system_health` |
| `/errors/database_health_summary` | Database health | `days`, `page`, `per_page` | `enable_system_health` |
| `/errors/swallowed_exceptions` | Swallowed exceptions | `days`, `page`, `per_page` | `detect_swallowed_exceptions` (Ruby 3.3+) |
| `/errors/rack_attack_summary` | Rack Attack events | `days`, `page`, `per_page` | `enable_rack_attack_tracking` |
| `/errors/actioncable_health_summary` | ActionCable health | `days`, `page`, `per_page` | `enable_actioncable_tracking` and `enable_breadcrumbs` |
| `/errors/activestorage_health_summary` | ActiveStorage health | `days`, `page`, `per_page` | `enable_activestorage_tracking` and `enable_breadcrumbs` |
| `/errors/llm_health_summary` | LLM health | `days`, `page`, `per_page` | `enable_llm_observability` and `enable_breadcrumbs` |
| `/errors/diagnostic_dumps` | Diagnostic dumps | `page`, `per_page` | `enable_diagnostic_dump` |
| `/settings` | Your configuration, read-only | | |

When a page's option is off, the page redirects to `/errors` with a message naming the option. The
LLM health page is the exception: it renders and says the feature is off.

### Actions on one error

All are `POST /errors/:id/<action>`, and all redirect back to the error.

| Action | Params | What it does |
|---|---|---|
| `resolve` | `resolved_by_name`, `resolution_comment`, `resolution_reference`, all optional | Resolves the error from any status. Runs your `on_error_resolved` callbacks and plugins, and closes a linked issue when issue tracking is on |
| `assign` | `assigned_to` (required) | Sets the assignee, and sets the status to `in_progress` |
| `unassign` | | Clears the assignee. The status doesn't change |
| `update_priority` | `priority_level`: `0` to `3` | See [priorities](#priority-and-status) |
| `snooze` | `hours`: a whole number from 1 to 720 (required); `reason` | Marks the error snoozed until then. The list leaves it out when "Hide snoozed" is ticked (`hide_snoozed=1`). Notifications still go out. A reason is saved as a comment |
| `unsnooze` | | |
| `mute` | `muted_by`, `reason` | Stops the error's own notifications and its baseline alerts. Digests still include it |
| `unmute` | | |
| `update_status` | `status` (required), `comment` | Changes the status if the [transition](#priority-and-status) is allowed. The dashboard has no control for this; only a POST uses it |
| `create_issue` | | Opens an issue in your tracker. Needs [issue tracking](/rails_error_dashboard/docs/guides/configuration/#issue-tracking--githubgitlabcodeberg-v058) |
| `link_issue` | `issue_url` (required, `http` or `https`) | Links an existing issue |
| `ai_help` | `question` (required, up to 4,000 characters) | Answers as server-sent events: `chunk` events, then `done` or `error`. Needs an LLM provider and key. Its refusals are JSON (`404`, `422`) |

An invalid value (an unknown status, a priority of 4, `hours=0`) changes nothing. The redirect
carries a message saying why.

#### Priority and status

| `priority_level` | Label |
|---|---|
| `3` | Critical (P0) |
| `2` | High (P1) |
| `1` | Medium (P2) |
| `0` | Low (P3), every error's default |

`status` is one of `new`, `in_progress`, `investigating`, `resolved` and `wont_fix`. `update_status`
allows only these moves:

| From | To |
|---|---|
| `new` | `in_progress`, `investigating`, `wont_fix` |
| `in_progress` | `investigating`, `resolved`, `new` |
| `investigating` | `resolved`, `in_progress`, `wont_fix` |
| `resolved` | `new` |
| `wont_fix` | `new` |

Moving to `resolved` this way resolves the error, but doesn't run `on_error_resolved` callbacks or
plugins. A `wont_fix` error still counts new occurrences, but sends no notifications for them.

### Other actions

All are `POST`.

| Path | Params | What it does |
|---|---|---|
| `/errors/batch_action` | `error_ids[]`, `action_type`, and see below | Acts on several errors, then redirects to `/errors` |
| `/errors/test_error` | | Logs a `RailsErrorDashboard::TestError`, to check your notification channels |
| `/errors/create_diagnostic_dump` | `note` | Captures a snapshot of the process. Needs `enable_diagnostic_dump` |
| `/errors/enable_coverage` | | Turns on line coverage for the source viewer. Needs `enable_coverage_tracking` and Ruby 3.2+ |
| `/errors/disable_coverage` | | Turns it off |
| `/locale` | `locale`: `de`, `en`, `es`, `fr`, `it`, `ja`, `pl`, `pt-BR`, `ru`, `uk` or `zh-CN` | Sets the dashboard's language for this session |

`batch_action` takes `action_type`:

| `action_type` | Extra params | Notes |
|---|---|---|
| `resolve` | `resolved_by_name`, `resolution_comment` | Doesn't run `on_error_resolved` callbacks, so linked issues stay open. Plugins get `on_errors_batch_resolved` |
| `mute` | `muted_by`, `reason` | |
| `unmute` | | |
| `delete` | | Deletes the errors with their occurrences and comments |

The list page offers only Resolve and Delete. IDs that don't exist are skipped.

### Issue-tracker webhooks

`POST /webhooks/:provider`, where `:provider` is `github`, `gitlab`, `codeberg` or `linear`. When
someone closes a linked issue, RED resolves the error; when they reopen it, RED reopens the error.

These routes skip the dashboard's login and CSRF check. They check a signature made with
`config.issue_webhook_secret` instead:

| Provider | Header | Value |
|---|---|---|
| GitHub | `X-Hub-Signature-256` | `sha256=` and the HMAC-SHA256 of the body |
| GitLab | `X-Gitlab-Token` | the secret itself |
| Codeberg | `X-Gitea-Signature` | the HMAC-SHA256 of the body |
| Linear | `Linear-Signature` | the HMAC-SHA256 of the body |

- `404` unless `enable_issue_tracking` is on and `issue_webhook_secret` is set.
- `401` for a missing or wrong signature, or any other provider.
- `200` once the signature checks out, even when the payload matches no error or fails to process,
  so the tracker doesn't retry.

### Filtering the error list

`GET /errors` takes these query parameters. Each takes a single value.

| Param | Values | Notes |
|---|---|---|
| `unresolved` | `0` or `false` shows all errors | **Defaults to unresolved only.** Add `unresolved=0` to see resolved ones |
| `status` | `new`, `in_progress`, `investigating`, `resolved`, `wont_fix` | `status=resolved` also needs `unresolved=0` |
| `error_type` | exact class name | |
| `platform` | exact value, such as `iOS`, `Android`, `API` | |
| `environment` | exact value, such as `production` | |
| `application_id` | an application's ID | |
| `user_id` | a user ID | |
| `app_version`, `git_sha` | exact value | |
| `search` | text | Searches the message, backtrace and error type. Full-text on PostgreSQL; a case-insensitive match elsewhere |
| `severity` | `critical`, `high`, `medium`, `low` | Uses RED's built-in classification. `custom_severity_rules` don't apply to this filter |
| `timeframe` | `last_hour`, `today`, `yesterday`, `last_7_days`, `last_30_days`, `last_90_days` | |
| `frequency` | `once`, `few` (2-9), `frequent` (10-99), `very_frequent` (100+), `recurring` | `recurring` means more than 5 occurrences and seen in the last 24 hours |
| `assigned_to` | `__unassigned__`, `__assigned__`, or a name | |
| `assignee_name` | a name | |
| `priority_level` | `0` to `3` | |
| `hide_snoozed` | `1` | Only `1` works, not `true` |
| `hide_muted` | `1` | Only `1` works, not `true` |
| `reopened` | `true` | Only `true` works, not `1` |
| `sort_by` | `occurred_at`, `first_seen_at`, `last_seen_at`, `created_at`, `resolved_at`, `occurrence_count`, `priority_score`, `error_type`, `platform`, `app_version`, `severity` | Defaults to `occurred_at` |
| `sort_direction` | `asc`, `desc` | Defaults to `desc` |
| `page`, `per_page` | numbers | `per_page` defaults to 25, at most 100. A `page` that isn't a positive number shows the first page |

Unknown values for `severity`, `timeframe`, `frequency` and `sort_by` are ignored.

```bash
curl -s -u "$RED_USER:$RED_PASSWORD" \
  "https://your-app.example.com/red/errors?platform=iOS&severity=critical&timeframe=last_7_days&hide_muted=1"
```

This returns the HTML page.

---

## Ruby API

These are the parts of RED meant to be called from your app.

### Configuration

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_slack_notifications = true
end
```

Every option is in the [Configuration Guide](/rails_error_dashboard/docs/guides/configuration/).

### Rails.error.report

RED subscribes to the Rails error reporter, so this records a rescued exception:

```ruby
begin
  charge_card!
rescue PaymentGateway::Declined => e
  Rails.error.report(e, handled: false, context: { user_id: current_user.id })
  # ...
end
```

Pass `handled: false` or `severity: :error`. RED skips reports that are handled warnings, which is
what a bare `Rails.error.report(e)` and `Rails.error.handle { }` send. `Rails.error.record { }`
reports and re-raises, and RED records it.

### ManualErrorReporter.report

Records an error that isn't a Ruby exception, such as one sent by a browser or a mobile app:

```ruby
RailsErrorDashboard::ManualErrorReporter.report(
  error_type: "TypeError",
  message: "Cannot read properties of undefined (reading 'id')",
  backtrace: ["at renderCart (cart.js:42)", "at onClick (button.js:15)"],
  platform: "Web",
  user_id: current_user&.id,
  app_version: "2.1.0",
  metadata: { component: "ShoppingCart" }
)
```

| Keyword | |
|---|---|
| `error_type:` | Required. Groups the error and decides its severity |
| `message:` | Required |
| `backtrace:` | An array of lines, or one string with a line per frame |
| `platform:` | Stored as given. The dashboard's iOS and Android badges match exactly `"iOS"` and `"Android"`. Without it the platform is `"API"` |
| `user_id:`, `app_version:` | Stored as given |
| `request_url:`, `user_agent:`, `ip_address:` | Stored as given |
| `metadata:` | A Hash. It is shown with the request params. Anything else is dropped |
| `occurred_at:` | A `Time` or a date string; defaults to now. A time in the future becomes now. An older time is kept on the occurrence, which the charts read; the error's own `occurred_at` is set no further back than 24 hours |
| `source:` | A label, such as `"mobile_app"`. Used as the request URL when `request_url:` is missing |
| `severity:` | Ignored. Severity comes from `error_type` |

It returns the `RailsErrorDashboard::ErrorLog`, or `nil`. It returns `nil` when
`config.async_logging` is on (a job saves the error), and when the error is ignored, sampled out
or held back by storm protection.

### Callbacks and notifications

Run your own code when RED records or resolves an error:

```ruby
# config/initializers/rails_error_dashboard.rb, after the configure block
RailsErrorDashboard.on_error_logged do |error_log|
  Rails.logger.info("RED: #{error_log.error_type}")
end

RailsErrorDashboard.on_critical_error do |error_log|
  # ...
end

RailsErrorDashboard.on_error_resolved do |error_log|
  # ...
end
```

- `on_error_logged` runs for a new error and for a resolved error that happens again, but not for
  each repeat of an open error. `on_critical_error` runs at the same moments when the error is
  critical.
- `on_error_resolved` runs when an error is resolved with the Resolve button, `ErrorLog#resolve!`
  or a webhook. A batch resolve or a status change to `resolved` doesn't run it.
- A callback that raises is rescued and doesn't stop the others.

The same moments are published as `ActiveSupport::Notifications` events:
`error_logged.rails_error_dashboard`, `critical_error.rails_error_dashboard` and
`error_resolved.rails_error_dashboard`. Each payload has `error_log` and `error_id`.

```ruby
ActiveSupport::Notifications.subscribe("error_logged.rails_error_dashboard") do |event|
  StatsD.increment("errors.#{event.payload[:severity]}")
end
```

For more events (every recurrence, mute, unmute, each batch action, and the error page being
viewed), write a plugin. See the [Plugin System](/rails_error_dashboard/docs/features/plugin-system/).

### Breadcrumbs

```ruby
RailsErrorDashboard.add_breadcrumb("checkout started", { cart_id: cart.id })
```

It adds a step to the current request's trail. It does nothing unless `config.enable_breadcrumbs`
is on. See [Breadcrumbs](/rails_error_dashboard/docs/guides/configuration/#breadcrumbs--request-activity-trail-new).

### Jobs

RED's periodic jobs need your scheduler: see
[Schedule the periodic jobs](/rails_error_dashboard/docs/production/#2-schedule-the-periodic-jobs). Cascade detection also
needs one if you want it. Nothing in the gem runs it, so there is no cascade data until you do
(the error page shows it when `enable_error_cascades` is on):

```ruby
RailsErrorDashboard::Services::CascadeDetector.call(lookback_hours: 24)
# => { detected: 2, updated: 5 }
```

### Reading and changing errors

Errors are `RailsErrorDashboard::ErrorLog` records, stored in RED's database (your primary database,
or the separate one if you set that up).

```ruby
errors = RailsErrorDashboard::ErrorLog.unresolved.by_platform("iOS").last_24_hours

error = RailsErrorDashboard::ErrorLog.find(42)
error.error_type        # "NoMethodError"
error.occurrence_count  # 17
error.severity          # :critical, :high, :medium or :low
error.critical?

error.resolve!(resolved_by_name: "deploy-bot", resolution_comment: "Fixed in #456")
error.mute!(muted_by: "ops", reason: "Known, fix scheduled")
error.unmute!
```

Scopes: `unresolved`, `resolved`, `recent`, `by_error_type`, `by_platform`, `by_environment`,
`by_status`, `by_priority`, `by_assignee`, `assigned`, `unassigned`, `active` (not snoozed),
`snoozed`, `muted`, `unmuted`, `last_24_hours`, `last_week`.

`resolve!` works like the Resolve button, including the callbacks. `mute!` and `unmute!` work like
their buttons.

### Internal classes

The `Commands`, `Queries` and `Services` classes back the dashboard's pages. They aren't a public
API and can change in any release. If you already call them, these are their current signatures:

| Call | Returns |
|---|---|
| `Commands::LogError.call(exception, context = {})` | Used by RED's own capture. Use `ManualErrorReporter.report` instead |
| `Commands::ResolveError.call(id, resolved_by_name: "me")`; the other keys are `resolution_comment` and `resolution_reference` | the `ErrorLog` |
| `Commands::BatchDeleteErrors.call([1, 2, 3])` | `{ success:, count:, total:, errors: [] }` |
| `Queries::DashboardStats.call(application_id: nil)` | a Hash: `total_today`, `total_week`, `total_month`, `unresolved`, `resolved`, `reopened`, `by_platform`, `top_errors` and more. Cached for a minute |
| `Queries::ErrorsList.call(filters = {})` | an `ActiveRecord::Relation`; the filters are [the list's](#filtering-the-error-list) |
| `Queries::SimilarErrors.call(id, threshold: 0.6, limit: 10)` | `[{ error:, similarity: }]` |
| `Queries::PlatformComparison.new(days: 7)` | methods such as `error_rate_by_platform` and `platform_health_summary` (a Hash by platform) |
| `Queries::ErrorCorrelation.new(days: 30)` | methods such as `errors_by_version` and `problematic_releases` |
| `Services::PatternDetector.analyze_cyclical_pattern(timestamps:, days: 30)` | a Hash with `pattern_type`, `peak_hours` and more |
| `Services::BaselineCalculator.calculate_all_baselines` | `{ calculated: }`. Schedule `BaselineCalculationJob` instead |

The source is in `lib/rails_error_dashboard/` and `app/models/rails_error_dashboard/`.
