# Error Correlation Guide

This guide covers the error correlation analysis features, including release correlation, user correlation, and time-based correlation.

**⚙️ Optional Feature** - Error correlation is disabled by default. Enable it in your initializer:

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_error_correlation = true
end
```

## Table of Contents

- [Overview](#overview)
- [Release Correlation](#release-correlation)
- [User Correlation](#user-correlation)
- [Time-Based Correlation](#time-based-correlation)
- [Period Comparison](#period-comparison)
- [Use Cases](#use-cases)
- [Configuration](#configuration)
- [Best Practices](#best-practices)

## Overview

Error correlation helps you answer critical questions:
- **Release Impact**: Did this version introduce more errors?
- **User Impact**: Are the same users experiencing multiple issues?
- **Temporal Patterns**: Do certain errors occur together?
- **Trend Analysis**: Are errors increasing or decreasing?

### Why Correlation Matters

Understanding correlations enables:
- **Release Quality**: Identify problematic releases quickly
- **User Experience**: Find users most impacted by errors
- **Root Cause Analysis**: Discover hidden relationships between errors
- **Proactive Fixes**: Address issues before they escalate

## Release Correlation

### What is Release Correlation?

Release correlation links errors to specific app versions or git commits, helping you identify which releases introduced errors.

### Errors by App Version

Track errors per version to spot problematic releases:

```ruby
correlation = RailsErrorDashboard::Queries::ErrorCorrelation.new(days: 30)
versions = correlation.errors_by_version

versions.each do |version, data|
  puts "Version: #{version}"
  puts "  Total Errors: #{data[:count]}"
  puts "  Error Types: #{data[:error_types]}"
  puts "  Critical Errors: #{data[:critical_count]}"
  puts "  Platforms: #{data[:platforms].join(', ')}"
  puts "  First Seen: #{data[:first_seen]}"
  puts "  Last Seen: #{data[:last_seen]}"
end
```

**Output**:
```text
Version: 2.1.0
  Total Errors: 450
  Error Types: 23
  Critical Errors: 12
  Platforms: iOS, Android
  First Seen: 2025-12-20 09:00:00
  Last Seen: 2025-12-25 14:30:00

Version: 2.0.5
  Total Errors: 120
  Error Types: 8
  Critical Errors: 2
  Platforms: iOS, Android
  First Seen: 2025-12-15 10:00:00
  Last Seen: 2025-12-24 16:00:00
```

**Metrics Explained**:
- **Total Errors**: Sum of all error occurrences for this version
- **Error Types**: Number of distinct error types (e.g., NoMethodError, ArgumentError)
- **Critical Errors**: Count of high-severity errors
- **Platforms**: Which platforms are running this version
- **First/Last Seen**: Time range for this version's errors

### Errors by Git SHA

For more granular tracking, correlate errors with specific commits:

```ruby
shas = correlation.errors_by_git_sha

shas.each do |sha, data|
  puts "Commit: #{sha[0..7]}"
  puts "  Total Errors: #{data[:count]}"
  puts "  Error Types: #{data[:error_types]}"
  puts "  App Versions: #{data[:app_versions].join(', ')}"
end
```

**Use Case**: Identify the exact commit that introduced a bug.

**Example**:
```text
Commit: a3b4c5d6
  Total Errors: 280
  Error Types: 15
  App Versions: 2.1.0, 2.1.1

Commit: e7f8g9h0
  Total Errors: 45
  Error Types: 5
  App Versions: 2.1.0
```

**Interpretation**: Commit `a3b4c5d6` is associated with significantly more errors → likely contains a bug.

### Problematic Releases

Automatically identify releases with abnormally high error rates:

```ruby
problematic = correlation.problematic_releases

problematic.each do |release|
  puts "⚠️  Version #{release[:version]}"
  puts "   Errors: #{release[:error_count]}"
  puts "   Deviation: +#{release[:deviation_from_avg]}% from average"
  puts "   Critical: #{release[:critical_count]}"
  puts "   Error Types: #{release[:error_types]}"
