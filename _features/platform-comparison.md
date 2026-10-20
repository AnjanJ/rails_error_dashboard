---
layout: default
title: "Platform Comparison Guide"
order: 8
---

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

Platform comparison helps you answer questions like:
- **Which platform is most stable?** - Compare health scores
- **Where should we focus engineering effort?** - Identify problematic platforms
- **Are errors platform-specific or cross-platform?** - Find root causes faster
- **Are errors rising or falling?** - Compare the two halves of the window, and the daily trend

### Supported Platforms

The dashboard tracks errors across:
- **iOS** - Requests whose User-Agent names an iPhone or iPad
- **Android** - Requests whose User-Agent names Android
- **API** - Everything else: other requests, desktop browsers included, and errors raised outside a request
- **Mobile** - Expo requests whose User-Agent names neither iOS nor Android
- **Web** - Web application errors — never auto-assigned: the User-Agent detector yields iOS, Android, Mobile or API, so a desktop browser request lands in API; pass `platform: "Web"` when reporting manually

Any `platform` value you pass when reporting an error is used as is. Errors with no platform value get no card on this page.

## Platform Health Metrics

### Accessing Platform Comparison

Click **Platform** in the sidebar's Health section, or:

```ruby
# In your code
comparison = RailsErrorDashboard::Queries::PlatformComparison.new(days: 7)
```

The page compares platforms over the last 7, 14 or 30 days, for the selected application when one is selected.

### Core Metrics

Each platform with errors in the window gets a card, which displays:

#### 1. Total Errors
**Description**: The platform's error events in the window

**Calculation**: Every event that happened in the window: one per occurrence row, plus events counted
in storm-protection buckets, plus the counts of older error records that have no occurrence rows.
An error first seen last month that recurs today counts today.
```ruby
comparison.error_rate_by_platform["iOS"]
```

**Interpretation**:
- High count = Platform experiencing issues
- Compare across platforms to identify which needs attention

#### 2. Critical Errors
**Description**: The platform's events whose error type is critical

**Calculation**: Severity is classified from the error type, not stored. A type is critical when
your `custom_severity_rules` say so or, failing that, when it is in the built-in critical list
(`SecurityError`, `NoMemoryError`, `ActiveRecord::ConnectionNotEstablished` and others).
```ruby
comparison.severity_distribution_by_platform["iOS"][:critical]
```

**Interpretation**:
- Even one critical error needs immediate attention
- Compare critical rate: critical_errors / total_errors

#### 3. Unresolved and Resolution Rate
**Description**: How many of the platform's errors are resolved

**Calculation**: These count errors (groups) first seen in the window, not events: a group is what
gets resolved.
```ruby
resolved = groups_first_seen_in_window.where.not(resolved_at: nil).count
unresolved = groups_first_seen_in_window.where(resolved_at: nil).count
resolution_rate = (resolved.to_f / (resolved + unresolved) * 100).round(1)  # 0.0 with no groups
```

#### 4. Stability Score
**Description**: A score from 0 to 100 that compares the platform with the others

**Calculation**: Weighted combination of:
- **70%** - Its share of the window's errors against an even split (at or below an even split
  scores full marks)
- **30%** - Its average resolution time against the fastest platform's (as fast as the fastest
  scores full marks)

