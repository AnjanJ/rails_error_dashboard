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
- **Pattern Strength**: How predictable is the error pattern?

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
- **Business Hours**: Errors peak 9 AM - 5 PM (user activity)
- **Night**: Errors peak midnight - 6 AM (batch processing)
- **Weekend**: Errors spike Saturday - Sunday (different user behavior)
- **Uniform**: Errors spread evenly throughout the day/week

### Pattern Detection Algorithm

The system analyzes error occurrence timestamps to detect patterns:

```ruby
def analyze_cyclical_pattern(error_type:, platform:, days: 30)
  # Step 1: Group errors by hour (0-23) and weekday (0-6)
  hourly_distribution = { 0 => 5, 1 => 3, ..., 9 => 45, ... }
  weekday_distribution = { 0 => 120, 1 => 95, ... }  # 0=Sunday, 1=Monday

  # Step 2: Identify peak hours and days
  peak_hours = hours where count > average * 1.5
  peak_weekdays = weekdays where count > average * 1.5

  # Step 3: Classify pattern type
  pattern_type = classify_pattern(peak_hours, peak_weekdays)
  # => :business_hours, :night, :weekend, :uniform

  # Step 4: Calculate pattern strength (0.0 - 1.0)
  pattern_strength = coefficient_of_variation(hourly_distribution)

  {
    pattern_type: pattern_type,
    pattern_strength: pattern_strength,
    peak_hours: peak_hours,
    peak_weekdays: peak_weekdays,
    hourly_distribution: hourly_distribution,
    weekday_distribution: weekday_distribution
  }
end
```

### Pattern Types

#### 1. Business Hours Pattern

**Characteristics**:
- Peak hours: 9 AM - 5 PM
- Low hours: Midnight - 6 AM
- Peak weekdays: Monday - Friday

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

**Characteristics**:
- Peak hours: Midnight - 6 AM
- Low hours: 9 AM - 5 PM
- No weekday preference

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

**Characteristics**:
- Peak weekdays: Saturday, Sunday
- Low weekdays: Monday - Friday
- No strong hourly preference

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

**Characteristics**:
- No clear peak hours
- No clear peak weekdays
- Errors distributed evenly

**Interpretation**: Errors **not time-dependent**
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

Pattern strength measures how **predictable** the pattern is (0.0 = no pattern, 1.0 = perfect pattern).

**Calculation**: Coefficient of Variation
```ruby
def calculate_pattern_strength(distribution)
  values = distribution.values
  mean = values.sum.to_f / values.count
  variance = values.sum { |v| (v - mean)**2 } / values.count
  std_dev = Math.sqrt(variance)

  # Coefficient of variation
  cv = std_dev / mean

  # Convert to strength score (higher CV = stronger pattern)
  # Cap at 1.0 for very strong patterns
  [cv / 2.0, 1.0].min
end
```

**Interpretation**:
- **0.8 - 1.0**: Very strong pattern (highly predictable)
- **0.5 - 0.8**: Strong pattern (predictable)
- **0.3 - 0.5**: Moderate pattern (somewhat predictable)
- **0.0 - 0.3**: Weak pattern (not very predictable)

**Example**:
```text
Business hours pattern: strength = 0.85 (very strong)
→ Errors very predictable, always 9 AM - 5 PM

Uniform pattern: strength = 0.15 (weak)
→ Errors unpredictable, random timing
```

### Accessing Pattern Data

#### Via UI
Navigate to an error detail page → "Occurrence Pattern" card shows:
- Pattern type badge
- Pattern strength progress bar
- Hourly distribution heatmap
- Peak hours alert
- Recommendations

#### Via Code
```ruby
error = RailsErrorDashboard::ErrorLog.find(123)
pattern = error.occurrence_pattern(days: 30)

puts "Pattern Type: #{pattern[:pattern_type]}"
puts "Strength: #{pattern[:pattern_strength]}"
puts "Peak Hours: #{pattern[:peak_hours].join(', ')}"
puts "Peak Weekdays: #{pattern[:peak_weekdays].join(', ')}"

# Hourly distribution
pattern[:hourly_distribution].each do |hour, count|
  puts "#{hour}:00 - #{count} errors"
end
```