end
```

**Algorithm**:
1. Calculate average errors per version
2. Flag versions with >2x the average
3. Sort by error count (worst first)

**Output**:
```text
⚠️  Version 2.1.0
   Errors: 450
   Deviation: +275% from average
   Critical: 12
   Error Types: 23
```

**Interpretation**: Version 2.1.0 has 275% more errors than average → **rollback or hotfix urgently**.

### Configuration Requirements

To enable release correlation, errors must include version metadata:

```ruby
# When logging errors
RailsErrorDashboard::Commands::LogError.call(
  error_type: "NoMethodError",
  message: "undefined method 'name'",
  backtrace: [...],
  app_version: "2.1.0",        # Required for version correlation
  git_sha: "a3b4c5d6e7f8",     # Optional, for commit correlation
  # ...
)
```

**Database Columns**:
- `app_version` (string) - Semantic version (e.g., "2.1.0")
- `git_sha` (string) - Full git commit hash

If these columns are missing, correlation queries return empty results.

## User Correlation

### What is User Correlation?

User correlation identifies users experiencing multiple error types, helping you understand user impact and prioritize fixes.

### Multi-Error Users

Find users affected by multiple different error types:

```ruby
correlation = RailsErrorDashboard::Queries::ErrorCorrelation.new(days: 30)
multi_error_users = correlation.multi_error_users(min_error_types: 2)

multi_error_users.each do |user_data|
  puts "User: #{user_data[:user_email]}"
  puts "  Error Types: #{user_data[:error_type_count]}"
  puts "  Total Errors: #{user_data[:total_errors]}"
  puts "  Types: #{user_data[:error_types].join(', ')}"
end
```

**Output**:
```text
User: user@example.com
  Error Types: 5
  Total Errors: 23
  Types: NoMethodError, ArgumentError, NetworkError, TimeoutError, ValidationError

User: another@example.com
  Error Types: 3
  Total Errors: 12
  Types: PaymentError, DatabaseError, CacheError
```

**Interpretation**:
- `user@example.com` experienced 5 different error types → **severely impacted**
- They hit 23 total errors → **frustrating experience**
- Reach out to this user, investigate their usage patterns

**Parameters**:
- `min_error_types` (default: 2) - Minimum distinct error types to include

### Error Type User Overlap

Calculate how many users experience two specific error types:

```ruby
overlap = correlation.error_type_user_overlap(
  "NoMethodError",
  "ArgumentError"
)

puts "Users with NoMethodError: #{overlap[:users_a_count]}"
puts "Users with ArgumentError: #{overlap[:users_b_count]}"
puts "Users with both: #{overlap[:overlap_count]}"
puts "Overlap percentage: #{overlap[:overlap_percentage]}%"
puts "Sample users: #{overlap[:overlapping_user_ids].join(', ')}"
```

**Output**:
```text
Users with NoMethodError: 150
Users with ArgumentError: 120
Users with both: 80
Overlap percentage: 66.7%
Sample users: 45, 67, 89, 102, 134, 156, 178, 190, 203, 245
```

**Interpretation**:
- 66.7% of users with ArgumentError also get NoMethodError
- High overlap suggests **related errors** or **common user path**
- Fixing NoMethodError may also reduce ArgumentError

**Use Cases**:
- Identify cascading errors (one error causes another)
- Find common user workflows triggering multiple errors
- Prioritize fixes with highest user impact

### Configuration Requirements

User correlation requires:
- `user_id` column in error_logs table
- User model with `email` attribute (configurable)

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  config.user_model = "User"  # Your user model class name
end

# When logging errors
RailsErrorDashboard::Commands::LogError.call(
  error_type: "NoMethodError",
  user_id: current_user.id,  # Required for user correlation
  # ...
)
```

## Time-Based Correlation

### What is Time-Based Correlation?

Time-based correlation finds error types that occur at similar times of day, suggesting shared root causes or triggers.

### Analyzing Time Correlation

