---
layout: default
title: "Occurrence Patterns Guide"
permalink: /docs/features/OCCURRENCE_PATTERNS
---

# Occurrence Patterns Guide

This guide covers the enhanced occurrence pattern detection features, including cyclical pattern analysis and error burst detection.

**⚙️ Optional Feature** - Occurrence pattern detection is disabled by default. Enable it in your initializer:

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_occurrence_patterns = true
end
```

## Table of Contents

- [Overview](#overview)
- [Cyclical Patterns](#cyclical-patterns)
- [Error Bursts](#error-bursts)
- [Pattern Visualization](#pattern-visualization)
- [Use Cases](#use-cases)
- [Configuration](#configuration)
- [Best Practices](#best-practices)

## Overview

Occurrence pattern analysis helps you understand **when and how** errors happen:
- **Cyclical Patterns**: Do errors follow daily or weekly rhythms?
- **Error Bursts**: Are errors happening in rapid sequences?
- **Pattern Strength**: How concentrated are the errors in a few hours of the day?

### Why Patterns Matter

Understanding temporal patterns enables:
- **Proactive Monitoring**: Know when to expect errors
- **Resource Planning**: Scale infrastructure for peak hours
- **Root Cause Analysis**: Link patterns to business activities
- **Deployment Planning**: Avoid deploying during high-error periods

## Cyclical Patterns

### What Are Cyclical Patterns?

Cyclical patterns are **repeating temporal rhythms** in error occurrences.

**Examples**:
- **Business Hours**: Errors peak between 9 AM and 6 PM (user activity)
- **Night**: Errors peak between midnight and 7 AM (batch processing)
- **Weekend**: Most errors happen on Saturday and Sunday (different user behavior)
- **Uniform**: None of the above

Hours and weekdays are read in your application's time zone (`config.time_zone`, UTC by default).

### Pattern Detection Algorithm

The system analyzes error occurrence timestamps to detect patterns:

```ruby
def analyze_cyclical_pattern(timestamps:, days: 30)
  # Step 1: Count the timestamps by hour (0-23) and weekday (0-6).
  # Hours and weekdays with no errors are absent.
  hourly_distribution = { 0 => 5, 1 => 3, ..., 9 => 45, ... }
  weekday_distribution = { 0 => 120, 1 => 95, ... }  # 0=Sunday, 1=Monday

  # Step 2: Classify the pattern from the two distributions
  pattern_type = determine_pattern_type(hourly_distribution, weekday_distribution)
  # => :business_hours, :night, :weekend, :uniform (:none with no timestamps)

  # Step 3: Peak hours: hours with more than twice the average,
  # where the average is the total divided by 24
  peak_hours = find_peak_hours(hourly_distribution)

  # Step 4: Pattern strength (0.0 - 1.0)
  pattern_strength = calculate_pattern_strength(hourly_distribution)

  {
    pattern_type: pattern_type,
    peak_hours: peak_hours,
    hourly_distribution: hourly_distribution,
    weekday_distribution: weekday_distribution,
    pattern_strength: pattern_strength,
    total_errors: timestamps.size,
    analysis_days: days
  }
end
```

### Pattern Types

The rules are checked in this order, and the first that matches wins:

| Type | Rule |
|---|---|
| Business Hours | 3 or more peak hours from 9:00 to 17:59 |
| Night | 2 or more peak hours from 0:00 to 6:59 |
| Weekend | Saturday and Sunday hold more than half of the errors |
| Uniform | None of the above |
| None | No timestamps in the window |

A peak hour is an hour with more than twice the average count, where the average is the total
divided by 24.

#### 1. Business Hours Pattern

**Rule**: 3 or more peak hours from 9:00 to 17:59. The weekdays and the other hours don't matter.

**Interpretation**: Errors driven by **user activity**
- More users during business hours = more errors
- Likely legitimate use triggering bugs

**Example**:
```text
Hourly Distribution:
  9 AM: ████████████████ 45 errors
  10 AM: ███████████████ 42 errors
  ...
  2 AM: ██ 5 errors
  3 AM: █ 3 errors
