# Baseline Monitoring and Alerts

This guide covers the intelligent baseline monitoring features, including statistical baseline calculation, anomaly detection, and automated alerting.

**⚙️ Optional Feature** - Baseline monitoring is disabled by default. Enable it in your initializer:

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_baseline_alerts = true
  config.baseline_alert_threshold_std_devs = 2.0  # Alert when >2 std devs above baseline
  config.baseline_alert_severities = [:critical, :high]  # Alert on these severities
  config.baseline_alert_cooldown_minutes = 120  # 2 hours between alerts
end
```

## Table of Contents

- [Overview](#overview)
- [Baseline Calculation](#baseline-calculation)
- [Anomaly Detection](#anomaly-detection)
- [Automated Alerts](#automated-alerts)
- [Configuration](#configuration)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

## Overview

Baseline monitoring goes beyond simple spike detection by using statistical methods to:
- **Calculate intelligent baselines** - Not just averages, but statistically sound thresholds
- **Detect anomalies** - Identify when error rates exceed expected ranges
- **Send proactive alerts** - Notify teams before issues escalate
- **Track trends** - Monitor how baselines evolve over time

### Why Baselines Matter

Simple thresholds (e.g., "alert if >100 errors/hour") don't work because:
- Normal error rates vary by time of day, day of week, and season
- What's normal for one error type may be abnormal for another
- Static thresholds cause false positives (alert fatigue) or miss real issues

Baselines solve this by establishing **dynamic, context-aware thresholds**.

## Baseline Calculation

### What is a Baseline?

A baseline is the **expected normal range** for an error type, calculated from historical data using statistical methods.

For each error type and platform combination, we track:
- **Mean**: Average error count
- **Standard Deviation**: How much variation is normal
- **Percentiles**: 95th and 99th percentile values
- **Sample Size**: How many data points were used

### Baseline Types

We calculate three types of baselines:

#### 1. Hourly Baseline
- **Lookback**: Last 4 weeks
- **Granularity**: By hour of day (0-23)
- **Use Case**: Detect unusual spikes during specific hours
- **Example**: "Between 2-3 PM, we normally see 10-20 errors, but today we saw 150"

#### 2. Daily Baseline
- **Lookback**: Last 12 weeks
- **Granularity**: By day of week (Mon-Sun)
- **Use Case**: Detect unusual daily patterns
- **Example**: "Mondays usually have 500 errors, but this Monday had 2000"

#### 3. Weekly Baseline
- **Lookback**: Last 52 weeks (1 year)
- **Granularity**: By week number
- **Use Case**: Detect long-term trends and seasonal changes
- **Example**: "This week's error rate is 3x higher than the same week last year"

### Statistical Method

We use a **robust statistical approach** that handles outliers:

```ruby
# Simplified algorithm
def calculate_baseline(error_counts)
  # 1. Remove extreme outliers (> 3 standard deviations)
  mean = error_counts.mean
  std_dev = error_counts.standard_deviation
  filtered = error_counts.reject { |count| count > mean + (3 * std_dev) }

  # 2. Recalculate statistics on filtered data
  baseline_mean = filtered.mean
  baseline_std_dev = filtered.standard_deviation

  # 3. Calculate percentiles
  percentile_95 = filtered.percentile(95)
  percentile_99 = filtered.percentile(99)

  {
    mean: baseline_mean,
    std_dev: baseline_std_dev,
    percentile_95: percentile_95,
    percentile_99: percentile_99,
    sample_size: filtered.count
  }
end
```

### How Baselines are Calculated

The `BaselineCalculator` service runs daily via background job:

```ruby
# Triggered automatically
RailsErrorDashboard::BaselineCalculationJob.perform_later

