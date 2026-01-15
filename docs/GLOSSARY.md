# Rails Error Dashboard - Glossary

A comprehensive guide to terms, concepts, and terminology used throughout the Rails Error Dashboard documentation.

---

## Core Concepts

### Error Log
An individual occurrence of an error captured by the dashboard. Each error log contains the exception class, message, backtrace, context, and metadata.

### Error Group
Errors with identical stack traces are automatically grouped together. The system tracks total occurrences, first seen, last seen, and provides a single view for related errors.

### Deduplication
The process of identifying and grouping identical errors using SHA-256 hashing of the normalized stack trace. Prevents duplicate error entries in the database.

### Hash Signature
A unique SHA-256 hash generated from an error's normalized backtrace. Used for error deduplication and grouping.

### Occurrence Count
The number of times a specific error (identified by hash signature) has been logged. Incremented atomically using pessimistic locking.

### Context
Additional information captured with an error, including:
- Request details (URL, HTTP method, parameters, headers)
- User information (ID, email, IP address)
- Application state (session data, environment variables)
- Platform and version information

---

## Severity Levels

### Critical
Highest severity. Errors that require immediate attention:
- Payment processing failures
- Security breaches
- Data corruption
- Service outages

**Default critical error types**: `SecurityError`, `NoMemoryError`, `SystemStackError`, `SignalException`, `ActiveRecord::StatementInvalid`, `LoadError`, `SyntaxError`, `ActiveRecord::ConnectionNotEstablished`, `Redis::ConnectionError`, `OpenSSL::SSL::SSLError`

Custom severity rules can override defaults.

### High
Serious errors that should be addressed soon:
- Database connection failures
- Third-party API failures
- Authentication errors
- Missing critical data

**Default high severity error types**: `ActiveRecord::RecordNotFound`, `ArgumentError`, `TypeError`, `NoMethodError`, `NameError`, `ZeroDivisionError`, `FloatDomainError`, `IndexError`, `KeyError`, `RangeError`

Custom severity rules can override defaults.

### Medium
Moderate errors that affect functionality:
- 404 Not Found (when unexpected)
- Invalid user input
- Missing optional resources
- Deprecated method calls

**Default medium severity error types**: `ActiveRecord::RecordInvalid`, `Timeout::Error`, `Net::ReadTimeout`, `Net::OpenTimeout`, `ActiveRecord::RecordNotUnique`, `JSON::ParserError`, `CSV::MalformedCSVError`, `Errno::ECONNREFUSED`

### Low
Minor errors or expected failures:
- User-initiated cancellations
- Preview mode errors
- Development-only warnings

**Default**: All other error types default to low severity unless matched by critical/high/medium rules or custom severity rules.

---

## Workflow States

### New
Default state. Error has not been addressed. Appears in the main error list.

**Status**: `new` (database column default)

**Valid transitions**: Can move to `in_progress`, `investigating`, or `wont_fix`.

### In Progress
Someone is actively working on fixing the error. Can be assigned to a team member.

**Status**: `in_progress`

**Valid transitions**: Can move to `investigating`, `resolved`, or back to `new`.

### Investigating
Team is analyzing the error to understand root cause.

**Status**: `investigating`

**Valid transitions**: Can move to `resolved`, `in_progress`, or `wont_fix`.

### Resolved
Error has been fixed. Removed from main list but still searchable. If the error occurs again, it automatically reopens to `new` status.

**Status**: `resolved`

**Valid transitions**: Can reopen to `new` if error recurs.

### Won't Fix
Error is intentionally not being fixed. Removed from main list. Can be reopened if needed.

**Status**: `wont_fix`

**Valid transitions**: Can reopen to `new`.

### Snoozed (Not a Status)
Snoozed is not a status field but a separate `snoozed_until` datetime column. Errors can be snoozed while in any status. Automatically becomes visible again when `snoozed_until` time expires.

---

## Features

### Async Logging
Error logging happens in a background job instead of blocking the request. Reduces performance impact from ~10-50ms to ~1-2ms per error.

**Adapters**: Sidekiq, Solid Queue, or Rails' built-in `:async` adapter.

### Sampling
Only log a percentage of non-critical errors. Useful for high-traffic applications to reduce database load. Critical errors always bypass sampling.

**Example**: `sampling_rate = 0.1` logs 10% of errors.

### Backtrace Limiting
Truncate error backtraces to reduce storage size. Default is 50 lines, configurable down to 10-20 for high-volume apps.