#### Via Service
```ruby
pattern = RailsErrorDashboard::Services::PatternDetector.analyze_cyclical_pattern(
  error_type: "NoMethodError",
  platform: "iOS",
  days: 30
)
```

## Error Bursts

### What Are Error Bursts?

Error bursts are **rapid sequences of errors** occurring in a short time window.

**Characteristics**:
- Multiple errors within 60 seconds
- Inter-arrival time < 60 seconds
- At least 5 errors in sequence

**Example**:
```text
Normal errors:
  10:00:00 - Error 1
  10:05:00 - Error 2  (5 min gap)
  10:12:00 - Error 3  (7 min gap)

Burst:
  14:30:00 - Error 1
  14:30:15 - Error 2  (15 sec gap) ← Burst starts
  14:30:22 - Error 3  (7 sec gap)
  14:30:45 - Error 4  (23 sec gap)
  14:31:10 - Error 5  (25 sec gap)
  14:31:30 - Error 6  (20 sec gap)
  14:35:00 - Error 7  (3.5 min gap) ← Burst ends
```

### Burst Detection Algorithm

```ruby
def detect_bursts(error_type:, platform:, days: 7)
  # Step 1: Get all occurrence timestamps, sorted
  timestamps = get_all_occurrences.sort

  # Step 2: Detect bursts
  bursts = []
  current_burst = nil

  timestamps.each_with_index do |timestamp, i|
    next if i.zero?

    # Calculate time since previous error
    inter_arrival = timestamp - timestamps[i - 1]

    if inter_arrival <= 60  # 60 seconds threshold
      # Start or continue burst
      if current_burst.nil?
        current_burst = {
          start_time: timestamps[i - 1],
          end_time: timestamp,
          errors: [timestamps[i - 1], timestamp]
        }
      else
        current_burst[:end_time] = timestamp
        current_burst[:errors] << timestamp
      end
    else
      # Gap too large, end burst
      if current_burst && current_burst[:errors].count >= 5
        # Save burst (minimum 5 errors)
        bursts << finalize_burst(current_burst)
      end
      current_burst = nil
    end
  end

  # Don't forget last burst
  if current_burst && current_burst[:errors].count >= 5
    bursts << finalize_burst(current_burst)
  end

  bursts
end

def finalize_burst(burst_data)
  {
    start_time: burst_data[:start_time],
    end_time: burst_data[:end_time],
    duration_seconds: burst_data[:end_time] - burst_data[:start_time],
    error_count: burst_data[:errors].count,
    errors_per_second: burst_data[:errors].count / duration_seconds,
    burst_intensity: classify_intensity(burst_data[:errors].count)
  }
end
```

### Burst Intensity

Bursts are classified by severity:

| Intensity | Error Count | Description |
|-----------|-------------|-------------|
| **Low** | 5-10 errors | Minor burst, monitor |
| **Medium** | 11-25 errors | Moderate burst, investigate |
| **High** | 26-50 errors | Significant burst, urgent |
| **Critical** | 50+ errors | Severe burst, immediate action |

**Calculation**:
```ruby
def classify_intensity(count)
  case count
  when 0..10 then :low
  when 11..25 then :medium
  when 26..50 then :high
  else :critical
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
- Steady error rate (even if high)
- Errors spread over hours
- Normal user activity patterns

### Accessing Burst Data

#### Via UI
Navigate to an error detail page → "Error Bursts" table shows:
- Burst start time
- Duration
- Error count
- Intensity badge
- Errors/second rate

#### Via Code
```ruby
error = RailsErrorDashboard::ErrorLog.find(123)
bursts = error.error_bursts(days: 7)

bursts.each do |burst|
  puts "Burst at #{burst[:start_time]}"
  puts "  Duration: #{burst[:duration_seconds]}s"
  puts "  Count: #{burst[:error_count]} errors"
  puts "  Rate: #{burst[:errors_per_second]} errors/sec"
  puts "  Intensity: #{burst[:burst_intensity]}"