```ruby
correlation = RailsErrorDashboard::Queries::ErrorCorrelation.new(days: 30)
time_correlated = correlation.time_correlated_errors

time_correlated.each do |pair_name, data|
  puts "#{data[:error_type_a]} ↔ #{data[:error_type_b]}"
  puts "  Correlation: #{(data[:correlation] * 100).round}%"
  puts "  Strength: #{data[:strength]}"
end
```

**Output**:
```text
NoMethodError ↔ DatabaseError
  Correlation: 85%
  Strength: strong

TimeoutError ↔ NetworkError
  Correlation: 92%
  Strength: strong

PaymentError ↔ ValidationError
  Correlation: 62%
  Strength: moderate
```

**Interpretation**:
- NoMethodError and DatabaseError occur at similar hours (85% correlation)
- Likely **shared root cause**: database issues trigger NoMethodError
- TimeoutError and NetworkError also correlate (92%)
- Both probably caused by **network infrastructure issues**

### Correlation Algorithm

Uses **Pearson correlation coefficient** to measure similarity:

```ruby
def calculate_time_correlation(series_a, series_b)
  # series_a and series_b are arrays of 24 elements (hourly counts)

  # Calculate means
  mean_a = series_a.sum.to_f / 24
  mean_b = series_b.sum.to_f / 24

  # Calculate covariance and standard deviations
  covariance = 0.0
  std_a = 0.0
  std_b = 0.0

  24.times do |i|
    diff_a = series_a[i] - mean_a
    diff_b = series_b[i] - mean_b
    covariance += diff_a * diff_b
    std_a += diff_a**2
    std_b += diff_b**2
  end

  # Pearson correlation
  correlation = covariance / Math.sqrt(std_a * std_b)
  correlation.round(3)
end
```

**Correlation Values**:
- **1.0** = Perfect positive correlation (always occur together)
- **0.5-1.0** = Strong correlation (often occur together)
- **0.0-0.5** = Weak correlation (sometimes occur together)
- **-1.0-0.0** = Negative correlation (occur at opposite times)

**Strength Classification**:
- **Strong**: correlation >= 0.8
- **Moderate**: correlation >= 0.5
- **Weak**: correlation < 0.5 (filtered out by default)

### Use Cases for Time Correlation

**1. Identify Cascading Failures**:
```text
DatabaseError ↔ CacheError (90% correlation)
→ Database issues cause cache to fail
→ Fix database to resolve both
```

**2. Find Shared Dependencies**:
```text
PaymentError ↔ ExternalAPIError (85% correlation)
→ Both depend on third-party payment API
→ Add retry logic for API timeouts
```

**3. Detect Infrastructure Issues**:
```text
All errors spike at 2 AM (high correlation)
→ Nightly backup job causing resource contention
→ Reschedule backup or scale infrastructure
```

## Period Comparison

### What is Period Comparison?

Period comparison shows how error rates changed between two time periods, helping identify trends.

### Comparing Periods

```ruby
correlation = RailsErrorDashboard::Queries::ErrorCorrelation.new(days: 30)
comparison = correlation.period_comparison

puts "Current Period (last #{days/2} days):"
puts "  Errors: #{comparison[:current_period][:count]}"
puts "  #{comparison[:current_period][:start]} to #{comparison[:current_period][:end]}"

puts "Previous Period (#{days/2} days before):"
puts "  Errors: #{comparison[:previous_period][:count]}"
puts "  #{comparison[:previous_period][:start]} to #{comparison[:previous_period][:end]}"

puts "Change: #{comparison[:change]} (#{comparison[:change_percentage]}%)"
puts "Trend: #{comparison[:trend]}"
```

**Output**:
```text
Current Period (last 15 days):
  Errors: 1850
  2025-12-10 to 2025-12-25

Previous Period (15 days before):
  Errors: 1200
  2025-11-25 to 2025-12-09

Change: +650 (+54.2%)
Trend: increasing_significantly
```

### Trend Classification

Trends are classified based on percentage change:

| Trend | Change | Meaning |
|-------|--------|---------|
| **decreasing_significantly** | < -20% | Major improvement |
| **decreasing** | -20% to -5% | Moderate improvement |
| **stable** | -5% to +5% | No significant change |
| **increasing** | +5% to +20% | Moderate concern |
| **increasing_significantly** | > +20% | Major concern |

**Use Cases**:
- **Post-release monitoring**: Check if errors increased after deployment
- **Improvement tracking**: Verify that fixes are working
- **Capacity planning**: Identify long-term growth trends

## Use Cases

### Scenario 1: Post-Release Validation

**Question**: "Did v2.1.0 introduce new errors?"

**Analysis**:
```ruby
correlation = ErrorCorrelation.new(days: 7)
versions = correlation.errors_by_version

v210 = versions["2.1.0"]
v205 = versions["2.0.5"]

puts "v2.1.0: #{v210[:count]} errors, #{v210[:error_types]} types"
puts "v2.0.5: #{v205[:count]} errors, #{v205[:error_types]} types"
puts "Increase: +#{v210[:count] - v205[:count]} errors"
```

**Interpretation**:
```text
v2.1.0: 450 errors, 23 types
v2.0.5: 120 errors, 8 types
Increase: +330 errors
```

**Conclusion**: v2.1.0 introduced 330 more errors and 15 new error types → **rollback or hotfix immediately**.

### Scenario 2: Identifying Power Users vs Affected Users

**Question**: "Who should we reach out to?"

**Analysis**:
```ruby
multi_error_users = correlation.multi_error_users(min_error_types: 3)

multi_error_users.first(5).each do |user|
  puts "#{user[:user_email]}: #{user[:error_type_count]} types, #{user[:total_errors]} errors"
end
```

**Output**:
```text
power_user@example.com: 7 types, 45 errors
affected_user@example.com: 5 types, 23 errors
casual_user@example.com: 3 types, 8 errors
```

**Action**:
1. Reach out to `power_user@example.com` (most impacted)
2. Offer compensation or support
3. Gather feedback on their experience
4. Investigate their usage patterns

### Scenario 3: Root Cause via Time Correlation

**Question**: "Why do these errors always occur together?"

**Analysis**:
```ruby
time_correlated = correlation.time_correlated_errors

# Find errors correlated with DatabaseError
database_correlated = time_correlated.select do |_, data|
  data[:error_type_a] == "DatabaseError" || data[:error_type_b] == "DatabaseError"
end

database_correlated.each do |_, data|
  other_error = data[:error_type_a] == "DatabaseError" ? data[:error_type_b] : data[:error_type_a]
  puts "#{other_error}: #{(data[:correlation] * 100).round}% correlation"
end
```

**Output**:
```text
CacheError: 90% correlation
NoMethodError: 85% correlation
TimeoutError: 78% correlation
```

**Conclusion**:
- DatabaseError triggers CacheError (cache depends on database)
- DatabaseError causes NoMethodError (missing data = nil.method)
- DatabaseError leads to TimeoutError (retry logic)

**Action**: **Fix DatabaseError** to resolve all correlated errors.

### Scenario 4: Trend Monitoring

**Question**: "Are we improving or getting worse?"

**Analysis**:
```ruby
# Weekly checks
week1 = ErrorCorrelation.new(days: 7).period_comparison
week2 = ErrorCorrelation.new(days: 14).period_comparison
month = ErrorCorrelation.new(days: 30).period_comparison

puts "This week: #{week1[:trend]} (#{week1[:change_percentage]}%)"
puts "Last 2 weeks: #{week2[:trend]} (#{week2[:change_percentage]}%)"
puts "Last month: #{month[:trend]} (#{month[:change_percentage]}%)"
```

**Output**:
```text
This week: decreasing (-12%)
Last 2 weeks: decreasing (-8%)
Last month: stable (+2%)
```

**Interpretation**: Recent fixes are working (decreasing trend), but long-term trend is stable.