```

**Actions**:
- Normal if error rate matches traffic
- Abnormal if error rate > traffic rate
- Scale infrastructure for business hours

#### 2. Night Pattern

**Rule**: 2 or more peak hours from 0:00 to 6:59, when the errors are not Business Hours. The
weekdays don't matter.

**Interpretation**: Errors driven by **background processes**
- Batch jobs, data syncs, scheduled tasks
- Cron jobs, ETL processes

**Example**:
```text
Hourly Distribution:
  2 AM: ████████████████ 120 errors (data sync)
  3 AM: ███████████████ 95 errors
  ...
  10 AM: ██ 8 errors
```

**Actions**:
- Review batch job logs
- Check scheduled task timing
- Optimize background processes

#### 3. Weekend Pattern

**Rule**: Saturday and Sunday together hold more than half of the errors, when the errors are
neither Business Hours nor Night.

**Interpretation**: Errors driven by **weekend user behavior**
- Different features used on weekends
- Recreational usage vs work usage
- Different device types (personal vs work)

**Example**:
```text
Weekday Distribution:
  Saturday: ████████████████ 250 errors
  Sunday: ███████████████ 230 errors
  Monday: ████ 80 errors
  Tuesday: ████ 75 errors
```

**Actions**:
- Identify weekend-specific features
- Check if errors relate to personal accounts
- Review weekend-only code paths

#### 4. Uniform Pattern

**Rule**: None of the other rules match.

Uniform doesn't mean the errors are spread evenly. An error with one or two peak hours in the
daytime, one peak hour at night, or its peaks in the evening (18:00 to 23:59) is Uniform too,
unless the weekend rule matches. Check the pattern strength and the heatmap.

**Interpretation**: When the strength is low too, errors are **not time-dependent**
- Background errors (timeouts, network)
- Random user-triggered errors
- System-level issues

**Example**:
```text
Hourly Distribution:
  All hours: ███████ ~25 errors (consistent)
```

**Actions**:
- Focus on error type, not timing
- Not related to specific user activities
- Likely infrastructure or code bug

### Pattern Strength

Pattern strength measures how **concentrated** the errors are in some hours of the day (0.0 = spread
evenly over all 24 hours, 1.0 = strongly concentrated). It is computed from the hourly distribution
alone, separately from the pattern type.

**Calculation**: Coefficient of variation of the 24 hourly counts
```ruby
def calculate_pattern_strength(hourly_distribution)
  values = (0..23).map { |hour| hourly_distribution[hour] || 0 }  # hours with no errors count as 0
  mean = values.sum.to_f / 24
  variance = values.sum { |v| (v - mean)**2 } / 24
  std_dev = Math.sqrt(variance)

  # Coefficient of variation, rounded to 2 places and capped at 1.0
  cv = std_dev / mean
  [cv.round(2), 1.0].min
end
```

Errors confined to a few hours reach the 1.0 cap: errors only from 9:00 to 17:59 score 1.0.

**Interpretation** (the bands the error page uses):
- **0.7 - 1.0**: Strong pattern - errors highly concentrated in specific hours
- **0.4 - 0.7**: Moderate pattern - some concentration in specific hours
- **0.0 - 0.4**: Weak pattern - errors distributed fairly evenly

**Example**:
```text
22 errors an hour from 9:00 to 17:59, 4 an hour otherwise:
→ Business Hours, strength 0.81 (strong)

8 to 12 errors every hour:
→ Uniform, strength 0.13 (weak)

20 errors an hour from 9:00 to 17:59, 4 an hour otherwise:
→ Uniform (20 is not more than twice the average of 10), strength 0.77 (strong)
```

### Accessing Pattern Data

#### Via UI
Navigate to an error detail page → the "Occurrence Patterns" card (last 30 days) shows:
- Pattern type badge, with a one-line description
- Pattern strength progress bar, labelled strong, moderate or weak
- Hourly distribution heatmap
- Peak hours, when there are any

The card appears when there is at least one timestamp in the 30 days.

#### Via Code
```ruby
error = RailsErrorDashboard::ErrorLog.find(123)
pattern = error.occurrence_pattern(days: 30)