# Or manually via console
RailsErrorDashboard::Services::BaselineCalculator.calculate_all_baselines
```

**Process**:
1. For each unique (error_type, platform) pair:
2. Fetch error counts for lookback period
3. Group by time unit (hour/day/week)
4. Calculate statistics (mean, std_dev, percentiles)
5. Store in `error_baselines` table
6. Update existing baselines or create new ones

**Performance**: Full recalculation takes ~5-10 minutes for 10,000 errors.

## Anomaly Detection

### What is an Anomaly?

An anomaly occurs when the **current error count significantly exceeds the baseline**.

We use a **standard deviation-based approach**:

```
current_count > baseline_mean + (threshold * std_dev)
```

### Severity Levels

Anomalies are classified by how far above the baseline they are:

| Severity | Threshold | Description | Action |
|----------|-----------|-------------|--------|
| **Normal** | < 2 std devs | Within expected range | No alert |
| **Elevated** | 2-3 std devs | Moderately above normal | Monitor |
| **High** | 3-4 std devs | Significantly above normal | Investigate |
| **Critical** | > 4 std devs | Extremely abnormal | Immediate action |

### Example Calculation

```
Baseline for "NoMethodError" on iOS, 2-3 PM:
- Mean: 15 errors
- Std Dev: 5 errors
- Percentile 95: 23 errors

Current count: 35 errors

Calculation:
35 - 15 = 20 errors above mean
20 / 5 = 4 standard deviations

Severity: Critical (> 4 std devs)
```

### Accessing Anomaly Data

```ruby
# Get current anomalies
stats = RailsErrorDashboard::Queries::BaselineStats.new
anomalies = stats.current_anomalies(severity: [:high, :critical])

anomalies.each do |anomaly|
  puts "#{anomaly[:error_type]} on #{anomaly[:platform]}"
  puts "  Current: #{anomaly[:current_count]}"
  puts "  Baseline: #{anomaly[:baseline_mean]} ± #{anomaly[:baseline_std_dev]}"
  puts "  Severity: #{anomaly[:severity]} (#{anomaly[:std_devs_above]} std devs)"
end
```

### Dashboard Integration

Anomalies are automatically displayed:
- **Dashboard**: Anomaly alerts card shows active anomalies
- **Error Show Page**: Baseline comparison chart
- **Analytics**: Trend charts with baseline ranges

## Automated Alerts

### Overview

Baseline alerts proactively notify your team when errors exceed baselines, **before they become critical issues**.

### Alert Configuration

Enable baseline alerts in your initializer:

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  # Enable baseline alerting
  config.enable_baseline_alerts = true

  # Alert threshold (standard deviations above mean)
  config.baseline_alert_threshold_std_devs = 2.0  # Default: 2.0

  # Which severities to alert on
  config.baseline_alert_severities = [:critical, :high]  # Default: [:critical, :high]

  # Cooldown period between alerts for same error type (minutes)
  config.baseline_alert_cooldown_minutes = 120  # Default: 120 (2 hours)

  # Alert channels (same as error notifications)
  config.enable_slack_notifications = true
  config.slack_webhook_url = ENV['SLACK_WEBHOOK_URL']

  config.enable_email_notifications = true
  config.notification_email = "errors@example.com"
end
```

### Alert Triggers

Alerts are sent when:
1. ✅ Baseline alerting is enabled
2. ✅ Error count exceeds threshold (e.g., mean + 2 std devs)
3. ✅ Severity matches configured severities
4. ✅ Cooldown period has elapsed since last alert

### Alert Payload

```json
{
  "alert_type": "baseline_violation",
  "error_type": "NoMethodError",
  "platform": "iOS",
  "current_count": 35,
  "baseline_mean": 15,
  "baseline_std_dev": 5,
  "std_devs_above": 4.0,
  "severity": "critical",
  "time_period": "2-3 PM",
  "baseline_type": "hourly",
  "trend": "increasing",
  "dashboard_url": "https://yourapp.com/errors/123"
}
```

### Alert Channels

Baseline alerts use the **same notification channels** as error notifications:

- **Slack**: Rich message with charts and links
- **Email**: HTML email with details and dashboard link
- **Discord**: Webhook notification
- **PagerDuty**: Incident creation for critical alerts
- **Custom Webhook**: POST JSON to your endpoint

