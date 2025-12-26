# Platform Comparison Guide

This guide covers the platform comparison and health analytics features, which enable side-by-side comparison of error metrics across iOS, Android, API, and Web platforms.

**⚙️ Optional Feature** - Platform comparison is disabled by default. Enable it in your initializer:

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_platform_comparison = true
end
```

## Table of Contents

- [Overview](#overview)
- [Platform Health Metrics](#platform-health-metrics)
- [Stability Scoring](#stability-scoring)
- [Cross-Platform Analysis](#cross-platform-analysis)
- [Platform-Specific Baselines](#platform-specific-baselines)
- [Use Cases](#use-cases)
- [Configuration](#configuration)
- [Best Practices](#best-practices)

## Overview

Platform comparison helps you answer critical questions:
- **Which platform is most stable?** - Compare health scores
- **Where should we focus engineering effort?** - Identify problematic platforms
- **Are errors platform-specific or cross-platform?** - Find root causes faster
- **How do platforms compare over time?** - Track improvement trends

### Supported Platforms

The dashboard tracks errors across:
- **iOS** - iPhone and iPad applications
- **Android** - Android applications
- **API** - Backend API errors
- **Web** - Web application errors
- **Unknown** - Errors without platform metadata

## Platform Health Metrics

### Accessing Platform Comparison

Navigate to **Platform Health** in the sidebar, or:

```ruby
# In your code
comparison = RailsErrorDashboard::Queries::PlatformComparison.new(days: 7)
```

### Core Metrics

Each platform displays:

#### 1. Total Errors
**Description**: Total error count for the time period

**Calculation**: Sum of all errors for the platform
```ruby
ErrorLog.where(platform: "iOS", "occurred_at >= ?", 7.days.ago).count
```

**Interpretation**:
- High count = Platform experiencing issues
- Compare across platforms to identify which needs attention

#### 2. Critical Errors
**Description**: Count of errors with `:critical` severity

**Calculation**: Errors with severity = :critical
```ruby
errors.select { |error| error.severity == :critical }.count
```

**Note**: Severity is a computed method, not a database column. It's based on:
- Custom severity rules (if configured)
- CRITICAL_ERROR_TYPES constant
- Impact assessment

**Interpretation**:
- Even one critical error needs immediate attention
- Compare critical rate: critical_errors / total_errors

#### 3. Resolution Rate
**Description**: Percentage of errors that have been resolved

**Calculation**:
```ruby
resolved = errors.where(resolved: true).count
total = errors.count
resolution_rate = (resolved.to_f / total * 100).round(1)
```

**Interpretation**:
- **>80%**: Good - Team is resolving issues
- **50-80%**: Fair - Some backlog building
- **<50%**: Poor - Issues accumulating

#### 4. Stability Score
**Description**: Overall platform health score (0-100)

**Calculation**: Weighted combination of:
- **70%** - Error count (normalized)
- **30%** - Resolution time (normalized)

See [Stability Scoring](#stability-scoring) for details.

**Interpretation**:
- **90-100**: Excellent health
- **70-90**: Good health
- **50-70**: Fair health, needs attention
- **<50**: Poor health, urgent action needed

#### 5. Error Velocity
**Description**: How error rate is changing (percentage change)

**Calculation**:
```ruby
current_period_count = errors_last_N_days
previous_period_count = errors_previous_N_days
velocity = ((current - previous) / previous * 100).round(1)
```

**Interpretation**:
- **Positive** = Errors increasing 📈 (concerning)
- **Negative** = Errors decreasing 📉 (improving)
- **>20%** = Significant increase (red flag)
- **<-20%** = Significant improvement (celebrate!)

#### 6. Health Status
**Description**: Quick visual indicator of platform health

**Calculation**:
```ruby
if stability_score >= 80 && velocity <= 0
  :healthy
elsif stability_score >= 60
  :fair
else
  :poor
end
```

**Indicators**:
- 🟢 **Healthy** - High stability, stable or decreasing errors
- 🟡 **Fair** - Moderate stability, may need attention
- 🔴 **Poor** - Low stability or rapidly increasing errors

## Stability Scoring

### Algorithm

The stability score combines two factors:

```ruby
def calculate_stability_score(platform)
  # Factor 1: Error count (70% weight)
  # Normalize: fewer errors = higher score
  max_errors = all_platforms.max(&:error_count)
  error_score = 1.0 - (platform_errors.to_f / max_errors)

  # Factor 2: Resolution time (30% weight)
  # Normalize: faster resolution = higher score
  avg_resolution_time = platform.average_resolution_time_hours
  max_resolution_time = 168  # 1 week max
  resolution_score = if avg_resolution_time > 0
    1.0 - (avg_resolution_time / max_resolution_time)
  else
    1.0  # No resolved errors yet, assume good
  end

  # Combine with weights
  score = (error_score * 0.7) + (resolution_score * 0.3)

  # Scale to 0-100
  (score * 100).round(1)
