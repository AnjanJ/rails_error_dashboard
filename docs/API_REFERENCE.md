# API Reference

Complete API documentation for Rails Error Dashboard.

## Table of Contents

1. [HTTP API](#http-api) - REST endpoints for error logging and management
2. [Ruby API](#ruby-api) - Commands, Queries, and Models
3. [Configuration API](#configuration-api) - Setup and customization

---

# HTTP API

The Rails Error Dashboard provides HTTP endpoints for error logging and management. These endpoints can be used by mobile apps, frontend applications, or other services to log errors programmatically.

## Base URL

All HTTP endpoints are mounted under `/error_dashboard` by default (configurable).

```
https://your-app.com/error_dashboard
```

## Authentication

The dashboard supports HTTP Basic Authentication:

```bash
curl -u username:password https://your-app.com/error_dashboard/errors
```

Configure credentials in your initializer:

```ruby
RailsErrorDashboard.configure do |config|
  config.require_authentication = true
  config.dashboard_username = "admin"
  config.dashboard_password = "secure_password"
end
```

## Rate Limiting

API endpoints are protected by rate limiting (configurable):

- **Dashboard Pages**: 300 requests/minute per IP
- **API Endpoints**: 100 requests/minute per IP

Rate limit exceeded returns `429 Too Many Requests`:

```json
{
  "error": "Rate limit exceeded. Please try again later."
}
```

Configure rate limits:

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_rate_limiting = true
  config.rate_limit_per_minute = 100
end
```

## Error Logging

While the gem doesn't provide built-in HTTP endpoints for error logging (to allow customization), you can easily create them in your application. See [Mobile App Integration Guide](guides/MOBILE_APP_INTEGRATION.md) for complete examples.

### Example: Creating a Custom Error Logging Endpoint

```ruby
# app/controllers/api/v1/mobile_errors_controller.rb
module Api
  module V1
    class MobileErrorsController < BaseController
      # POST /api/v1/mobile_errors
      def create
        RailsErrorDashboard::Commands::LogError.call(
          error_type: error_params[:error_type],
          message: error_params[:message],
          backtrace: error_params[:stack]&.split("\n"),
          occurred_at: Time.current,
          platform: error_params[:platform],
          app_version: error_params[:app_version],
          user_id: current_user&.id,
          request_url: error_params[:url],
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )

        render json: { success: true }, status: :created
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def error_params
        params.require(:error).permit(
          :error_type, :message, :stack, :platform,
          :app_version, :url, :component
        )
      end
    end
  end
end
```

### Request Format

```bash
curl -X POST https://your-app.com/api/v1/mobile_errors \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "error": {
      "error_type": "TypeError",
      "message": "Cannot read property of undefined",
      "stack": "TypeError: Cannot read property...\n  at Component.render",
      "platform": "ios",
      "app_version": "2.1.0",
      "url": "/recordings/new",
      "component": "RecordingScreen"
    }
  }'
```

### Response Format

**Success (201 Created):**
```json
{
  "success": true
}
```

**Error (422 Unprocessable Entity):**
```json
{
  "error": "Validation failed: Message can't be blank"
}
```

## Dashboard Endpoints

These endpoints are used by the web dashboard UI but can also be accessed programmatically.

### List Errors

Get a paginated list of errors with optional filtering.

**Endpoint:** `GET /error_dashboard/errors`

**Query Parameters:**

| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `page` | integer | Page number (default: 1) | `?page=2` |
| `per_page` | integer | Items per page (default: 25) | `?per_page=50` |
| `platform` | string | Filter by platform | `?platform=iOS` |
| `error_type` | string | Filter by error type | `?error_type=NoMethodError` |
| `severity` | string | Filter by severity | `?severity=critical` |
| `status` | string | Filter by status | `?status=investigating` |
| `assigned_to` | string | Filter by assignee | `?assigned_to=dev@example.com` |
| `priority_level` | integer | Filter by priority (0-4) | `?priority_level=4` |
| `unresolved` | boolean | Show only unresolved | `?unresolved=true` |
| `hide_snoozed` | boolean | Hide snoozed errors | `?hide_snoozed=true` |
| `search` | string | Search message/backtrace | `?search=payment` |
| `timeframe` | string | Time filter | `?timeframe=today` |
| `sort_by` | string | Sort field | `?sort_by=occurred_at` |
| `sort_direction` | string | Sort direction (asc/desc) | `?sort_direction=desc` |

**Example:**
```bash
curl -u admin:password \
  "https://your-app.com/error_dashboard/errors?platform=iOS&unresolved=true&per_page=10"
```

### Get Error Details

Get detailed information about a specific error.

**Endpoint:** `GET /error_dashboard/errors/:id`

**Example:**
```bash
curl -u admin:password https://your-app.com/error_dashboard/errors/123
```

### Resolve Error

Mark an error as resolved.

**Endpoint:** `POST /error_dashboard/errors/:id/resolve`

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `resolved_by_name` | string | No | Name of resolver |
| `resolution_comment` | string | No | Resolution notes |
| `resolution_reference` | string | No | PR/commit URL |

**Example:**
```bash
curl -X POST -u admin:password \
  -d "resolved_by_name=John Doe" \
  -d "resolution_comment=Fixed in latest release" \
  -d "resolution_reference=https://github.com/org/repo/pull/456" \
  https://your-app.com/error_dashboard/errors/123/resolve
```

### Assign Error

Assign an error to a team member.

**Endpoint:** `POST /error_dashboard/errors/:id/assign`

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `assigned_to` | string | Yes | Email of assignee |

**Example:**
```bash
curl -X POST -u admin:password \
  -d "assigned_to=dev@example.com" \
  https://your-app.com/error_dashboard/errors/123/assign
```

### Update Priority

Change error priority level.

**Endpoint:** `POST /error_dashboard/errors/:id/update_priority`

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `priority_level` | integer | Yes | Priority (0-4) |

Priority levels:
- `0` - None
- `1` - Low
- `2` - Medium
- `3` - High
- `4` - Critical

**Example:**
```bash
curl -X POST -u admin:password \
  -d "priority_level=4" \
  https://your-app.com/error_dashboard/errors/123/update_priority
```

### Snooze Error

Temporarily hide an error from active view.

**Endpoint:** `POST /error_dashboard/errors/:id/snooze`

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `hours` | integer | Yes | Snooze duration in hours |
| `reason` | string | No | Reason for snoozing |

**Example:**
```bash
curl -X POST -u admin:password \
  -d "hours=24" \
  -d "reason=Waiting for third-party API fix" \
  https://your-app.com/error_dashboard/errors/123/snooze
```

### Update Status

Change error workflow status.

**Endpoint:** `POST /error_dashboard/errors/:id/update_status`

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `status` | string | Yes | New status |
| `comment` | string | No | Status change comment |

Available statuses:
- `new`
- `investigating`
- `fixing`
- `testing`
- `deployed`
- `closed`

**Example:**
```bash
curl -X POST -u admin:password \
  -d "status=investigating" \
  -d "comment=Looking into root cause" \
  https://your-app.com/error_dashboard/errors/123/update_status
```

### Add Comment

Add a comment to an error.

**Endpoint:** `POST /error_dashboard/errors/:id/add_comment`

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `author_name` | string | Yes | Comment author |
| `body` | string | Yes | Comment text |

**Example:**
```bash
curl -X POST -u admin:password \
  -d "author_name=John Doe" \
  -d "body=This appears to be a race condition" \
  https://your-app.com/error_dashboard/errors/123/add_comment
```

### Batch Actions

Perform actions on multiple errors at once.

**Endpoint:** `POST /error_dashboard/errors/batch_action`

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `error_ids[]` | array | Yes | Array of error IDs |
| `action_type` | string | Yes | Action: "resolve" or "delete" |
| `resolved_by_name` | string | No | For resolve action |
| `resolution_comment` | string | No | For resolve action |

**Example:**
```bash
curl -X POST -u admin:password \
  -d "error_ids[]=123" \
  -d "error_ids[]=124" \
  -d "error_ids[]=125" \
  -d "action_type=resolve" \
  -d "resolved_by_name=John Doe" \
  -d "resolution_comment=Fixed in batch update" \
  https://your-app.com/error_dashboard/errors/batch_action
```

## Analytics Endpoints

### Dashboard Overview

Get high-level dashboard statistics.

**Endpoint:** `GET /error_dashboard/overview`

Returns:
- Total errors (today, week, month)
- Unresolved/resolved counts
- Errors by platform
- Top error types
- Trend data
- Critical alerts

### Analytics

Get detailed analytics data.

**Endpoint:** `GET /error_dashboard/errors/analytics`

**Query Parameters:**

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `days` | integer | Days of history | 30 |

**Example:**
```bash
curl -u admin:password \
  "https://your-app.com/error_dashboard/errors/analytics?days=7"
```

Returns:
- Errors over time
- Errors by type
- Errors by platform
- Errors by hour
- Top affected users
- Resolution rate
- Mobile vs API errors
- MTTR statistics
- Recurring issues
- Release correlation

### Platform Comparison

Compare error rates across platforms.

**Endpoint:** `GET /error_dashboard/errors/platform_comparison`

**Query Parameters:**

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `days` | integer | Days of history | 7 |

**Example:**
```bash
curl -u admin:password \
  "https://your-app.com/error_dashboard/errors/platform_comparison?days=14"
```

### Error Correlation

Analyze error patterns and correlations.

**Endpoint:** `GET /error_dashboard/errors/correlation`

**Query Parameters:**

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `days` | integer | Days of history | 30 |

**Example:**
```bash
curl -u admin:password \
  "https://your-app.com/error_dashboard/errors/correlation?days=7"
```

## Error Response Codes

| Code | Description |
|------|-------------|
| `200` | Success |
| `201` | Created |
| `302` | Redirect (after POST actions) |
| `401` | Unauthorized (authentication required) |
| `404` | Not Found |
| `422` | Unprocessable Entity (validation error) |
| `429` | Too Many Requests (rate limit exceeded) |
| `500` | Internal Server Error |

## Code Examples

### JavaScript (Fetch)

```javascript
// Log error from React/React Native app
async function reportError(error, component) {
  try {
    const response = await fetch('https://your-app.com/api/v1/mobile_errors', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${authToken}`
      },
      body: JSON.stringify({
        error: {
          error_type: error.name,
          message: error.message,
          stack: error.stack,
          platform: Platform.OS, // 'ios' or 'android'
          app_version: AppConfig.version,
          component: component
        }
      })
    });

    const data = await response.json();
    return data.success;
  } catch (e) {
    console.error('Failed to report error:', e);
    return false;
  }
}

// Usage in React component
try {
  // Your code
} catch (error) {
  await reportError(error, 'RecordingScreen');
}
```

### Swift (iOS)

```swift
import Foundation

struct ErrorReport: Codable {
    let error: ErrorDetails
}

struct ErrorDetails: Codable {
    let errorType: String
    let message: String
    let stack: String?
    let platform: String
    let appVersion: String
    let component: String?

    enum CodingKeys: String, CodingKey {
        case errorType = "error_type"
        case message
        case stack
        case platform
        case appVersion = "app_version"
        case component
    }
}

func reportError(_ error: Error, component: String) {
    let errorDetails = ErrorDetails(
        errorType: String(describing: type(of: error)),
        message: error.localizedDescription,
        stack: Thread.callStackSymbols.joined(separator: "\n"),
        platform: "ios",
        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
        component: component
    )

    let report = ErrorReport(error: errorDetails)

    guard let url = URL(string: "https://your-app.com/api/v1/mobile_errors"),
          let jsonData = try? JSONEncoder().encode(report) else {
        return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
    request.httpBody = jsonData

    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            print("Failed to report error: \(error)")
        }
    }.resume()
}
```

### Kotlin (Android)

```kotlin
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

@Serializable
data class ErrorReport(val error: ErrorDetails)

@Serializable
data class ErrorDetails(
    val error_type: String,
    val message: String,
    val stack: String?,
    val platform: String,
    val app_version: String,
    val component: String?
)

suspend fun reportError(error: Throwable, component: String) = withContext(Dispatchers.IO) {
    val errorDetails = ErrorDetails(
        error_type = error::class.simpleName ?: "UnknownError",
        message = error.message ?: "No message",
        stack = error.stackTraceToString(),
        platform = "android",
        app_version = BuildConfig.VERSION_NAME,
        component = component
    )

    val report = ErrorReport(errorDetails)
    val json = Json.encodeToString(ErrorReport.serializer(), report)

    val client = OkHttpClient()
    val mediaType = "application/json; charset=utf-8".toMediaType()
    val body = json.toRequestBody(mediaType)

    val request = Request.Builder()
        .url("https://your-app.com/api/v1/mobile_errors")
        .addHeader("Authorization", "Bearer $authToken")
        .post(body)
        .build()

    try {
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                println("Failed to report error: ${response.code}")
            }
        }
    } catch (e: Exception) {
        println("Failed to report error: ${e.message}")
    }
}
```

### cURL (Testing)

```bash
# Log an error
curl -X POST https://your-app.com/api/v1/mobile_errors \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "error": {
      "error_type": "NetworkError",
      "message": "Failed to fetch user data",
      "stack": "NetworkError: Failed to fetch\n  at fetchUser (api.js:42)",
      "platform": "web",
      "app_version": "2.1.0",
      "component": "UserProfile"
    }
  }'

# List errors
curl -u admin:password \
  "https://your-app.com/error_dashboard/errors?platform=iOS&unresolved=true"

# Get error details
curl -u admin:password \
  https://your-app.com/error_dashboard/errors/123

# Resolve error
curl -X POST -u admin:password \
  -d "resolved_by_name=John Doe" \
  -d "resolution_comment=Fixed in v2.1.1" \
  https://your-app.com/error_dashboard/errors/123/resolve
```

---

# Ruby API

The Ruby API provides Commands, Queries, and Service objects for programmatic error management within Rails applications.

## Configuration API

### RailsErrorDashboard.configure

```ruby
RailsErrorDashboard.configure do |config|
  # See CUSTOMIZATION.md for all options
end
```

## Commands API

### LogError

Log an error to the dashboard.

```ruby
RailsErrorDashboard::Commands::LogError.call(
  error_type: "NoMethodError",
  message: "undefined method 'name' for nil:NilClass",
  backtrace: exception.backtrace,
  occurred_at: Time.current,
  platform: "iOS",  # or "Android", "API", "Web"
  app_version: "2.1.0",
  git_sha: "a3b4c5d6",
  user_id: 123,
  request_url: "/api/users",
  request_params: { id: 1 },
  ip_address: "192.168.1.1",
  user_agent: "Mozilla/5.0..."
)
```

### ResolveError

Mark an error as resolved.

```ruby
RailsErrorDashboard::Commands::ResolveError.call(
  error_id: 123,
  resolved_by: "developer@example.com",
  resolution_comment: "Fixed in PR #456",
  resolution_reference: "https://github.com/org/repo/pull/456"
)
```

### BatchDeleteErrors

Delete multiple errors.

```ruby
RailsErrorDashboard::Commands::BatchDeleteErrors.call(
  error_ids: [1, 2, 3, 4, 5]
)
```

## Query Objects API

### DashboardStats

```ruby
stats = RailsErrorDashboard::Queries::DashboardStats.call

stats[:total_errors]          # Total error count
stats[:errors_today]          # Errors today
stats[:errors_last_7_days]    # Last 7 days
stats[:errors_last_30_days]   # Last 30 days
stats[:top_errors]            # Top 10 error types
stats[:errors_by_platform]    # Grouped by platform
stats[:resolved_count]        # Resolved errors
stats[:unresolved_count]      # Unresolved errors
```

### ErrorsList

```ruby
errors = RailsErrorDashboard::Queries::ErrorsList.call(
  platform: "iOS",
  error_type: "NoMethodError",
  unresolved: true,
  search: "payment"
)
```

### SimilarErrors

```ruby
similar = RailsErrorDashboard::Queries::SimilarErrors.call(
  error_id: 123,
  threshold: 0.6,  # 60% similarity
  limit: 10
)

similar.each do |result|
  result[:error]       # ErrorLog instance
  result[:similarity]  # 0.0 - 1.0
end
```

### PlatformComparison

```ruby
comparison = RailsErrorDashboard::Queries::PlatformComparison.new(days: 7)

comparison.error_rate_by_platform
comparison.platform_stability_scores
comparison.platform_health_summary("iOS")
comparison.cross_platform_errors
```

### ErrorCorrelation

```ruby
correlation = RailsErrorDashboard::Queries::ErrorCorrelation.new(days: 30)

correlation.errors_by_version
correlation.problematic_releases
correlation.multi_error_users
correlation.time_correlated_errors
```

## Models API

### ErrorLog

```ruby
error = RailsErrorDashboard::ErrorLog.find(123)

# Attributes
error.error_type       # "NoMethodError"
error.message          # Error message
error.backtrace        # Stack trace
error.platform         # "iOS", "Android", etc.
error.app_version      # "2.1.0"
error.occurrence_count # How many times occurred
error.resolved?        # Boolean
error.severity         # :critical, :high, :medium, :low

# Associations
error.similar_errors(threshold: 0.6)
error.co_occurring_errors(window_minutes: 5)
error.error_cascades(min_probability: 0.5)
error.occurrence_pattern(days: 30)
error.error_bursts(days: 7)
```

## Service Objects API

### PatternDetector

```ruby
# Cyclical patterns
pattern = RailsErrorDashboard::Services::PatternDetector.analyze_cyclical_pattern(
  error_type: "NoMethodError",
  platform: "iOS",
  days: 30
)

pattern[:pattern_type]        # :business_hours, :night, :weekend, :uniform
pattern[:pattern_strength]    # 0.0 - 1.0
pattern[:peak_hours]          # [9, 10, 11, 14, 15]
pattern[:hourly_distribution] # { 0 => 5, 1 => 3, ... }

# Bursts
bursts = RailsErrorDashboard::Services::PatternDetector.detect_bursts(
  error_type: "NoMethodError",
  platform: "iOS",
  days: 7
)
```

### CascadeDetector

```ruby
result = RailsErrorDashboard::Services::CascadeDetector.call(
  lookback_hours: 24
)

result[:detected]  # Number of new cascades
result[:updated]   # Number of updated cascades
```

### BaselineCalculator

```ruby
RailsErrorDashboard::Services::BaselineCalculator.calculate_all_baselines
```

## Complete Reference

For more details, see the source code or inline documentation (YARD format).

**Models**: `app/models/rails_error_dashboard/`
**Commands**: `lib/rails_error_dashboard/commands/`
**Queries**: `lib/rails_error_dashboard/queries/`
**Services**: `lib/rails_error_dashboard/services/`