### Scenario 5: A/B Test Impact

**Question**: "Did the new feature increase errors?"

**Analysis**:
```ruby
# Assume feature deployed in v2.1.0
correlation = ErrorCorrelation.new(days: 14)

# Users on new version
v210_errors = correlation.errors_by_version["2.1.0"]

# Users still on old version
v205_errors = correlation.errors_by_version["2.0.5"]

puts "New version (v2.1.0): #{v210_errors[:count]} errors"
puts "Old version (v2.0.5): #{v205_errors[:count]} errors"
```

**Interpretation**:
- If v2.1.0 has significantly more errors → feature has bugs
- If similar → feature is stable
- Compare error types to see if new errors introduced

## Configuration

### Required Columns

For full correlation analysis, ensure these columns exist:

```ruby
# db/migrate/XXXXXX_add_correlation_columns.rb
class AddCorrelationColumns < ActiveRecord::Migration[7.0]
  def change
    add_column :rails_error_dashboard_error_logs, :app_version, :string
    add_column :rails_error_dashboard_error_logs, :git_sha, :string
    add_column :rails_error_dashboard_error_logs, :user_id, :integer

    add_index :rails_error_dashboard_error_logs, :app_version
    add_index :rails_error_dashboard_error_logs, :git_sha
    add_index :rails_error_dashboard_error_logs, :user_id
  end
end
```

### User Model Configuration

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  config.user_model = "User"  # Your user model class
end
```

### Logging Errors with Correlation Data

```ruby
# In your error handler
RailsErrorDashboard::Commands::LogError.call(
  error_type: error.class.name,
  message: error.message,
  backtrace: error.backtrace,

  # Release correlation
  app_version: ENV['APP_VERSION'] || "unknown",
  git_sha: ENV['GIT_SHA'] || `git rev-parse HEAD`.strip,

  # User correlation
  user_id: current_user&.id,

  # Other metadata
  platform: request.user_agent =~ /iPhone/ ? "iOS" : "Android",
  # ...
)
```

## Best Practices

### 1. Track App Version Consistently

**Use semantic versioning**:
```text
✓ Good: "2.1.0", "2.1.1", "2.2.0"
✗ Bad: "v2.1", "2.1-beta", "latest"
```

**Set in environment**:
```ruby
# config/application.rb
config.app_version = ENV['APP_VERSION'] || '1.0.0'

# Or read from package.json, build number, etc.
```

### 2. Monitor Problematic Releases Daily

**Set up daily alerts**:
```ruby
# In a scheduled job
correlation = ErrorCorrelation.new(days: 1)
problematic = correlation.problematic_releases

if problematic.any?
  AlertService.notify(
    title: "Problematic releases detected",
    releases: problematic.map { |r| "#{r[:version]} (+#{r[:deviation_from_avg]}%)" }
  )
end
```

### 3. Investigate Multi-Error Users

**Weekly review**:
```ruby
# In a scheduled report
multi_error_users = correlation.multi_error_users(min_error_types: 3)
top_10 = multi_error_users.first(10)

CsTeam.send_report(
  title: "Top 10 Most Impacted Users",
  users: top_10
)
```

**Action**:
- Reach out to these users
- Offer support or compensation
- Investigate common patterns

### 4. Use Time Correlation for Root Cause

**When stuck on root cause**:
1. Find all errors correlated with the mystery error
2. Identify the common dependency
3. That's likely your root cause

**Example**:
```ruby
correlated = correlation.time_correlated_errors
mystery_error_corr = correlated.select do |_, data|
  data[:error_type_a] == "MysteryError" || data[:error_type_b] == "MysteryError"
end

# If all correlated errors involve ExternalAPI
# → MysteryError is caused by ExternalAPI issues
```

### 5. Compare Periods After Fixes

**After deploying a fix**:
```ruby
# Wait 24 hours, then check
before_fix = ErrorCorrelation.new(days: 14).period_comparison
after_fix = ErrorCorrelation.new(days: 7).period_comparison