puts "Pattern Type: #{pattern[:pattern_type]}"
puts "Strength: #{pattern[:pattern_strength]}"
puts "Peak Hours: #{pattern[:peak_hours].join(', ')}"

# Hourly distribution
pattern[:hourly_distribution].each do |hour, count|
  puts "#{hour}:00 - #{count} errors"
end
```

`occurrence_pattern` returns `{}` unless `enable_occurrence_patterns` is on. Since 0.15.0, it,
`error_bursts` and the error page's pattern section read the occurrences of that error type and
platform, in every application (the newest 10,000 in the window, so a frequent error's
distribution can cover fewer days than asked). When there are no occurrence rows in the window
(an install from before the occurrences table, for instance), they fall back to one timestamp per
error record. To analyse another set of times, call the service yourself:

#### Via Service
```ruby
logs = RailsErrorDashboard::ErrorLog.where(error_type: "NoMethodError", platform: "iOS")
timestamps = RailsErrorDashboard::ErrorOccurrence
  .where(error_log_id: logs.select(:id))
  .where("occurred_at >= ?", 30.days.ago)
  .pluck(:occurred_at)

pattern = RailsErrorDashboard::Services::PatternDetector.analyze_cyclical_pattern(
  timestamps: timestamps,
  days: 30
)
```

## Error Bursts

### What Are Error Bursts?

Error bursts are **rapid sequences of errors** occurring in a short time window.

**Characteristics**:
- Each error comes 60 seconds or less after the one before
- At least 5 errors in sequence
- No limit on the length: a burst lasts as long as the gaps stay at 60 seconds or less

**Example**:
```text
Normal errors:
  10:00:00 - Error 1
  10:05:00 - Error 2  (5 min gap)
  10:12:00 - Error 3  (7 min gap)

Burst:
  14:30:00 - Error 1  ← Burst starts
  14:30:15 - Error 2  (15 sec gap)
  14:30:22 - Error 3  (7 sec gap)
  14:30:45 - Error 4  (23 sec gap)
  14:31:10 - Error 5  (25 sec gap)
  14:31:30 - Error 6  (20 sec gap) ← Burst ends: 6 errors over 90 seconds, low intensity
  14:35:00 - Error 7  (3.5 min gap)
```

### Burst Detection Algorithm

`PatternDetector.detect_bursts(timestamps:)`:

1. Sorts the timestamps, and returns no bursts when there are fewer than 5
2. Walks through them in order. A gap of 60 seconds or less starts a burst (at the earlier of the
   two errors) or extends the current one
3. A longer gap ends the current burst. It is kept if it has 5 or more errors
4. Each kept burst is returned, oldest first, as:

```ruby
{
  start_time: first_error_time,
  end_time: last_error_time,
  duration_seconds: (last_error_time - first_error_time).round(1),
  error_count: errors_in_burst,
  burst_intensity: classify_burst_intensity(errors_in_burst)
}
```

### Burst Intensity

Bursts are classified by severity:

| Intensity | Error Count | Description |
|-----------|-------------|-------------|
| **Low** | 5-9 errors | Minor burst, monitor |
| **Medium** | 10-19 errors | Moderate burst, investigate |
| **High** | 20+ errors | Significant burst, urgent |

**Calculation**:
```ruby
def classify_burst_intensity(count)
  if count >= 20
    :high
  elsif count >= 10
    :medium
  else
    :low
  end
end
```

### Why Bursts Matter

Bursts indicate:
- **Cascading failures**: One error triggers many others
- **Load spikes**: Sudden traffic increase
- **Deployment issues**: Bad release causes immediate errors
- **Infinite loops**: Code stuck in error loop

**Not bursts**:
- Steady error rate with gaps over 60 seconds (even if high)
- Errors spread over hours
- Normal user activity patterns

### Accessing Burst Data

#### Via UI
Navigate to an error detail page → the "Error Bursts" card (last 7 days) shows a table with:
- Burst start time
- Duration (in minutes, with the seconds)
- Error count
- Intensity badge

It lists the first 10 bursts, oldest first, with a note when there are more, and a list of things
to check below the table. The card appears only when there is at least one burst.

#### Via Code
```ruby
error = RailsErrorDashboard::ErrorLog.find(123)
bursts = error.error_bursts(days: 7)