end
```

### Why This Formula?

**Error Count (70% weight)**: Primary indicator of platform health
- Fewer errors = more stable platform
- Normalized against the highest-error platform
- Dominant factor because prevention > cure

**Resolution Time (30% weight)**: Secondary indicator of team responsiveness
- Faster fixes = better process
- Normalized against 1 week (reasonable resolution window)
- Lower weight because it measures response, not prevention

### Example Calculation

**Scenario**:
- iOS: 100 errors, avg resolution 24 hours
- Android: 300 errors, avg resolution 48 hours

**iOS Score**:
```
max_errors = 300
error_score = 1.0 - (100 / 300) = 0.67

avg_resolution = 24 hours
resolution_score = 1.0 - (24 / 168) = 0.86

stability_score = (0.67 * 0.7) + (0.86 * 0.3)
                = 0.469 + 0.258
                = 0.727
                = 72.7/100
```

**Android Score**:
```
error_score = 1.0 - (300 / 300) = 0.0
resolution_score = 1.0 - (48 / 168) = 0.71

stability_score = (0.0 * 0.7) + (0.71 * 0.3)
                = 0.213
                = 21.3/100
```

**Interpretation**: iOS (72.7) is significantly more stable than Android (21.3).

## Cross-Platform Analysis

### What Are Cross-Platform Errors?

Cross-platform errors are the **same error type** occurring on **multiple platforms**.

Example:
```
NoMethodError: undefined method 'name' for nil:NilClass
- Occurs on: iOS, Android, Web
- Indicates: Backend API issue (shared code)
```

### Finding Cross-Platform Errors

```ruby
comparison = RailsErrorDashboard::Queries::PlatformComparison.new(days: 7)
cross_platform = comparison.cross_platform_errors

cross_platform.each do |error_type, data|
  puts "#{error_type}:"
  puts "  Platforms: #{data[:platforms].join(', ')}"
  puts "  Total occurrences: #{data[:total_count]}"

  data[:platform_breakdown].each do |platform, count|
    puts "    #{platform}: #{count} errors"
  end
end
```

**Output**:
```
NoMethodError:
  Platforms: iOS, Android, API
  Total occurrences: 450
    iOS: 200 errors
    Android: 150 errors
    API: 100 errors
```

### Why Cross-Platform Analysis Matters

**1. Root Cause Identification**:
- Cross-platform = Likely backend/API issue
- Platform-specific = Likely client-side issue

**2. Fix Prioritization**:
- Fixing one cross-platform error helps ALL platforms
- High impact, single fix

**3. Testing Strategy**:
- Cross-platform errors need testing on all affected platforms
- Regression testing should cover all platforms

### Platform-Specific vs Cross-Platform

The UI shows this breakdown:

```
iOS Errors:
  NetworkTimeoutError (450 occurrences)
    ✓ Platform-Specific
  NoMethodError (200 occurrences)
    ✗ Cross-Platform (also on: Android, API)
```

**Interpretation**:
- `NetworkTimeoutError` only on iOS → iOS networking issue
- `NoMethodError` everywhere → Backend API issue

## Platform-Specific Baselines

### Why Platform-Specific Baselines?

Different platforms have different normal error rates:
- **iOS**: Typically lower error rates (strict review process)
- **Android**: Often higher due to device fragmentation
- **API**: Different patterns based on traffic
- **Web**: Browser compatibility issues

**Solution**: Calculate separate baselines per platform.

### How It Works

Baselines are calculated for each (error_type, platform) combination:

```ruby
# iOS baseline for NoMethodError
ErrorBaseline.find_by(
  error_type: "NoMethodError",
  platform: "iOS",
  baseline_type: "hourly"
)
# => { mean: 5, std_dev: 2 }

# Android baseline for same error
ErrorBaseline.find_by(
  error_type: "NoMethodError",
  platform: "Android",
  baseline_type: "hourly"
)
# => { mean: 15, std_dev: 5 }
```

**Result**: Anomaly detection is platform-aware:
- iOS: Alert if > 9 errors/hour (5 + 2*2)
- Android: Alert if > 25 errors/hour (15 + 2*5)

### Viewing Platform Baselines

The Platform Health page shows baselines:

```
iOS - NoMethodError
  Current: 12 errors (2.3 std devs above baseline)
  Baseline: 5 ± 2 errors
  Status: 🟡 Elevated

Android - NoMethodError
  Current: 18 errors (0.6 std devs above baseline)
  Baseline: 15 ± 5 errors
  Status: 🟢 Normal