if after_fix[:trend] == :decreasing
  puts "Fix is working! Errors down #{after_fix[:change_percentage]}%"
else
  puts "Fix didn't help. Keep investigating."
end
```

### 6. Document Version History

**Maintain a version log**:
```text
v2.1.0 (2025-12-20):
  - Added new payment flow
  - Errors: 450 total, 12 critical
  - Status: ⚠️  Problematic, hotfix planned

v2.0.5 (2025-12-15):
  - Fixed checkout bug
  - Errors: 120 total, 2 critical
  - Status: ✓ Stable

v2.0.0 (2025-12-01):
  - Major redesign
  - Errors: 800 total, 45 critical
  - Status: ⚠️  Problematic, rolled back
```

## Troubleshooting

### "No version data available"

**Cause**: `app_version` column missing or always null

**Fix**:
```ruby
# Add column
rails g migration add_app_version_to_error_logs app_version:string
rails db:migrate

# Ensure errors include version
RailsErrorDashboard::Commands::LogError.call(
  app_version: ENV['APP_VERSION'],  # Must be set!
  # ...
)
```

### "Multi-error users showing strange results"

**Cause**: User model not found or email missing

**Fix**:
```ruby
# Verify configuration
RailsErrorDashboard.configuration.user_model
# => "User"

# Check if User model has email
User.column_names.include?('email')
# => true

# If using different attribute:
# Update find_user_email method in error_correlation.rb
```

### "Time correlation shows no results"

**Cause**: Not enough error types (need at least 2)

**Fix**:
```ruby
# Check distinct error types
ErrorLog.distinct.pluck(:error_type).count
# If < 2, wait for more data

# Lower correlation threshold to see weaker correlations
# (requires code change to min correlation threshold)
```

### "Period comparison shows unexpected trend"

**Cause**: Time period split doesn't align with deployment

**Fix**: Use custom date ranges instead of automatic split:
```ruby
# Instead of using days parameter (which splits in half)
# Query specific periods:
current = ErrorLog.where("occurred_at >= ?", deployment_date).count
previous = ErrorLog.where("occurred_at < ?", deployment_date).where("occurred_at >= ?", deployment_date - 7.days).count
```

## API Reference

### ErrorCorrelation Query Object

```ruby
correlation = RailsErrorDashboard::Queries::ErrorCorrelation.new(days: 30)

# Release correlation
correlation.errors_by_version
# => { "2.1.0" => { count: 450, error_types: 23, ... }, ... }

correlation.errors_by_git_sha
# => { "a3b4c5d6" => { count: 280, error_types: 15, ... }, ... }

correlation.problematic_releases
# => [{ version: "2.1.0", error_count: 450, deviation_from_avg: 275.0, ... }]

# User correlation
correlation.multi_error_users(min_error_types: 2)
# => [{ user_id: 45, user_email: "...", error_types: [...], total_errors: 23 }]

correlation.error_type_user_overlap("NoMethodError", "ArgumentError")
# => { users_a_count: 150, users_b_count: 120, overlap_count: 80, overlap_percentage: 66.7 }

# Time correlation
correlation.time_correlated_errors
# => { "NoMethodError <-> DatabaseError" => { correlation: 0.85, strength: :strong } }

# Period comparison
correlation.period_comparison
# => { current_period: {...}, previous_period: {...}, change: 650, change_percentage: 54.2, trend: :increasing_significantly }

# Platform-specific errors
correlation.platform_specific_errors
# => { "iOS" => [{ error_type: "...", count: 120, platform_specific: true }] }
```

## Further Reading

- [Advanced Error Grouping Guide](ADVANCED_ERROR_GROUPING.md) - Finding related errors
- [Baseline Monitoring Guide](BASELINE_MONITORING.md) - Statistical anomaly detection
- [Platform Comparison Guide](PLATFORM_COMPARISON.md) - Platform health analysis
- [Occurrence Patterns Guide](OCCURRENCE_PATTERNS.md) - Temporal pattern detection