bursts.each do |burst|
  puts "Burst at #{burst[:start_time]}"
  puts "  Duration: #{burst[:duration_seconds]}s"
  puts "  Count: #{burst[:error_count]} errors"
  puts "  Intensity: #{burst[:burst_intensity]}"
end
```

#### Via Service
```ruby
logs = RailsErrorDashboard::ErrorLog.where(error_type: "NoMethodError", platform: "iOS")
timestamps = RailsErrorDashboard::ErrorOccurrence
  .where(error_log_id: logs.select(:id))
  .where("occurred_at >= ?", 7.days.ago)
  .pluck(:occurred_at)

bursts = RailsErrorDashboard::Services::PatternDetector.detect_bursts(timestamps: timestamps)
```

## Pattern Visualization

### Hourly Distribution Heatmap

The UI displays a row of **24 cells**, one per hour, each showing its count. A cell's red is
stronger the closer its count is to the busiest hour's, and peak hours have a red border:

```text
Hour   0   1   2  ...   9   10   11  ...  23
Count  5   3   8  ...  45   42   38  ...   6
Shade  ░   ░   ░  ...  █    █    ▓   ...   ░
                       ^peak ^peak ^peak
```

**Color Coding**:
- Red at an opacity of count ÷ the busiest hour's count: an hour with no errors is blank, the busiest hour is solid red
- A red border marks the peak hours (more than twice the average)

### Pattern Insights Card

The error page's "Occurrence Patterns" card displays:
- **Pattern Type Badge**: Business Hours, Night, Weekend, Uniform, or No Pattern Detected, with a one-line description
- **Pattern Strength**: Progress bar (0-100%), labelled strong, moderate or weak
- **Hourly Distribution Heatmap**: see above
- **Peak Hours**: The hours with more than twice the average, when there are any

**Example**:
```text
┌─────────────────────────────────────────────┐
│ Occurrence Patterns (Last 30 days)          │
├─────────────────────────────────────────────┤
│ Pattern Type: Business Hours Pattern        │
│ Pattern Strength: ████████░░ 85%            │
│   Strong pattern - Errors highly            │
│   concentrated in specific hours            │
│                                             │
│ Hourly Distribution Heatmap                 │
│ [0] [1] [2] ... [9] [10] ... [23]           │
│                                             │
│ Peak Hours: 9:00, 10:00, 11:00, 14:00,      │
│             15:00                           │
└─────────────────────────────────────────────┘
```

### Burst Timeline

Bursts are displayed in a table:

```text
Error Bursts  3  (Last 7 days)

Start Time                     Duration        Error Count  Intensity
December 18, 2025 03:45:00 PM  1.0 min (60s)   12 errors    Medium (10-19 errors)
December 19, 2025 10:15:00 AM  2.0 min (120s)  18 errors    Medium (10-19 errors)
December 20, 2025 02:30:00 PM  1.5 min (90s)   35 errors    High (20+ errors)
```

## Use Cases

### Scenario 1: Investigating Business Hours Errors

**Problem**: "Why do we only see this error during the day?"

**Analysis**:
```ruby
error = ErrorLog.find_by(error_type: "SlowQueryError")
pattern = error.occurrence_pattern

puts pattern[:pattern_type]
# => :business_hours

puts pattern[:peak_hours]
# => [9, 10, 11, 14, 15, 16]
```

**Interpretation**:
- Error peaks during business hours (9 AM - 6 PM)
- Likely related to user activity
- Database queries slow under load

**Action**:
1. Check if query performance degrades with traffic
2. Add database indexes for common queries
3. Implement query caching
4. Scale database for peak hours

### Scenario 2: Debugging Night-Time Failures

**Problem**: "Batch job fails every night at 2 AM"

**Analysis**:
```ruby
error = ErrorLog.find_by(error_type: "DataSyncError")
pattern = error.occurrence_pattern