A platform with nothing from the window resolved yet is scored on its share alone, and its card
says "No errors from this period resolved yet". With errors on fewer than two platforms in the window
there is no score: the card shows a grey **Not rated** badge and no score bar. See
[Stability Scoring](#stability-scoring) for details.

**Interpretation**: The score bar is green from 80, yellow from 60 to 80, and red below 60, the same
thresholds as the health status.

#### 5. Error Velocity
**Description**: How the error rate is changing (percentage change)

**Calculation**: The window is split in two halves; the platform's events in the second half are
compared with the first.
```ruby
velocity = ((second_half - first_half).to_f / first_half * 100).round(1)
# 0.0 when the first half had no events, however many the second half had
```

**Interpretation**:
- **Positive** = Errors increasing (shown in red)
- **Zero or negative** = Errors flat or decreasing (shown in green)
- Above 10% a rated platform can't be Healthy; above 50% it is Critical (see Health Status)

#### 6. Health Status
**Description**: Quick visual indicator of platform health

**Calculation**:
```ruby
if fewer_than_two_platforms
  :not_rated
elsif stability_score >= 80 && velocity <= 10
  :healthy
elsif stability_score >= 60 && velocity <= 50
  :warning
else
  :critical
end
```

**Indicators** (the card's badge and border):
- **Healthy** (green) - Score 80 or more, and velocity 10% or less
- **Warning** (yellow) - Score 60 or more, and velocity 50% or less
- **Critical** (red) - A lower score, or a higher velocity
- **Not rated** (grey) - Fewer than two platforms with errors in the window; `stability_score` is `nil`

## Stability Scoring

### Algorithm

The stability score combines two factors (`platform_stability_scores`). Only platforms with errors in
the window are scored:

```ruby
# A score compares platforms: it needs two with errors in the window.
return {} if error_rate_by_platform.size < 2

even_share = 1.0 / error_rate_by_platform.size  # one over the platforms with errors
share = platform_errors.to_f / total_errors

# Factor 1: Volume (70% weight). Full credit at or below an even split, falling
# linearly to 0 when one platform has every error
error_score = if share <= even_share
  1.0
else
  1.0 - (share - even_share) / (1.0 - even_share)
end

if avg_resolution_hours  # something from the window is resolved
  # Factor 2: Resolution time (30% weight). The fastest platform's average over
  # this one's, each floored at one hour
  resolution_score = [fastest_avg_hours, 1.0].max / [avg_resolution_hours, 1.0].max

  ((error_score * 0.7) + (resolution_score * 0.3)) * 100  # rounded to 1 decimal
else
  error_score * 100  # nothing resolved: volume alone, rounded to 1 decimal
end
```

`fastest_avg_hours` is the lowest average among the platforms that have resolved something from the
window. A platform with no errors in the window gets no score and no card. Errors with no platform
value belong to no platform: they get no card and don't count towards the even split.

### Why This Formula?

**Volume (70% weight)**: Primary indicator of platform health
- Fewer errors = more stable platform
- Measured against an even split, so platforms that share the errors equally all get full credit,
  and the credit reaches 0 only when one platform has every error
- Dominant factor because prevention > cure

**Resolution Time (30% weight)**: Secondary indicator of team responsiveness
- Faster fixes = better process
- Measured in hours from an error's first occurrence to its resolution, averaged over the errors
  first seen in the window and resolved
- Measured against the fastest platform: the fastest and any as fast get full credit, and one twice
  as slow gets half
- Each average is floored at one hour. Otherwise an average of 0.0 (resolved at once) would leave
  every other platform with no credit, and differences under an hour say little about a platform
- Lower weight because it measures response, not prevention

What follows from the formula:
- The scores are relative: a platform's score changes when another platform's errors or resolution
  times do
- Platforms with equal shares that resolve equally fast score 100 each
- A platform with nothing from the window resolved is scored on volume alone, so two platforms on the
  same page can be scored on different bases. Its card says "No errors from this period resolved yet"
- One very fast platform pulls the others' resolution credit down: against a 1-hour platform, a
  10-hour one gets a tenth of the credit, and scores 73 at an even share

The busier platform's score at some common splits, with full resolution credit:

| Split | Busier platform's volume credit | Its score |
|---|---|---|
| 50/50 | 1.0 | 100, Healthy |
| 60/40 | 0.8 | 86, Healthy |
| 90/10 | 0.2 | 44, Critical |
| 80/10/10 | 0.3 | 51, Critical |

Healthy also needs a velocity of 10% or less.

### Example Calculation

**Scenario** (7 days):
- iOS: 100 errors, avg resolution 24 hours, velocity -10%
- Android: 300 errors, avg resolution 48 hours, velocity +20%
- API: 100 errors, none resolved yet, velocity +5%

```text
total_errors = 500
even_share   = 1/3      (three platforms with errors)
fastest      = 24 hours (iOS; API has nothing resolved)
```

**iOS Score**:
```text
share            = 100 / 500 = 0.2   (at or below 1/3)
error_score      = 1.0
resolution_score = 24 / 24   = 1.0

stability_score = (1.0 * 0.7) + (1.0 * 0.3)
                = 1.0
                = 100.0/100   → Healthy (80 or more, velocity -10%)
```

**Android Score**:
```text
share            = 300 / 500 = 0.6
error_score      = 1.0 - (0.6 - 1/3) / (1 - 1/3) = 1.0 - 0.4 = 0.6
resolution_score = 24 / 48   = 0.5

stability_score = (0.6 * 0.7) + (0.5 * 0.3)
                = 0.42 + 0.15
                = 0.57
                = 57.0/100   → Critical (below 60)
```

**API Score**:
```text
share            = 100 / 500 = 0.2   (at or below 1/3)
error_score      = 1.0
nothing resolved → volume alone

stability_score = 1.0 * 100
                = 100.0/100   → Healthy (80 or more, velocity +5%)
```

**Interpretation**: Android needs attention: 60% of the errors, and the slowest fixes. API's 100 is
on volume alone, and its card says "No errors from this period resolved yet".

With only one platform, `platform_stability_scores` returns `{}`; that platform's summary has
`stability_score: nil` and `health_status: :not_rated`.

## Cross-Platform Analysis

### What Are Cross-Platform Errors?

Cross-platform errors are the **same error type** with events on **two or more platforms** in the window.

They are matched by type (class name) only: messages are not compared.

Example:
```text
NoMethodError
- Occurs on: API, Android, iOS
- Could indicate: Backend API issue (shared code)
```

### Finding Cross-Platform Errors

```ruby
comparison = RailsErrorDashboard::Queries::PlatformComparison.new(days: 7)
cross_platform = comparison.cross_platform_errors

cross_platform.each do |data|
  puts "#{data[:error_type]}:"
  puts "  Platforms: #{data[:platforms].join(', ')}"
  puts "  Total occurrences: #{data[:total_occurrences]}"

  data[:platform_breakdown].each do |platform, count|
    puts "    #{platform}: #{count} errors"
  end
end
```

**Output**:
```text
NoMethodError:
  Platforms: API, Android, iOS
  Total occurrences: 450
    iOS: 200 errors
    Android: 150 errors
    API: 100 errors
```

### Why Cross-Platform Analysis Matters

**1. Root Cause Identification**:
- Cross-platform = Possibly a backend/API issue
- Platform-specific = Likely client-side issue
- Common types such as `NoMethodError` show up on several platforms from unrelated bugs, so check the messages

**2. Fix Prioritization**:
- Fixing one cross-platform error helps ALL platforms
- High impact, single fix

**3. Testing Strategy**:
- Cross-platform errors need testing on all affected platforms
- Regression testing should cover all platforms

### Platform-Specific vs Cross-Platform

The page shows two lists:
- **Cross-Platform Errors**: the 10 types with the most events, each with its platforms, its total
  and a per-platform breakdown. The type links to the error list filtered by that type
- **Top Errors - _platform_**: one card per platform with its 5 errors that had the most events in
  the window, and the count for each

An error type in a platform's top errors that is not in the Cross-Platform table had events on that
platform only, unless the table is full (it shows 10; `cross_platform_errors` has them all).

## Platform-Specific Baselines

### Why Platform-Specific Baselines?

Different platforms have different normal error rates:
- **iOS**: Typically lower error rates (strict review process)
- **Android**: Often higher due to device fragmentation
- **API**: Different patterns based on traffic
- **Web**: Browser compatibility issues

**Solution**: Calculate separate baselines per platform.

### How It Works

`BaselineCalculationJob`, which you schedule, calculates baselines for each (error_type, platform) combination:

```ruby
# iOS baseline for NoMethodError
ErrorBaseline.find_by(
  error_type: "NoMethodError",
  platform: "iOS",
  baseline_type: "hourly"
)
# => mean: 5, std_dev: 2

# Android baseline for same error
ErrorBaseline.find_by(
  error_type: "NoMethodError",
  platform: "Android",
  baseline_type: "hourly"
)
# => mean: 15, std_dev: 5
```

**Result**: Anomaly detection is platform-aware. With the default `baseline_alert_threshold_std_devs` of 2.0:
- iOS: Anomalous at 9 or more errors in an hour (5 + 2 × 2)
- Android: Anomalous at 25 or more errors in an hour (15 + 2 × 5)

### Viewing Platform Baselines

Baselines are not on the Platform page. With `enable_baseline_alerts` on, each error's own page has
a Baseline Statistics card with the baselines for its type and platform (mean, standard deviation
and P95, hourly, daily and weekly). It flags an anomaly when the current count is 2 or more standard
deviations above the mean. See the [Baseline Monitoring Guide](/rails_error_dashboard/docs/features/baseline-monitoring/).

## Use Cases

### Scenario 1: Post-Release Health Check

**Question**: "Did the new release affect all platforms equally?"

**Analysis**:
1. Navigate to the Platform page
2. Pick a window whose second half starts around the release (7 days for a release 3 to 4 days ago)
3. Compare error velocity across platforms

**Example**:
```text
Release: v2.0.0 deployed 3 days ago

Platform Velocity (7 Days: the last 3.5 days against the 3.5 before):
  iOS:     +150% (ISSUE!)
  Android: +5%   (normal)
  API:     +2%   (normal)
```

**Conclusion**: The iOS build has an issue; Android and the backend look fine.

### Scenario 2: Prioritizing Platform Investment

**Question**: "Which platform needs the most engineering resources?"

**Analysis**:
1. View the 30-day stability scores
2. Check resolution rates
3. Review error velocity trends

**Example**:
```text
Platform Metrics (30 days):
           Errors  Avg resolution  Stability  Resolution Rate  Velocity  Status
  iOS:     200     20 h            85.0       75%              -10%      Healthy
  Android: 600     60 h            43.7       30%              +45%      Critical
  API:     150     10 h            100.0      90%              -5%       Healthy
```

**Conclusion**: Android needs urgent attention:
- Low stability (43.7): most of the errors, and the slowest fixes
- Poor resolution rate (30%)
- Rapidly increasing errors (+45%)

**Action**: Allocate Android team to focus on top errors.

### Scenario 3: Backend vs Client Issue

**Question**: "Is this a backend problem or client problem?"

**Analysis**:
1. View the Cross-Platform Errors table
2. Check if the error type appears on multiple platforms
3. Click the type and compare the messages: the table matches on type only

**Example**:
```text
ArgumentError: Missing required parameter 'user_id'

Platforms affected:
  iOS:     120 occurrences
  Android: 95 occurrences
  API:     150 occurrences
```

**Conclusion**: Cross-platform error with the same message → Backend API validation issue
- Not sending user_id from any client
- OR backend expecting user_id but docs don't specify

**Action**: Fix backend validation, update API docs.

### Scenario 4: Platform-Specific Regression

**Question**: "Why is this error only happening on Android?"

**Analysis**:
1. Find it in the "Top Errors - Android" card
2. Check that its type is not in the Cross-Platform Errors table
3. Click "View Android Errors" for the full list, and open the error

**Example**:
```text
SQLiteException: database locked (code 5)

Top Errors - Android: 350 occurrences
Cross-Platform Errors: not listed
```

**Conclusion**: Android-specific database issue
- Likely concurrent access to local SQLite database
- iOS uses different local storage (Core Data)

**Action**: Investigate Android database access patterns.

### Scenario 5: Monitoring Improvement

**Question**: "Are our fixes improving platform health?"

**Analysis**:
1. Check the error velocity and the Daily Error Trends chart
2. Note the stability scores at each review: the page shows the current window only and keeps no history

**Example**:
```text
iOS, 30 Days view:
  Error Velocity: -40% (decreasing)
  Stability: 85.0 (noted at the last review: 70.0)
```

**Conclusion**: iOS errors are falling. The score is relative, so it rises when iOS improves
faster than the other platforms, and can fall when they improve faster.

**Action**: Document what worked, apply to other platforms.

## Configuration

### Time Period Selection

The page has 7 Days (the default), 14 Days and 30 Days buttons. Any other number of days from 1 to
365 works through the URL, for example `?days=90`. In code:

```ruby
# 7-day comparison (default)
comparison = PlatformComparison.new(days: 7)

# 30-day comparison
comparison = PlatformComparison.new(days: 30)

# One application only
comparison = PlatformComparison.new(days: 30, application_id: app.id)
```

**Recommendation**: Use 7 days for recent issues, 30 days for trends.

### Custom Analysis

```ruby
# In Rails console
comparison = RailsErrorDashboard::Queries::PlatformComparison.new(days: 14)

# Get all metrics for a platform
ios_health = comparison.platform_health_summary["iOS"]
# => { total_errors: 450, critical_errors: 12, stability_score: 75.5, ... }

# Compare error rates
rates = comparison.error_rate_by_platform
# => { "iOS" => 450, "Android" => 780, "API" => 320 }

# Get top errors per platform
top_errors = comparison.top_errors_by_platform
# => { "iOS" => [{ id: 42, error_type: "NoMethodError", occurrence_count: 120, ... }, ...], ... } (10 per platform)
```

## Best Practices

### 1. Regular Health Reviews

**Weekly Review**:
- Check platform health scores
- Identify platforms with declining health
- Review cross-platform errors

**Monthly Review**:
- Note the 30-day stability scores (the page keeps no history)
- Compare resolution rates across platforms
- Plan engineering allocation

### 2. Set Platform Health Goals

Scores are relative, so set goals on the numbers each platform controls:
- **Errors**: Fewer events per week on each platform
- **Velocity**: Zero or negative on every platform
- **Resolution**: >70% resolution rate on all platforms

A goal like "every platform above 80" depends on the other platforms as well: a platform's score
moves when another platform's errors or resolution times change.

Track progress toward goals using the dashboard.

### 3. Prioritize Cross-Platform Fixes

When triaging errors:
1. **High Priority**: Cross-platform + critical
2. **Medium Priority**: Platform-specific + critical OR cross-platform + non-critical
3. **Low Priority**: Platform-specific + non-critical

**Rationale**: Cross-platform fixes have maximum impact.

### 4. Monitor Post-Release

After every release:
1. View the Platform page
2. Check error velocity (should be neutral or negative)
3. Watch for new error types

**Red Flags**:
- Velocity >50% on any platform (the platform is then Critical, whatever its score)
- New critical errors
- Stability score drop >10 points

### 5. Use Platform Comparison for Incident Response

During incidents:
```text
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

Establish "normal" for each platform, in numbers that don't depend on the other platforms:

```text
Our Baselines (example):
  iOS:     <100 errors/week, resolution rate >80%
  Android: <300 errors/week, resolution rate >70%
  API:     <50 errors/week, resolution rate >90%
```

Act when platforms deviate from their baselines.

## Visualizations

### Charts Available

#### 1. Error Rate by Platform
**Shows**: Total error events per platform (bar chart)
**Use**: Quick comparison of volume

#### 2. Daily Error Trends
**Shows**: Error events per day per platform (line chart, one line per platform)
**Use**: Spot trends and anomalies

#### 3. Severity Distribution
**Shows**: A stacked bar per platform, split by severity
**Use**: Understand error composition

#### 4. Average Resolution Time
**Shows**: Average hours to resolve per platform (horizontal bar chart; a platform with no resolved errors shows 0)
**Use**: Compare team responsiveness

### Reading the Charts

**Error Rate by Platform**:
- Tallest bar = Most errors
- Compare relative heights
- To see a platform's errors, use the "View _platform_ Errors" button on its card

**Daily Error Trends**:
- Upward slope = Increasing errors
- Downward slope = Decreasing errors
- Spikes = Incidents or releases
- Flat line = Stable

**Severity Distribution**:
- Red (critical) = Urgent issues
- Yellow (high)
- Blue (medium)
- Grey (low) = Minor issues

## API Reference

### PlatformComparison Query Object

```ruby
comparison = RailsErrorDashboard::Queries::PlatformComparison.new(days: 7, application_id: nil)

# Error events by platform (platforms with none in the window are left out)
comparison.error_rate_by_platform
# => { "iOS" => 100, "Android" => 300, "API" => 100 }

# Severity breakdown (events)
comparison.severity_distribution_by_platform
# => { "iOS" => { critical: 10, high: 50, ... }, ... }

# Resolution times, in hours (nil: nothing resolved)
comparison.resolution_time_by_platform
# => { "iOS" => 24.0, "Android" => 48.0, "API" => nil }

# Stability scores (0-100) for the platforms with errors in the window; {} with fewer than two
comparison.platform_stability_scores
# => { "iOS" => 100.0, "Android" => 57.0, "API" => 100.0 }

# Top 10 errors per platform, by their events in the window
comparison.top_errors_by_platform
# => { "iOS" => [{ id: 42, error_type: "NoMethodError", message: "...", severity: :high,
#                  occurrence_count: 120, occurred_at: <Time> }, ...], ... }

# Errors seen on more than one platform, most frequent first
comparison.cross_platform_errors
# => [{ error_type: "NoMethodError", platforms: ["Android", "iOS"], total_occurrences: 450,
#       platform_breakdown: { "iOS" => 200, "Android" => 250 } }, ...]

# Events per day per platform, a zero for each day without any
comparison.daily_trend_by_platform
# => { "iOS" => { Date => 12, ... }, ... }

# Health summary, for each platform with errors in the window
comparison.platform_health_summary["iOS"]
# => {
#   total_errors: 100,
#   critical_errors: 4,
#   unresolved_errors: 12,
#   resolution_rate: 70.0,
#   resolution_measured: true,    # false: nothing from the window resolved, so the score is volume alone
#   stability_score: 100.0,       # nil with errors on fewer than two platforms
#   error_velocity: -10.0,
#   health_status: :healthy       # :healthy, :warning, :critical or :not_rated
# }

# Error velocity (% change between the window's two halves) is in the summary
comparison.platform_health_summary.transform_values { |h| h[:error_velocity] }
# => { "iOS" => -10.0, "Android" => 20.0, "API" => 5.0 }
```

## Troubleshooting

### "Platform comparison shows no data"

**Cause**: No errors with platform metadata. Every captured error gets one (API when nothing else
matches), so this usually means the selected application has no errors yet.

**Solution**:
```ruby
# Check if errors have platform field
ErrorLog.where.not(platform: nil).count
# If 0, no platform tracking

# Set the platform when you report an error yourself
RailsErrorDashboard::Commands::LogError.call(exception, { platform: "iOS" })

# Or, for an error that isn't a Ruby exception
RailsErrorDashboard::ManualErrorReporter.report(
  error_type: "NSException",
  message: "Fatal crash in payment processing",
  platform: "iOS"
)
```

### "Stability scores seem wrong"

**Cause**: The scores compare platforms with each other.

**Explanation**:
- With errors on fewer than two platforms in the window there is no score: the platform shows "Not rated"
- A platform's score moves when another platform's errors or resolution times change
- A platform's volume credit drops only when it has more than an even split of the errors
- A platform with nothing from the window resolved is scored on volume alone; its card says so
- One very fast platform lowers the others' resolution credit (each average is floored at one hour)
- A platform with no errors in the window gets no score and no card

### "Cross-platform errors not showing"

**Cause**: The type had events on only one platform in the window, or the class names differ across
platforms

**Example**:
```text
iOS:     NSInvalidArgumentException
Android: java.lang.IllegalArgumentException
```

**Solution**: Cross-platform errors are matched on the error type alone, so these never match. Report
the same `error_type` from each client if you want them compared. Fuzzy matching won't link them
either: it compares errors on the same platform only.

## Further Reading

- [Advanced Error Grouping Guide](/rails_error_dashboard/docs/features/advanced-error-grouping/) - Fuzzy matching, co-occurring errors and cascades
- [Baseline Monitoring Guide](/rails_error_dashboard/docs/features/baseline-monitoring/) - Platform-specific baselines
- [Occurrence Patterns Guide](/rails_error_dashboard/docs/features/occurrence-patterns/) - Platform-specific patterns
- [Error Correlation Guide](/rails_error_dashboard/docs/features/error-correlation/) - Platform correlation analysis