```

## Use Cases

### Scenario 1: Post-Release Health Check

**Question**: "Did the new release affect all platforms equally?"

**Analysis**:
1. Navigate to Platform Health
2. Select time range covering the release
3. Compare error velocity across platforms

**Example**:
```
Release: v2.0.0 deployed Friday 2 PM

Platform Velocity (Fri-Sun vs previous week):
  iOS:     +150% 🔴 (ISSUE!)
  Android: +5%   🟢 (normal)
  API:     +2%   🟢 (normal)
  Web:     +180% 🔴 (ISSUE!)
```

**Conclusion**: iOS and Web builds have issues, Android is fine. Likely a shared codebase change affecting both.

### Scenario 2: Prioritizing Platform Investment

**Question**: "Which platform needs the most engineering resources?"

**Analysis**:
1. View 30-day stability scores
2. Check resolution rates
3. Review error velocity trends

**Example**:
```
Platform Metrics (30 days):
                Stability  Resolution Rate  Velocity
  iOS:          85         75%              -10%
  Android:      45         30%              +45%
  API:          90         90%              -5%
  Web:          70         60%              +5%
```

**Conclusion**: Android needs urgent attention:
- Low stability (45)
- Poor resolution rate (30%)
- Rapidly increasing errors (+45%)

**Action**: Allocate Android team to focus on top errors.

### Scenario 3: Backend vs Client Issue

**Question**: "Is this a backend problem or client problem?"

**Analysis**:
1. View Cross-Platform Errors section
2. Check if error appears on multiple platforms

**Example**:
```
ArgumentError: Missing required parameter 'user_id'

Platforms affected:
  iOS:     120 occurrences
  Android: 95 occurrences
  Web:     150 occurrences
```

**Conclusion**: Cross-platform error → Backend API validation issue
- Not sending user_id from any client
- OR backend expecting user_id but docs don't specify

**Action**: Fix backend validation, update API docs.

### Scenario 4: Platform-Specific Regression

**Question**: "Why is this error only happening on Android?"

**Analysis**:
1. Filter by platform: Android
2. Check Platform-Specific Errors
3. Review error details

**Example**:
```
SQLiteException: database locked (code 5)

Platforms:
  Android: 350 occurrences ✓ Platform-Specific
  (No other platforms affected)
```

**Conclusion**: Android-specific database issue
- Likely concurrent access to local SQLite database
- iOS uses different local storage (Core Data)

**Action**: Investigate Android database access patterns.

### Scenario 5: Monitoring Improvement

**Question**: "Are our fixes improving platform health?"

**Analysis**:
1. View stability score trends over time
2. Compare current vs previous period

**Example**:
```
iOS Stability Score Trend (90 days):
  60 days ago: 60/100
  30 days ago: 70/100
  Current:     85/100

Error Velocity: -40% (decreasing)
```

**Conclusion**: iOS health improving significantly
- Stability up 25 points in 2 months
- Error rate decreasing 40%

**Action**: Document what worked, apply to other platforms.

## Configuration

### Time Period Selection

The UI provides buttons for different lookback periods:

```ruby
# 7-day comparison (default)
comparison = PlatformComparison.new(days: 7)

# 30-day comparison
comparison = PlatformComparison.new(days: 30)

# 90-day comparison
comparison = PlatformComparison.new(days: 90)
```

**Recommendation**: Use 7 days for recent issues, 30 days for trends.

### Custom Analysis

```ruby
# In Rails console
comparison = RailsErrorDashboard::Queries::PlatformComparison.new(days: 14)

# Get all metrics for a platform
ios_health = comparison.platform_health_summary("iOS")
# => { total_errors: 450, critical_errors: 12, stability_score: 75.5, ... }

# Compare error rates
rates = comparison.error_rate_by_platform
# => { "iOS" => 450, "Android" => 780, "API" => 320 }

# Get top errors per platform
top_errors = comparison.top_errors_by_platform(limit: 5)
# => { "iOS" => [["NoMethodError", 120], ...], ... }
```

## Best Practices

### 1. Regular Health Reviews

**Weekly Review**:
- Check platform health scores
- Identify platforms with declining health
- Review cross-platform errors

**Monthly Review**:
- Analyze 30-day stability trends
- Compare resolution rates across platforms
- Plan engineering allocation

### 2. Set Platform Health Goals

**Example Goals**:
- **Target**: All platforms >80 stability score
- **Minimum**: No platform <60 stability score
- **Resolution**: >70% resolution rate on all platforms

Track progress toward goals using the dashboard.

### 3. Prioritize Cross-Platform Fixes

When triaging errors:
1. **High Priority**: Cross-platform + critical
2. **Medium Priority**: Platform-specific + critical OR cross-platform + non-critical
3. **Low Priority**: Platform-specific + non-critical

**Rationale**: Cross-platform fixes have maximum impact.

### 4. Monitor Post-Release

After every release:
1. View Platform Health immediately
2. Check error velocity (should be neutral or negative)
3. Watch for new error types

**Red Flags**:
- Velocity >50% on any platform
- New critical errors
- Stability score drop >10 points

### 5. Use Platform Comparison for Incident Response

During incidents:
```
Step 1: Is it affecting all platforms? (Cross-platform view)
Step 2: Which platform is worst affected? (Error rates)
Step 3: Are errors increasing? (Velocity)
Step 4: What's the impact? (Critical error count)
```

This triage helps you:
- Understand scope quickly
- Route to correct team (iOS/Android/Backend)
- Prioritize response

### 6. Baseline Platform Health

Establish "normal" for each platform:

```
Our Baselines (example):
  iOS:     Stability 85-95, <100 errors/week
  Android: Stability 70-80, <300 errors/week
  API:     Stability 90-95, <50 errors/week