puts pattern[:pattern_type]
# => :night

puts pattern[:peak_hours]
# => [2, 3]
```

**Interpretation**:
- Error occurs during scheduled data sync (2-3 AM)
- Not user-facing, background process issue
- Consistent timing suggests cron job

**Action**:
1. Review cron job logs at 2 AM
2. Check data sync implementation
3. Add retry logic for transient failures
4. Monitor sync job duration

### Scenario 3: Responding to Error Burst

**Problem**: "60 errors in 2 minutes, what happened?"

**Analysis**: `error_bursts` reads the error's occurrences, so a burst of one error shows up
(it needs `enable_occurrence_patterns`):

```ruby
error = RailsErrorDashboard::ErrorLog.find_by(error_type: "NoMethodError")
bursts = error.error_bursts(days: 1)

latest_burst = bursts.last # bursts come oldest first
puts latest_burst
# => {
#   start_time: 2025-12-25 14:30:00 UTC,
#   end_time: 2025-12-25 14:31:58 UTC,
#   duration_seconds: 118.0,
#   error_count: 60,
#   burst_intensity: :high
# }
```

**Interpretation**:
- High-intensity burst: 60 errors in 2 minutes
- About one error every 2 seconds
- Indicates sudden failure, not gradual degradation

In a bigger flood, storm protection keeps an occurrence for only some of the errors (by default,
past 30 in a minute for one error, every 10th), so `error_count` can be lower than what happened.

**Action**:
1. Check deployment timeline (was there a release at 14:30?)
2. Review server logs for 14:30-14:32
3. Check if traffic spiked (load balancer metrics)
4. Rollback if caused by recent deployment

### Scenario 4: Weekend vs Weekday Behavior

**Problem**: "Errors spike every weekend"

**Analysis**:
```ruby
error = ErrorLog.find_by(error_type: "PaymentError")
pattern = error.occurrence_pattern(days: 90)

puts pattern[:pattern_type]
# => :weekend

puts pattern[:weekday_distribution]
# => { 0 => 450, 1 => 120, 2 => 110, ..., 6 => 420 }
```

**Interpretation**:
- Errors 3-4x higher on weekends
- Different user behavior (personal shopping vs work)
- Possibly different payment methods (personal cards)

**Action**:
1. Segment users by weekday vs weekend activity
2. Check if weekend users hit different code paths
3. Review weekend-specific payment flows
4. Ensure weekend traffic is handled properly

### Scenario 5: Pattern Change Detection

**Problem**: "Errors used to be business hours, now uniform"

**Analysis**: `occurrence_pattern(days: 60)` covers the last 60 days, the last 30 included. To look at
30-60 days ago alone, pass those occurrences to the service:

```ruby
# Old pattern (30-60 days ago)
logs = RailsErrorDashboard::ErrorLog.where(error_type: error.error_type, platform: error.platform)
old_times = RailsErrorDashboard::ErrorOccurrence
  .where(error_log_id: logs.select(:id))
  .where(occurred_at: 60.days.ago...30.days.ago)
  .pluck(:occurred_at)
old_pattern = RailsErrorDashboard::Services::PatternDetector.analyze_cyclical_pattern(
  timestamps: old_times,
  days: 30
)
puts old_pattern[:pattern_type]
# => :business_hours