### Baseline Monitoring
Statistical anomaly detection that compares current error rates against historical baselines. Alerts when error rates exceed 2 standard deviations from the mean.

**Metrics**: Mean, standard deviation, 95th percentile.

### Platform Comparison
Compare error rates and stability across different platforms (iOS, Android, Web, API). Calculates stability scores and health status.

### Error Correlation
Analyze relationships between errors and:
- **Release correlation**: Errors introduced in specific app versions
- **User correlation**: Users experiencing multiple error types
- **Co-occurring errors**: Errors that happen together

### Cascade Detection
Identify parent-child error relationships where one error triggers subsequent errors. Helps find root causes.

**Example**: Database connection timeout → Multiple record not found errors

### Occurrence Patterns
Detect cyclical patterns in error occurrences:
- **Hourly patterns**: Errors during peak hours
- **Daily patterns**: Weekend vs weekday differences
- **Burst detection**: Sudden spikes in error rates

### Fuzzy Error Matching
Find similar errors even if they're not exact duplicates using:
- **Jaccard similarity**: Compare error message and backtrace tokens
- **Levenshtein distance**: Measure string similarity

### Priority Scoring
Automatic calculation of error priority based on:
- Severity level (weight: 40%)
- Occurrence count (weight: 30%)
- Recency (weight: 20%)
- User impact (weight: 10%)

---

## Database

### Abstract Base Class
Rails pattern for routing specific models to different databases. Used for multi-database support.

```ruby
class ErrorsRecord < ActiveRecord::Base
  self.abstract_class = true
  connects_to database: { writing: :errors, reading: :errors }
end
```

### Composite Index
Database index on multiple columns. Improves query performance for common filter combinations.

**Example**: `(application_id, occurred_at)` for time-range queries per app.

### Pessimistic Locking
Database row-level locking using `SELECT FOR UPDATE`. Prevents race conditions during error deduplication.

### Connection Pooling
Reusable database connections. Rails manages a pool of connections shared across requests. Critical for multi-database setups.

---

## Multi-App Support

### Application
A registered application instance in the dashboard. Created automatically from `APP_NAME` environment variable or manual configuration.

### Application Name
Unique identifier for each application. Used to filter and separate errors across multiple apps sharing one dashboard.

**Sources**:
1. `APP_NAME` environment variable (recommended)
2. `config.application_name` (manual)
3. `Rails.application.class.module_parent_name` (fallback)

### Shared Database
Single database storing errors from multiple applications. Each error is tagged with `application_id`.

### Separate Database
Dedicated error database, separate from the main application database. Improves performance and isolates error data.

---

## Notifications

### Webhook
HTTP POST callback sent when specific events occur. Used for Slack, Discord, and custom integrations.

### Notification Channel
Delivery method for error alerts:
- **Slack**: Team chat notifications
- **Discord**: Server/channel notifications
- **Email**: Direct email alerts
- **PagerDuty**: Incident management for critical errors
- **Custom**: Your own webhook endpoints

### Notification Throttling
Rate limiting to prevent alert fatigue. Example: Baseline alerts limited to once per hour per error type.

### Severity Threshold
Minimum severity level required to trigger a notification. Example: PagerDuty only receives critical errors.

---

## Real-Time Updates

### Turbo Streams
Hotwire/Turbo feature for real-time page updates without JavaScript. Broadcasts DOM changes over WebSockets or SSE.

### Broadcast
Server-initiated update sent to connected clients. Used to update error lists and statistics in real-time.

### ActionCable
Rails' WebSocket framework. Powers real-time broadcasts in the dashboard.

---

## Plugin System

### Plugin
Custom extension that hooks into error dashboard lifecycle events. Used for custom integrations, metrics, or audit logging.

### Plugin Registry
Central registry managing all registered plugins. Ensures plugins execute safely without breaking error logging.

### Lifecycle Hooks
Events that trigger plugin callbacks:
- `on_error_logged`: When an error is first captured
- `on_error_resolved`: When an error is marked as resolved
- `on_error_ignored`: When an error is marked as ignored
- `on_error_assigned`: When an error is assigned to someone
- `on_error_reopened`: When a resolved error occurs again

### Safe Execution
Plugin methods wrapped in error handling to prevent plugin failures from breaking core functionality.

---

## Configuration

### Initializer
Ruby file in `config/initializers/` that runs at Rails startup. Used for gem configuration.