end
```

#### Via Service
```ruby
bursts = RailsErrorDashboard::Services::PatternDetector.detect_bursts(
  error_type: "NoMethodError",
  platform: "iOS",
  days: 7
)
```

## Pattern Visualization

### Hourly Distribution Heatmap

The UI displays a **24-hour heatmap** showing error concentration:

```text
Hour  Count  Visualization
00:00   5    ░░░░░
01:00   3    ░░░
02:00   8    ░░░░░░░░
...
09:00  45    ████████████████ (Peak)
10:00  42    ███████████████
11:00  38    ██████████████
...
23:00   6    ░░░░░░
```

**Color Coding**:
- 🟦 **Light Blue**: Low (< 50% of peak)
- 🟨 **Yellow**: Medium (50-80% of peak)
- 🟥 **Red**: High (> 80% of peak)

### Pattern Insights Card

The error show page displays:
- **Pattern Type Badge**: Visual indicator (Business Hours, Night, Weekend, Uniform)
- **Pattern Strength**: Progress bar (0-100%)
- **Peak Hours**: List of high-error hours
- **Recommendations**: Actionable suggestions based on pattern

**Example**:
```text
┌─────────────────────────────────────┐
│ 🕒 Occurrence Pattern               │
├─────────────────────────────────────┤
│ Pattern Type: Business Hours        │
│ Pattern Strength: ████████░░ 85%    │
│                                     │
│ Peak Hours: 9 AM, 10 AM, 11 AM,    │
│             2 PM, 3 PM              │
│                                     │
│ 💡 Recommendations:                 │
│ • Monitor error rate during         │
│   business hours                    │
│ • Correlate with user traffic       │
│ • Consider scaling infrastructure   │
└─────────────────────────────────────┘
```

### Burst Timeline

Bursts are displayed in a timeline table:

```text
┌─────────────────────────────────────────────────────┐
│ 💥 Error Bursts (Last 7 Days)                       │
├─────────────────────────────────────────────────────┤
│ Time             Duration  Count  Intensity  Rate   │
├─────────────────────────────────────────────────────┤
│ Dec 20, 2:30 PM    90s      35    🔴 High    0.4/s │
│ Dec 19, 10:15 AM  120s      18    🟡 Medium  0.2/s │
│ Dec 18, 3:45 PM    60s      12    🟡 Medium  0.2/s │
└─────────────────────────────────────────────────────┘
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
- Error peaks during business hours (9 AM - 5 PM)
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

**Problem**: "500 errors in 2 minutes, what happened?"

**Analysis**:
```ruby
error = ErrorLog.find_by(error_type: "NoMethodError")
bursts = error.error_bursts(days: 1)

latest_burst = bursts.first
puts latest_burst
# => {
#   start_time: "2025-12-25 14:30:00",
#   duration_seconds: 120,
#   error_count: 500,
#   burst_intensity: :critical,
#   errors_per_second: 4.2
# }
```

**Interpretation**:
- Critical burst: 500 errors in 2 minutes
- Very high rate: 4.2 errors/second
- Indicates sudden failure, not gradual degradation

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

puts pattern[:peak_weekdays]
# => [0, 6]  # Sunday, Saturday

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

**Analysis**:
```ruby
# Old pattern (30-60 days ago)
old_pattern = error.occurrence_pattern(days: 60)
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

### Pattern Detection Settings

```ruby
# In error_log.rb or pattern_detector.rb

# Lookback period for pattern analysis
PATTERN_LOOKBACK_DAYS = 30

# Peak threshold (hours with count > avg * threshold)
PEAK_THRESHOLD_MULTIPLIER = 1.5

# Minimum errors for pattern detection
MIN_ERRORS_FOR_PATTERN = 10
```

### Burst Detection Settings

```ruby
# In pattern_detector.rb

# Inter-arrival threshold for bursts (seconds)
BURST_INTER_ARRIVAL_THRESHOLD = 60

# Minimum errors to qualify as burst
BURST_MIN_ERROR_COUNT = 5

# Burst intensity thresholds
BURST_INTENSITY_THRESHOLDS = {
  low: 10,
  medium: 25,
  high: 50
}
```

### Customization

To adjust burst detection sensitivity:

```ruby
# Stricter (fewer bursts detected)
BURST_INTER_ARRIVAL_THRESHOLD = 30  # 30 seconds
BURST_MIN_ERROR_COUNT = 10