# Recent pattern (last 30 days)
new_pattern = error.occurrence_pattern(days: 30)
puts new_pattern[:pattern_type]
# => :uniform
```

**Interpretation**:
- Pattern changed from business hours to uniform
- Error no longer tied to user activity
- Suggests code change or infrastructure issue

**Action**:
1. Review deployments in last 30 days
2. Check if background jobs were added
3. Look for new cron jobs or scheduled tasks
4. Identify root cause of pattern shift

## Configuration

There are no settings for pattern or burst detection. The rules are fixed in
`PatternDetector`:

| Rule | Value |
|---|---|
| Lookback | The `days:` you pass: 30 by default for patterns, 7 for bursts. The error page always uses 30 and 7 |
| Sample | The newest 10,000 occurrences in the lookback |
| Peak hour | An hour with more than twice the average count per hour (the total divided by 24) |
| Pattern type | See [Pattern Types](#pattern-types) |
| Burst | A run of 5 or more errors, each within 60 seconds of the one before |
| Burst intensity | `:low` 5-9 errors, `:medium` 10-19, `:high` 20 or more |

For other rules, analyse the occurrence timestamps yourself (see [Via Service](#via-service)).

## Best Practices

### 1. Correlate Patterns with Business Metrics

**Don't just track errors, correlate with**:
- User traffic (pageviews, API calls)
- Business events (sales, signups)
- Infrastructure metrics (CPU, memory)

**Example**:
```text
Business hours pattern with high errors:
- Error rate: 45 errors/hour at 10 AM
- Traffic: 1000 requests/hour at 10 AM
- Error rate: 4.5% ← High!

vs

- Error rate: 10 errors/hour at 2 AM
- Traffic: 50 requests/hour at 2 AM
- Error rate: 20% ← Very high!
```

**Insight**: Night errors are more severe (20% vs 4.5%), even though absolute count is lower.

### 2. Use Patterns for Deployment Planning

**Avoid deploying during**:
- Peak hours (if pattern is business_hours)
- Batch processing windows (if pattern is night)
- High-traffic days (if pattern is weekend)

**Best deployment times**:
- Business hours pattern → Deploy late night or early morning
- Night pattern → Deploy during afternoon
- Weekend pattern → Deploy weekdays

### 3. Set Pattern-Aware Alerts

Instead of static thresholds:
```ruby
# Bad: Alert if > 50 errors/hour (doesn't account for patterns)
alert if error_count > 50

# Good: Alert if exceeding the usual count for this hour of the day.
# hourly_distribution holds totals over the whole lookback, so divide by its days.
pattern = error.occurrence_pattern(days: 30)
usual = pattern[:hourly_distribution].to_h.fetch(Time.current.hour, 0) / 30.0
alert if error_count > usual * 2
```

### 4. Investigate Pattern Changes

**Red flags**:
- Business hours → Uniform (background job added?)
- Uniform → Business hours (new user-facing feature?)
- No bursts → Frequent bursts (instability introduced?)

**Action**: Investigate when patterns shift unexpectedly.

### 5. Document Known Patterns

Maintain a "pattern knowledge base":

```text
Error: DataSyncError
Pattern: Night (2-3 AM)
Cause: Scheduled nightly data sync
Expected: Yes, normal behavior
Action: Only investigate if fails >2 nights in a row

Error: CheckoutError
Pattern: Business hours + Weekend spike
Cause: User checkout activity
Expected: Yes, correlates with traffic
Action: Monitor error rate %, not absolute count
```

### 6. Use Bursts as Incident Indicators

**Burst Detection Rules**:
- Low/Medium intensity → Log, monitor
- High intensity (20+ errors) → Alert on-call engineer

**Example**:
```ruby
latest = error.error_bursts(days: 1).last # oldest first

if latest && latest[:burst_intensity] == :high
  PagerDutyService.create_incident(
    title: "High-intensity error burst detected",
    details: latest
  )