**Location**: `config/initializers/rails_error_dashboard.rb`

### Configuration Block
DSL for setting gem options:

```ruby
RailsErrorDashboard.configure do |config|
  config.option_name = value
end
```

### Environment Variables
System-level variables accessed via `ENV['NAME']`. Used for secrets and environment-specific settings.

**Best practice**: Use `.env` files with `dotenv-rails` gem in development.

### Feature Flags
Boolean configuration options that enable/disable specific features:
- `enable_slack_notifications`
- `enable_baseline_alerts`
- `enable_similar_errors`
- `enable_platform_comparison`

---

## Performance

### N+1 Query
Performance anti-pattern where a query is executed once for each item in a collection. Rails Error Dashboard uses eager loading to prevent this.

**Solution**: `.includes(:application)` on error queries.

### Eager Loading
Preload associated records in a single query instead of multiple queries. Uses Rails' `includes`, `preload`, or `eager_load`.

### Caching
Temporary storage of computed results. Dashboard uses:
- **Stats caching**: 1-minute TTL for dashboard statistics
- **Application lookup caching**: 1-hour TTL for app names

### Background Job
Asynchronous task executed outside the request-response cycle. Used for error logging, notifications, and data cleanup.

---

## Security

### HTTP Basic Auth
Simple authentication requiring username and password. Used to protect dashboard access.

**Implementation**: `authenticate_or_request_with_http_basic`

### XSS (Cross-Site Scripting)
Security vulnerability where user input is rendered as HTML/JavaScript. Dashboard sanitizes all user-provided content.

**Protection**: `json_escape`, `sanitize`, HTML escaping in ERB.

### SQL Injection
Security vulnerability where user input is executed as SQL. Rails protects against this with parameterized queries.

**Protection**: ActiveRecord's query interface, never raw SQL with string interpolation.

### Mass Assignment
Security vulnerability where unwanted attributes are updated. Rails protects with strong parameters.

**Protection**: Permitted parameters in controllers.

---

## Testing

### RSpec
Ruby testing framework. Rails Error Dashboard has 935+ tests covering models, controllers, services, and integration.

### Factory Bot
Test data generation. Creates realistic test records for errors, applications, and users.

### Test Coverage
Percentage of code executed during tests. Measured with SimpleCov.

**Current**: 90%+ coverage target.

### Integration Test
Test that verifies multiple components working together. Example: Error capture → Database save → Notification sent.

---

## API

### REST API
HTTP-based API following REST principles. Dashboard provides endpoints for:
- Creating errors
- Querying errors
- Updating error status
- Retrieving statistics

### API Authentication
HTTP Basic Auth required for all API endpoints. Same credentials as dashboard UI.

### JSON Response
Structured data format for API responses. Includes status codes, data payload, and error messages.

---

## Deployment

### Migration
Database schema change. Rails Error Dashboard includes migrations for creating tables and indexes.

**Run**: `rails db:migrate`

### Zero-Downtime Deploy
Deployment strategy where new code is deployed without stopping the application. Requires backward-compatible migrations.

### Rollback
Reverting to a previous version after a failed deployment. Rails Error Dashboard supports database rollbacks via migration down methods.

---

## Common Abbreviations

- **TTL**: Time To Live (cache expiration)
- **MTTR**: Mean Time To Resolution (average time to fix errors)
- **SHA**: Secure Hash Algorithm (for hash signatures)
- **HTTP**: HyperText Transfer Protocol
- **SSL**: Secure Sockets Layer (for HTTPS)
- **API**: Application Programming Interface
- **UI**: User Interface
- **CRUD**: Create, Read, Update, Delete
- **DSL**: Domain-Specific Language
- **ENV**: Environment (variables)
- **DB**: Database
- **DDL**: Data Definition Language (migrations)
- **ORM**: Object-Relational Mapping (ActiveRecord)

---

## Additional Resources

- **[Configuration Guide](guides/CONFIGURATION.md)** - Complete configuration reference
- **[Features Documentation](FEATURES.md)** - All feature details
- **[API Reference](API_REFERENCE.md)** - API endpoint documentation
- **[Plugin System](PLUGIN_SYSTEM.md)** - Building custom plugins

---

**Need clarification on a term?** [Open an issue](https://github.com/AnjanJ/rails_error_dashboard/issues) or [start a discussion](https://github.com/AnjanJ/rails_error_dashboard/discussions).