# More lenient (more bursts detected)
BURST_INTER_ARRIVAL_THRESHOLD = 120  # 2 minutes
BURST_MIN_ERROR_COUNT = 3
```

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

# Good: Alert if exceeding expected pattern
baseline = pattern[:hourly_distribution][current_hour]
alert if error_count > baseline * 2
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
- High intensity → Alert on-call engineer
- Critical intensity → Page incident response team

**Example**:
```ruby
bursts = error.error_bursts(days: 1)
latest = bursts.first

if latest && latest[:burst_intensity] == :critical
  PagerDutyService.create_incident(
    title: "Critical error burst detected",
    details: latest
  )
end
```

## Troubleshooting

### "Pattern detection shows no data"

**Cause**: Not enough errors to detect pattern

**Requirements**:
- At least 10 errors in lookback period
- Errors must have occurred_at timestamps

**Solution**:
```ruby
# Check error count
ErrorLog.where(error_type: "YourError").count
# If < 10, wait for more data

# Check timestamps
ErrorLog.where(error_type: "YourError").pluck(:occurred_at)
# Ensure timestamps are present and varied
```

### "Pattern type always shows 'uniform'"

**Cause**: Not enough variation in timing, or truly uniform distribution

**Check**:
```ruby
pattern = error.occurrence_pattern
puts pattern[:hourly_distribution]
# If all hours have similar counts → truly uniform

# If some hours have 0, some have many → check peak threshold
```

**Solution**: Adjust peak threshold if needed:
```ruby
# Lower threshold to detect weaker patterns
PEAK_THRESHOLD_MULTIPLIER = 1.2  # Was 1.5
```

### "Burst detection shows no bursts"

**Cause**: Errors not close enough in time, or not enough in sequence

**Check**:
```ruby
bursts = error.error_bursts
puts "Found #{bursts.count} bursts"

# Check raw timestamps
timestamps = ErrorLog.where(error_type: "YourError").pluck(:occurred_at).sort
timestamps.each_with_index do |t, i|
  next if i.zero?
  gap = t - timestamps[i-1]
  puts "Gap: #{gap} seconds" if gap < 120
end
```

**Solution**: Adjust burst parameters if appropriate:
```ruby
# Allow larger gaps
BURST_INTER_ARRIVAL_THRESHOLD = 120  # 2 minutes

# Require fewer errors
BURST_MIN_ERROR_COUNT = 3
```

### "Heatmap visualization not showing"

**Cause**: UI rendering issue or no data

**Debug**:
1. Check browser console for JS errors
2. Verify pattern data is present in page source
3. Ensure Chart.js loaded correctly

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
  pattern_type: :business_hours,  # or :night, :weekend, :uniform
  pattern_strength: 0.85,
  peak_hours: [9, 10, 11, 14, 15],
  peak_weekdays: [1, 2, 3, 4, 5],  # Mon-Fri
  hourly_distribution: { 0 => 5, 1 => 3, ..., 23 => 6 },
  weekday_distribution: { 0 => 120, 1 => 95, ..., 6 => 110 }
}
```

### ErrorLog#error_bursts

```ruby
error = RailsErrorDashboard::ErrorLog.find(123)
bursts = error.error_bursts(days: 7)

# Returns array:
[
  {
    start_time: <Time>,
    end_time: <Time>,
    duration_seconds: 120,
    error_count: 35,
    errors_per_second: 0.29,
    burst_intensity: :high
  },
  ...
]
```

### PatternDetector Service

```ruby
# Cyclical pattern analysis
pattern = RailsErrorDashboard::Services::PatternDetector.analyze_cyclical_pattern(
  error_type: "NoMethodError",
  platform: "iOS",
  days: 30
)

# Burst detection
bursts = RailsErrorDashboard::Services::PatternDetector.detect_bursts(
  error_type: "NoMethodError",
  platform: "iOS",
  days: 7
)
```

## Further Reading

- [Advanced Error Grouping Guide](ADVANCED_ERROR_GROUPING.md) - Finding similar errors
- [Baseline Monitoring Guide](BASELINE_MONITORING.md) - Statistical baselines
- [Platform Comparison Guide](PLATFORM_COMPARISON.md) - Platform health
- [Error Correlation Guide](ERROR_CORRELATION.md) - Release and user correlation