end
```

## Troubleshooting

### "Pattern detection shows no data"

**Cause**: `enable_occurrence_patterns` is off (`occurrence_pattern` returns `{}`), or there is
nothing in the lookback (`pattern_type` is `:none`).

`occurrence_pattern` reads the error's occurrences in the lookback. Check there are some:

```ruby
logs = RailsErrorDashboard::ErrorLog.where(error_type: "YourError")
RailsErrorDashboard::ErrorOccurrence.where(error_log_id: logs.select(:id)).where("occurred_at >= ?", 30.days.ago).count
```

### "Pattern type always shows 'uniform'"

**Cause**: Uniform is what's left when no other rule matches: fewer than 3 peak hours from 9:00 to
17:59, fewer than 2 from 0:00 to 6:59, and no more than half of the errors at the weekend

**Check**:
```ruby
pattern = error.occurrence_pattern
puts pattern[:hourly_distribution]
puts pattern[:peak_hours]
# If all hours have similar counts → truly uniform
# Otherwise check where the peak hours fall: a peak hour needs more than twice the average,
# and peaks in the evening (18:00-23:59) don't count towards any type
```

The thresholds are fixed. For a different rule, analyse the occurrence timestamps yourself.

### "Burst detection shows no bursts"

**Cause**: Errors not close enough in time, or not enough in sequence

**Check**:
```ruby
bursts = error.error_bursts
puts "Found #{bursts.count} bursts"

# Check the raw occurrence timestamps
logs = RailsErrorDashboard::ErrorLog.where(error_type: "YourError")
timestamps = RailsErrorDashboard::ErrorOccurrence.where(error_log_id: logs.select(:id)).pluck(:occurred_at).sort
timestamps.each_with_index do |t, i|
  next if i.zero?
  gap = t - timestamps[i-1]
  puts "Gap: #{gap} seconds" if gap < 120
end
```

A burst needs 5 or more errors, each within 60 seconds of the one before; these are fixed.
`error_bursts` reads these same occurrence timestamps (the newest 10,000 in the window).

### "Heatmap visualization not showing"

**Cause**: The heatmap is part of the Occurrence Patterns card, which appears only with
`enable_occurrence_patterns` on and at least one timestamp in the last 30 days. It is plain HTML,
with no chart library or JavaScript.

**Workaround**: View pattern data via console:
```ruby
error.occurrence_pattern[:hourly_distribution]
```

## API Reference

### ErrorLog#occurrence_pattern

```ruby
error = RailsErrorDashboard::ErrorLog.find(123)
pattern = error.occurrence_pattern(days: 30)

# Returns:
{
  pattern_type: :business_hours,  # or :night, :weekend, :uniform, :none
  peak_hours: [9, 10, 11, 14, 15],
  hourly_distribution: { 0 => 5, 1 => 3, ..., 23 => 6 },        # hours with no errors are absent
  weekday_distribution: { 0 => 120, 1 => 95, ..., 6 => 110 },   # 0 = Sunday
  pattern_strength: 0.85,         # 0.0-1.0, two decimal places
  total_errors: 1250,
  analysis_days: 30               # 0 when there are no timestamps
}
```

### ErrorLog#error_bursts

```ruby
error = RailsErrorDashboard::ErrorLog.find(123)
bursts = error.error_bursts(days: 7)

# Returns array, oldest burst first:
[
  {
    start_time: <Time>,
    end_time: <Time>,
    duration_seconds: 120.0,
    error_count: 35,
    burst_intensity: :high
  },
  ...
]
```

### PatternDetector Service

```ruby
# Both take the timestamps to analyse, for example an error type's occurrences
logs = RailsErrorDashboard::ErrorLog.where(error_type: "NoMethodError", platform: "iOS")
timestamps = RailsErrorDashboard::ErrorOccurrence.where(error_log_id: logs.select(:id)).pluck(:occurred_at)

# Cyclical pattern analysis
pattern = RailsErrorDashboard::Services::PatternDetector.analyze_cyclical_pattern(
  timestamps: timestamps,
  days: 30
)

# Burst detection
bursts = RailsErrorDashboard::Services::PatternDetector.detect_bursts(timestamps: timestamps)
```

## Further Reading

- [Advanced Error Grouping Guide](ADVANCED_ERROR_GROUPING.md) - Finding similar errors
- [Baseline Monitoring Guide](BASELINE_MONITORING.md) - Statistical baselines
- [Platform Comparison Guide](PLATFORM_COMPARISON.md) - Platform health
- [Error Correlation Guide](ERROR_CORRELATION.md) - Release and user correlation
