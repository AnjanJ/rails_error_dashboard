---
layout: default
title: "Error Sampling and Filtering Guide"
permalink: /docs/guides/ERROR_SAMPLING_AND_FILTERING
---

# Error Sampling and Filtering Guide

This guide explains how to use error sampling and filtering in RailsErrorDashboard to manage high-volume error logging and reduce noise.

## Table of Contents

- [What is Error Sampling?](#what-is-error-sampling)
- [What are Ignored Exceptions?](#what-are-ignored-exceptions)
- [When to Use Each Feature](#when-to-use-each-feature)
- [Error Sampling Configuration](#error-sampling-configuration)
- [Ignored Exceptions Configuration](#ignored-exceptions-configuration)
- [Best Practices](#best-practices)
- [Performance Impact](#performance-impact)
- [Common Use Cases](#common-use-cases)

---

## What is Error Sampling?

Error sampling allows you to log only a percentage of non-critical errors, reducing database growth and processing overhead in high-traffic applications.

**Key Features:**
- Sample rate from 0% to 100%
- **Critical errors are ALWAYS logged** (regardless of sample rate)
- Probabilistic sampling ensures fair distribution
- Helps manage costs in high-volume applications

**Example:** With a 10% sample rate (0.1):
- 100 `ArgumentError` exceptions → ~10 logged
- 100 `SecurityError` exceptions → **100 logged** (critical errors bypass sampling)

---

## What are Ignored Exceptions?

Ignored exceptions allow you to completely skip logging certain exception types that add no value to your dashboard.

**Key Features:**
- Support exact class name matching
- Support regex pattern matching
- Support inheritance (ignores subclasses too)
- Reduces noise from expected/handled errors

**Example:** Ignore routing errors and authentication failures:
```ruby
config.ignored_exceptions = [
  "ActionController::RoutingError",
  "ActionController::InvalidAuthenticityToken"
]
```

---

## When to Use Each Feature

### Use **Sampling** When:
- ✅ You have high error volume (thousands per day)
- ✅ You want to see trends but don't need every occurrence
- ✅ You want to reduce storage costs
- ✅ You still want to see all critical errors

### Use **Ignored Exceptions** When:
- ✅ Certain errors are expected and handled (404s, CSRF failures)
- ✅ You want to completely eliminate noise
- ✅ Errors are logged elsewhere (e.g., web server logs)
- ✅ You never need to see specific error types

### Use **Both** When:
- ✅ High-volume application with some expected errors
- ✅ Need to optimize both storage and performance
- ✅ Want granular control over what gets logged

---

## Error Sampling Configuration

### Basic Configuration

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  # Sample 10% of non-critical errors
  config.sampling_rate = 0.1  # 10%
end
```

### Sampling Rates

| Rate | Percentage | Use Case |
|------|-----------|----------|
| `1.0` | 100% (default) | Development, low-volume apps |
| `0.5` | 50% | Moderate traffic, want half the errors |
| `0.1` | 10% | High traffic, just need trends |
| `0.01` | 1% | Very high traffic, extremely large scale |
| `0.0` | 0% | Don't log non-critical errors (not recommended) |

### Critical Errors Always Logged

These errors **bypass sampling** and are **always logged at 100%**:

```ruby
# From ErrorLog::CRITICAL_ERROR_TYPES
CRITICAL_ERROR_TYPES = [
  "SecurityError",           # Security breaches
  "NoMemoryError",          # Out of memory
  "SystemStackError",       # Stack overflow
  "SignalException",        # System signals
  "ActiveRecord::StatementInvalid"  # Database errors
]
```

**Why?** Critical errors indicate serious system problems that need immediate attention, regardless of sample rate.

### Environment-Specific Configuration

```ruby
RailsErrorDashboard.configure do |config|
  config.sampling_rate = case Rails.env
  when 'development'
    1.0   # Log everything in dev
  when 'staging'
    0.5   # 50% in staging
  when 'production'
    0.1   # 10% in production
  else
    1.0   # Default to full logging
  end
end
```

### Dynamic Sampling Based on Load

```ruby
# Advanced: Adjust sampling based on error volume
RailsErrorDashboard.configure do |config|
  # Check recent error count
  recent_errors = RailsErrorDashboard::ErrorLog
    .where("occurred_at >= ?", 1.hour.ago)
    .count

  config.sampling_rate = case recent_errors
  when 0..100
    1.0   # Low volume: log everything
  when 101..1000
    0.5   # Moderate: 50%
  when 1001..10000
    0.1   # High: 10%
  else
    0.01  # Very high: 1%
  end
end
```

---

## Ignored Exceptions Configuration

### Basic Configuration

```ruby
RailsErrorDashboard.configure do |config|
  config.ignored_exceptions = [
    "ActionController::RoutingError",
    "ActionController::InvalidAuthenticityToken",
    "ActiveRecord::RecordNotFound"
  ]
end
```

### Exact Class Matching

Ignores the exact exception class and all its subclasses:

```ruby
config.ignored_exceptions = [
  "ActiveRecord::RecordNotFound"
]

# This will ignore:
# - ActiveRecord::RecordNotFound
# - Any custom subclasses of RecordNotFound
```

### Regex Pattern Matching

Use regex for flexible pattern matching:

```ruby
config.ignored_exceptions = [
  /^ActionController::/,     # All ActionController exceptions
  /NotFound$/,              # Any exception ending with "NotFound"
  /^Custom::.*Error$/       # All errors in Custom:: namespace
]
```

### Mixed Configuration

Combine exact matches and regex patterns:

```ruby
config.ignored_exceptions = [
  # Exact matches
  "ActionController::RoutingError",
  "ActionController::InvalidAuthenticityToken",

  # Regex patterns
  /^Pundit::/,               # All authorization errors
  /RateLimitExceeded$/       # Any rate limit errors
]
```

### Common Exceptions to Ignore

```ruby
config.ignored_exceptions = [
  # Routing and controller errors (expected in web apps)
  "ActionController::RoutingError",
  "ActionController::InvalidAuthenticityToken",
  "ActionController::UnknownFormat",

  # Record not found (often expected)
  "ActiveRecord::RecordNotFound",

  # Bot/scanner traffic
  /PhusionPassenger::/,

  # Authentication (already handled)
  "Devise::Failure::Unauthenticated"
]
```

---

## Best Practices

### 1. Start Conservative, Then Optimize

**Week 1:** Observe with full logging
```ruby
config.sampling_rate = 1.0
config.ignored_exceptions = []
```

**Week 2:** Identify noisy exceptions
```ruby
# Check most common errors
RailsErrorDashboard::ErrorLog
  .group(:error_type)
  .count
  .sort_by { |_, v| -v }
  .first(10)
```

**Week 3:** Apply targeted filtering
```ruby
config.ignored_exceptions = [
  "ActionController::RoutingError"  # 50% of all errors
]
```

**Week 4:** Add sampling if needed
```ruby
config.sampling_rate = 0.1  # Still seeing 1000s per day
```

### 2. Monitor Ignored/Sampled Errors

```ruby
# Track what's being filtered
RailsErrorDashboard.configure do |config|
  config.on_error_ignored = ->(exception) {
    Rails.logger.info("Ignored error: #{exception.class}")
  }

  config.on_error_sampled_out = ->(exception) {
    Rails.logger.info("Sampled out: #{exception.class}")
  }
end
```

### 3. Document Your Decisions

```ruby
RailsErrorDashboard.configure do |config|
  # Ignore routing errors - we track these in nginx logs
  # Decision: 2025-01-15, @username
  # Reasoning: 90% of errors are bot traffic
  config.ignored_exceptions = [
    "ActionController::RoutingError"
  ]

  # Sample at 10% - we have 50K errors/day
  # Decision: 2025-01-20, @username
  # Reasoning: Storage costs too high, trends are sufficient
  config.sampling_rate = 0.1
end
```

### 4. Review Periodically

Set calendar reminders to review your configuration:

**Monthly:**
- Check if ignored exceptions are still relevant
- Verify critical errors are being logged
- Adjust sample rate based on volume

**Quarterly:**
- Review most common errors
- Update ignored list
- Consider if sampling rate needs adjustment

### 5. Don't Over-Filter

⚠️ **Warning:** Be careful not to hide important errors!

**Bad:**
```ruby
config.ignored_exceptions = [
  /Error$/,  # TOO BROAD - ignores ALL errors!
]
```

**Good:**
```ruby
config.ignored_exceptions = [
  "ActionController::RoutingError",  # Specific and intentional
  "MyApp::ExpectedBusinessError"     # Custom exception we handle
]
```

---

## Performance Impact

### Error Sampling

**Before Sampling** (1.0 = 100%):
- 10,000 errors/day
- Processing time: ~2 seconds/error
- Total processing: 20,000 seconds/day (~5.5 hours)
- Database writes: 10,000/day

**After Sampling** (0.1 = 10%):
- 1,000 errors logged/day
- Processing time: ~2 seconds/error
- Total processing: 2,000 seconds/day (~33 minutes)
- Database writes: 1,000/day
- **Savings: 90% less processing and storage**

### Ignored Exceptions

**Before Ignoring**:
- Check in LogError → Check sampling → Create ErrorLog → Save to DB
- Time: ~2ms per ignored error

**After Ignoring**:
- Check in LogError → Return nil
- Time: ~0.01ms per ignored error
- **Savings: 99.5% faster for ignored errors**

### Combined Impact

High-traffic app logging 100,000 errors/day:

| Configuration | Errors Logged | Processing Time | Storage/Day |
|--------------|---------------|----------------|-------------|
| No filtering | 100,000 | ~55 hours | ~500 MB |
| Ignore 50% | 50,000 | ~27 hours | ~250 MB |
| Ignore 50% + 10% sampling | 5,000 | ~2.7 hours | ~25 MB |
| **Savings** | **95%** | **95%** | **95%** |

---

## Common Use Cases

### Use Case 1: High-Traffic E-Commerce Site

**Challenge:** 100K errors/day, mostly 404s and CSRF failures

**Solution:**
```ruby
RailsErrorDashboard.configure do |config|
  # Ignore expected errors from bots/scanners
  config.ignored_exceptions = [
    "ActionController::RoutingError",          # 50K/day
    "ActionController::InvalidAuthenticityToken"  # 30K/day
  ]

  # Sample remaining 20K errors at 10%
  config.sampling_rate = 0.1  # 2K/day logged

  # Still logs ALL critical errors (SecurityError, etc.)
end
```

**Result:** 100K → 2K errors/day (98% reduction)

---

### Use Case 2: API with Rate Limiting

**Challenge:** Rate limit errors filling up dashboard

**Solution:**
```ruby
RailsErrorDashboard.configure do |config|
  # Ignore rate limit errors (tracked separately)
  config.ignored_exceptions = [
    /RateLimitExceeded$/,
    "Rack::Attack::Throttle"
  ]

  # Keep full logging for actual API errors
  config.sampling_rate = 1.0
end
```

**Result:** Only real errors are logged, rate limits tracked elsewhere

---

### Use Case 3: Microservices Architecture

**Challenge:** Multiple services, some very noisy

**Solution:**
```ruby
# In noisy service (user-facing API)
RailsErrorDashboard.configure do |config|
  config.ignored_exceptions = [
    "ActionController::RoutingError",
    /NotFound$/
  ]
  config.sampling_rate = 0.1  # 10%
end

# In critical service (payment processing)
RailsErrorDashboard.configure do |config|
  config.ignored_exceptions = []  # Log everything
  config.sampling_rate = 1.0      # 100%
end
```

**Result:** Critical services get full visibility, noisy services are filtered

---

### Use Case 4: Development vs Production

**Challenge:** Need different configurations per environment

**Solution:**
```ruby
RailsErrorDashboard.configure do |config|
  if Rails.env.production?
    # Production: Aggressive filtering
    config.ignored_exceptions = [
      "ActionController::RoutingError",
      "ActionController::InvalidAuthenticityToken",
      "ActiveRecord::RecordNotFound"
    ]
    config.sampling_rate = 0.1

  elsif Rails.env.staging?
    # Staging: Moderate filtering
    config.ignored_exceptions = [
      "ActionController::RoutingError"
    ]
    config.sampling_rate = 0.5

  else
    # Development/Test: No filtering
    config.ignored_exceptions = []
    config.sampling_rate = 1.0
  end
end
```

---

### Use Case 5: Gradual Rollout

**Challenge:** Testing filtering in production safely

**Solution:**
```ruby
# Week 1: Monitor only
RailsErrorDashboard.configure do |config|
  config.ignored_exceptions = []
  config.sampling_rate = 1.0

  # Log what WOULD be filtered
  config.on_candidate_for_ignoring = ->(exception) {
    if exception.is_a?(ActionController::RoutingError)
      Rails.logger.info("Would ignore: #{exception.class}")
    end
  }
end

# Week 2: Enable filtering
RailsErrorDashboard.configure do |config|
  config.ignored_exceptions = [
    "ActionController::RoutingError"
  ]
end

# Week 3: Add sampling
RailsErrorDashboard.configure do |config|
  config.ignored_exceptions = [
    "ActionController::RoutingError"
  ]
  config.sampling_rate = 0.5  # Start at 50%
end

# Week 4: Full optimization
RailsErrorDashboard.configure do |config|
  config.ignored_exceptions = [
    "ActionController::RoutingError",
    "ActionController::InvalidAuthenticityToken"
  ]
  config.sampling_rate = 0.1  # 10%
end
```

---

## Troubleshooting

### Problem: Not seeing any errors

**Possible causes:**
1. Sampling rate too low
2. All errors are being ignored
3. All errors are critical (bypassing sample rate)

**Solution:**
```ruby
# Temporarily disable filtering
config.ignored_exceptions = []
config.sampling_rate = 1.0

# Check what's happening
RailsErrorDashboard::ErrorLog.last(10)
```

---

### Problem: Still seeing ignored errors

**Possible causes:**
1. Typo in exception class name
2. Exception inheritance not working
3. Regex pattern incorrect

**Solution:**
```ruby
# Test your configuration
exception = ActionController::RoutingError.new("test")
config = RailsErrorDashboard.configuration

# Should return true if properly ignored
config.ignored_exceptions.any? do |ignored|
  case ignored
  when String
    exception.is_a?(ignored.constantize)
  when Regexp
    exception.class.name.match?(ignored)
  else
    false
  end
end
```

---

### Problem: Sampling not working

**Possible causes:**
1. All errors are critical (bypass sampling)
2. Sample rate set incorrectly
3. Randomization not working

**Solution:**
```ruby
# Check if errors are critical
error_log = RailsErrorDashboard::ErrorLog.last
error_log.critical?  # Returns true if critical

# Verify configuration
RailsErrorDashboard.configuration.sampling_rate  # Should be 0.0 to 1.0

# Test with non-critical error
100.times do
  begin
    raise ArgumentError, "test"
  rescue => e
    RailsErrorDashboard::ErrorLog.log_error(e)
  end
end

# Should see roughly (sampling_rate * 100) errors
RailsErrorDashboard::ErrorLog.where(error_type: "ArgumentError").count
```

---

## Additional Resources

- [Configuration Guide](CONFIGURATION.md)
- [Performance Tuning](DATABASE_OPTIMIZATION.md)
- [Backtrace Limiting](BACKTRACE_LIMITING.md)
- [Async Logging](../README.md#async-logging)

---

## FAQ

**Q: Will sampling affect my ability to debug issues?**
A: For trends and patterns, sampling is sufficient. If you need exact counts, keep sampling at 100% or only sample low-priority errors.

**Q: Can I ignore critical errors?**
A: Technically yes (they'll match your ignore patterns), but it's strongly discouraged. Critical errors indicate serious problems.

**Q: Does ignored exception checking slow down my app?**
A: No. The check happens in microseconds and returns early before any database operations.

**Q: Can I change sampling rate without restarting?**
A: Configuration is loaded at boot time. Changes require an application restart.

**Q: What happens to sampled-out errors?**
A: They are discarded immediately and never touch the database. No record is created.

**Q: Can I see what's being filtered?**
A: Add logging to your configuration (see "Monitor Ignored/Sampled Errors" section above).