```

Alert when platforms deviate from their baselines.

## Visualizations

### Charts Available

#### 1. Error Rate Bar Chart
**Shows**: Total error count per platform
**Use**: Quick comparison of volume

#### 2. Daily Trend Line Chart
**Shows**: Error count over time per platform
**Use**: Spot trends and anomalies

#### 3. Severity Distribution
**Shows**: Breakdown by severity per platform
**Use**: Understand error composition

#### 4. Resolution Time Chart
**Shows**: Average resolution time per platform
**Use**: Compare team responsiveness

### Reading the Charts

**Error Rate Bar Chart**:
- Tallest bar = Most errors
- Compare relative heights
- Click bar to filter by platform

**Daily Trend**:
- Upward slope = Increasing errors 📈
- Downward slope = Decreasing errors 📉
- Spikes = Incidents or releases
- Flat line = Stable

**Severity Distribution**:
- More red (critical) = Urgent issues
- More yellow (warning) = Technical debt
- More green (info) = Minor issues

## API Reference

### PlatformComparison Query Object

```ruby
comparison = RailsErrorDashboard::Queries::PlatformComparison.new(days: 7)

# Error counts by platform
comparison.error_rate_by_platform
# => { "iOS" => 450, "Android" => 780 }

# Severity breakdown
comparison.severity_distribution_by_platform
# => { "iOS" => { critical: 10, high: 50, ... }, ... }

# Resolution times
comparison.resolution_time_by_platform
# => { "iOS" => 24.5, "Android" => 36.2 }  # hours

# Stability scores (0-100)
comparison.platform_stability_scores
# => { "iOS" => 85.3, "Android" => 62.1 }

# Top errors per platform
comparison.top_errors_by_platform(limit: 10)
# => { "iOS" => [["NoMethodError", 120], ...], ... }

# Cross-platform errors
comparison.cross_platform_errors
# => { "NoMethodError" => { platforms: ["iOS", "Android"], total_count: 450 } }

# Health summary for specific platform
comparison.platform_health_summary("iOS")
# => {
#   total_errors: 450,
#   critical_errors: 12,
#   unresolved_errors: 120,
#   resolution_rate: 73.3,
#   stability_score: 85.3,
#   error_velocity: -15.2,
#   health_status: :healthy
# }

# Error velocity (% change)
comparison.platform_error_velocity
# => { "iOS" => -15.2, "Android" => 23.5 }
```

## Troubleshooting

### "Platform comparison shows no data"

**Cause**: No errors with platform metadata

**Solution**:
```ruby
# Check if errors have platform field
ErrorLog.where.not(platform: nil).count
# If 0, no platform tracking

# Add platform to error logging
RailsErrorDashboard::Commands::LogError.call(
  error_type: "NoMethodError",
  platform: "iOS",  # Add this
  # ...
)
```

### "Stability scores seem wrong"

**Cause**: Formula expects multiple platforms for normalization

**Fix**: Scores are relative to other platforms. With only one platform, score may be 100% or misleading.

**Workaround**: Add dummy data for comparison or ignore scores until multiple platforms have data.

### "Cross-platform errors not showing"

**Cause**: Error types don't match exactly across platforms

**Example**:
```
iOS:     "NoMethodError: undefined method 'name'"
Android: "NoMethodError: undefined method `name`"  # Note: ` vs '
```

**Solution**: Normalize error messages before logging, or use fuzzy matching (see ADVANCED_ERROR_GROUPING.md).

## Further Reading

- [Advanced Error Grouping Guide](ADVANCED_ERROR_GROUPING.md) - Fuzzy matching across platforms
- [Baseline Monitoring Guide](BASELINE_MONITORING.md) - Platform-specific baselines
- [Occurrence Patterns Guide](OCCURRENCE_PATTERNS.md) - Platform-specific patterns
- [Error Correlation Guide](ERROR_CORRELATION.md) - Platform correlation analysis