### Cooldown Mechanism

To prevent **alert fatigue**, alerts are throttled:

```ruby
# Check if alert should be sent
RailsErrorDashboard::Services::BaselineAlertThrottler.should_alert?(
  error_type: "NoMethodError",
  platform: "iOS"
)
# => false if alert sent within cooldown period
```

**Implementation**:
- Last alert time stored in Redis (if available) or database
- Key: `baseline_alert:#{error_type}:#{platform}`
- Expires after cooldown period

### Manual Alert Testing

Test your alert configuration:

```ruby
# Send a test baseline alert
RailsErrorDashboard::BaselineAlertJob.perform_now(
  error_type: "TestError",
  platform: "iOS",
  current_count: 100,
  baseline_mean: 20,
  baseline_std_dev: 10,
  severity: :critical
)
```

## Configuration

### Full Configuration Reference

```ruby
RailsErrorDashboard.configure do |config|
  # === Baseline Calculation ===

  # How far back to look for baseline calculation
  config.baseline_lookback_weeks = 4      # Hourly baselines
  config.baseline_lookback_weeks_daily = 12   # Daily baselines
  config.baseline_lookback_weeks_weekly = 52  # Weekly baselines

  # Minimum sample size for valid baseline
  config.baseline_min_sample_size = 10

  # === Anomaly Detection ===

  # Outlier removal threshold (std devs)
  config.baseline_outlier_threshold = 3.0

  # Anomaly severity thresholds (std devs above mean)
  config.baseline_elevated_threshold = 2.0
  config.baseline_high_threshold = 3.0
  config.baseline_critical_threshold = 4.0

  # === Alerts ===

  # Enable/disable baseline alerting
  config.enable_baseline_alerts = true

  # Alert threshold (std devs)
  config.baseline_alert_threshold_std_devs = 2.0

  # Alert severities
  config.baseline_alert_severities = [:critical, :high]

  # Cooldown period (minutes)
  config.baseline_alert_cooldown_minutes = 120

  # Alert channels (see notification configuration)
  config.enable_slack_notifications = true
  config.slack_webhook_url = ENV['SLACK_WEBHOOK_URL']
end
```

### Tuning Recommendations

#### For Low-Traffic Applications
```ruby
config.baseline_alert_threshold_std_devs = 3.0  # More lenient
config.baseline_alert_cooldown_minutes = 60     # Shorter cooldown
config.baseline_min_sample_size = 5             # Lower minimum
```

#### For High-Traffic Applications
```ruby
config.baseline_alert_threshold_std_devs = 2.0  # Stricter
config.baseline_alert_cooldown_minutes = 180    # Longer cooldown
config.baseline_min_sample_size = 20            # Higher minimum
```

#### For Noisy Error Types
```ruby
# Option 1: Exclude from alerting
config.baseline_alert_severities = [:critical]  # Only critical

# Option 2: Use higher threshold for specific types
# (Custom logic in BaselineAlertJob)
```

## Best Practices

### 1. Start with Conservative Settings

Begin with **stricter thresholds** and relax them as needed:
```ruby
config.baseline_alert_threshold_std_devs = 3.0  # Start strict
config.baseline_alert_severities = [:critical]  # Only critical
config.baseline_alert_cooldown_minutes = 180    # Longer cooldown
```

Gradually tune based on your team's needs.

### 2. Monitor Baseline Health

Check baselines weekly:
```ruby
stats = RailsErrorDashboard::Queries::BaselineStats.new

# Check which error types have baselines
baseline_coverage = stats.baseline_coverage
# => { "NoMethodError" => 80%, "ArgumentError" => 60% }

# Identify stale baselines (not updated recently)
stale_baselines = ErrorBaseline.where("updated_at < ?", 7.days.ago)
```

### 3. Handle Seasonal Changes

Baselines adapt over time, but sudden changes (e.g., holiday traffic) may cause false alerts:

**Solution**: Temporarily adjust thresholds:
```ruby
# During known high-traffic events
config.baseline_alert_threshold_std_devs = 4.0
```

Or **disable alerts** for specific periods:
```ruby
# In config/initializers/rails_error_dashboard.rb
config.enable_baseline_alerts = ENV['BASELINE_ALERTS_ENABLED'] != 'false'

# Then in production:
export BASELINE_ALERTS_ENABLED=false  # Temporarily disable
```

### 4. Combine with Other Monitoring

Baseline alerts complement (not replace) other monitoring:
- **Application Performance Monitoring (APM)**: Datadog, New Relic, etc.
- **Uptime Monitoring**: Pingdom, StatusCake, etc.
- **Business Metrics**: Revenue, conversions, etc.

Use baseline alerts as **early warning signals** before issues impact users.

### 5. Review Alert History

Periodically review alerts to tune configuration:
```ruby
# Get alert history (from your logging system)
recent_alerts = BaselineAlertJob.where("created_at > ?", 30.days.ago)

# Analyze:
# - Are there frequent false positives? (increase threshold)
# - Are we missing real issues? (decrease threshold)
# - Is cooldown too short? (team fatigued by repeated alerts)
```

### 6. Use Baselines for Capacity Planning

Baselines reveal traffic patterns:
```ruby
stats = RailsErrorDashboard::Queries::BaselineStats.new
hourly_baselines = stats.hourly_baseline("NoMethodError", "iOS")

# Find peak hours
peak_hours = hourly_baselines
  .select { |hour, data| data[:mean] > overall_mean }
  .keys
# => [9, 10, 11, 14, 15, 16]  # Business hours
```

Use this to:
- Scale infrastructure during peak hours
- Schedule deployments during low-traffic periods
- Plan maintenance windows

## Troubleshooting

### "No baseline available for error type"

**Cause**: Not enough historical data to calculate baseline.

**Requirements**:
- At least `baseline_min_sample_size` data points (default: 10)
- Data must span the lookback period (e.g., 4 weeks for hourly)

**Solution**:
```ruby
# Check sample size
ErrorLog.where(error_type: "YourError").count
# If < 10, wait for more data

# Lower minimum if needed (not recommended)
config.baseline_min_sample_size = 5
```

### "Baseline alerts not sending"

**Checklist**:
1. ✅ Alerts enabled: `config.enable_baseline_alerts = true`
2. ✅ Notification channel configured: `config.enable_slack_notifications = true`
3. ✅ Severity matches: `config.baseline_alert_severities` includes current severity
4. ✅ Cooldown expired: Check last alert time
5. ✅ Threshold exceeded: Current count > mean + (threshold * std_dev)

**Debug**:
```ruby
# Check baseline exists
baseline = ErrorBaseline.find_by(error_type: "YourError", platform: "iOS")
baseline.present?  # Should be true

# Check cooldown
throttler = RailsErrorDashboard::Services::BaselineAlertThrottler
throttler.should_alert?(error_type: "YourError", platform: "iOS")
# => true if alert should be sent

# Manually trigger alert
RailsErrorDashboard::BaselineAlertJob.perform_now(...)
```

### "Too many false positive alerts"

**Causes**:
- Threshold too sensitive
- High natural variance in error rates
- Insufficient historical data

**Solutions**:

1. **Increase threshold**:
```ruby
config.baseline_alert_threshold_std_devs = 3.0  # Was 2.0
```

2. **Alert only on critical**:
```ruby
config.baseline_alert_severities = [:critical]  # Was [:critical, :high]
```

3. **Increase cooldown**:
```ruby
config.baseline_alert_cooldown_minutes = 240  # Was 120 (4 hours)
```

4. **Exclude noisy error types**:
```ruby
# In BaselineAlertJob (custom modification)
return if error_type.in?(["CommonWarning", "ExpectedError"])
```

### "Alerts missing real issues"

**Causes**:
- Threshold too lenient
- Gradual increases not detected (boiling frog problem)
- Baseline not updated recently

**Solutions**:

1. **Decrease threshold**:
```ruby
config.baseline_alert_threshold_std_devs = 1.5  # Was 2.0
```

2. **Alert on more severities**:
```ruby
config.baseline_alert_severities = [:critical, :high, :elevated]
```

3. **Recalculate baselines**:
```ruby
# Force recalculation
RailsErrorDashboard::Services::BaselineCalculator.calculate_all_baselines(force: true)
```

4. **Monitor trends manually**:
```ruby
stats = RailsErrorDashboard::Queries::BaselineStats.new
trends = stats.error_trends(days: 30)
# Look for gradual increases
```

### "Baselines seem inaccurate"

**Causes**:
- Recent code changes altered normal behavior
- Seasonal patterns not yet learned
- Outliers not properly filtered

**Solutions**:

1. **Reset baselines after major changes**:
```ruby
# Delete old baselines for affected error types
ErrorBaseline.where(error_type: "AffectedError").delete_all

# Recalculate will use only recent data
RailsErrorDashboard::Services::BaselineCalculator.calculate_all_baselines
```

2. **Adjust outlier threshold**:
```ruby
config.baseline_outlier_threshold = 2.5  # Was 3.0 (more aggressive filtering)
```

3. **Use shorter lookback for new features**:
```ruby
# Temporarily use shorter period
config.baseline_lookback_weeks = 2  # Was 4
```

## Database Schema

### ErrorBaseline Table

```ruby
create_table :rails_error_dashboard_error_baselines do |t|
  t.string :error_type, null: false
  t.string :platform
  t.string :baseline_type, null: false  # "hourly", "daily", "weekly"

  t.datetime :period_start, null: false
  t.datetime :period_end, null: false

  # Statistical measures
  t.float :mean
  t.float :std_dev
  t.float :percentile_95
  t.float :percentile_99
  t.integer :sample_size

  t.timestamps
end

add_index :rails_error_dashboard_error_baselines,
  [:error_type, :platform, :baseline_type, :period_start],
  name: "index_error_baselines_on_type_platform_baseline_period"
```

## API Reference

### BaselineStats Query Object

```ruby
stats = RailsErrorDashboard::Queries::BaselineStats.new

# Get baseline for specific error type
baseline = stats.hourly_baseline("NoMethodError", "iOS")
# => { mean: 15, std_dev: 5, percentile_95: 23, ... }

# Get current anomalies
anomalies = stats.current_anomalies(severity: [:high, :critical])
# => [{ error_type: "...", severity: :critical, std_devs_above: 4.2 }]

# Check if current count is anomalous
is_anomaly = stats.is_anomaly?(
  error_type: "NoMethodError",
  platform: "iOS",
  current_count: 35
)
# => { anomaly: true, severity: :critical, std_devs_above: 4.0 }
```

### BaselineCalculator Service

```ruby
# Calculate all baselines
RailsErrorDashboard::Services::BaselineCalculator.calculate_all_baselines

# Calculate for specific error type
RailsErrorDashboard::Services::BaselineCalculator.calculate_baseline(
  error_type: "NoMethodError",
  platform: "iOS",
  baseline_type: "hourly"
)
```

### BaselineAlertThrottler Service

```ruby
throttler = RailsErrorDashboard::Services::BaselineAlertThrottler

# Check if alert should be sent
should_send = throttler.should_alert?(
  error_type: "NoMethodError",
  platform: "iOS"
)
# => true or false

# Record that alert was sent
throttler.record_alert(
  error_type: "NoMethodError",
  platform: "iOS"
)
```

## Further Reading

- [Advanced Error Grouping Guide](ADVANCED_ERROR_GROUPING.md) - Fuzzy matching and cascades
- [Platform Comparison Guide](PLATFORM_COMPARISON.md) - iOS vs Android analysis
- [Occurrence Patterns Guide](OCCURRENCE_PATTERNS.md) - Cyclical and burst patterns
- [Error Correlation Guide](ERROR_CORRELATION.md) - Release and user correlation
