# Advanced Error Grouping

This guide covers the advanced error grouping features, including fuzzy error matching, co-occurring error detection, and error cascade identification.

**⚙️ Optional Features** - All grouping features are disabled by default. Enable them in your initializer:

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_similar_errors = true          # Fuzzy error matching
  config.enable_co_occurring_errors = true     # Co-occurring patterns
  config.enable_error_cascades = true          # Cascade detection
end
```

## Table of Contents

- [Overview](#overview)
- [Fuzzy Error Matching](#fuzzy-error-matching)
- [Co-occurring Errors](#co-occurring-errors)
- [Error Cascades](#error-cascades)
- [Configuration](#configuration)
- [Use Cases](#use-cases)

## Overview

Intelligent error grouping that goes beyond simple error type matching:

- **Fuzzy Matching**: Find similar errors even when error_hash differs
- **Co-occurring Errors**: Detect errors that happen together in time
- **Cascade Detection**: Identify error chains (A causes B causes C)

These features help you:
- Reduce noise by grouping related errors
- Identify root causes faster
- Understand error dependencies
- Prioritize fixes based on impact

## Fuzzy Error Matching

### What It Does

Fuzzy matching finds errors that are similar but not identical. It uses:
- **Backtrace similarity**: Compares stack frames (70% weight)
- **Message similarity**: Uses Levenshtein distance (30% weight)

### How It Works

```ruby
# In your error show page, similar errors are automatically displayed
# Or access programmatically:
error = RailsErrorDashboard::ErrorLog.find(123)
similar = error.similar_errors(threshold: 0.6, limit: 10)

similar.each do |result|
  puts "#{result[:error].error_type} - #{result[:similarity]}% similar"
end
```

### Similarity Calculation

1. **Backtrace Frames** (70%):
   - Extracts file paths and method names from stack traces
   - Ignores line numbers (they change with code edits)
   - Uses Jaccard similarity on frame sets
   - Example: `app/controllers/users_controller.rb:create`

2. **Message Similarity** (30%):
   - Normalizes messages (replaces numbers, quoted strings)
   - Calculates Levenshtein distance
   - Example: "User 123 not found" → "User N not found"

3. **Combined Score**:
   ```
   similarity = (backtrace_score * 0.7) + (message_score * 0.3)
   ```

### Configuration

Default threshold is **0.6 (60% similar)**. This provides a good balance between recall and precision.

```ruby
# Adjust threshold for your needs
similar = error.similar_errors(threshold: 0.7)  # More strict (fewer results)
similar = error.similar_errors(threshold: 0.5)  # More lenient (more results)
```

### Platform-Based Matching

By default, fuzzy matching only compares errors from the **same platform** (iOS to iOS, Android to Android). This is because:
- Platform-specific code differs significantly
- More relevant matches for debugging
- Faster computation

### Use Cases

1. **After Refactoring**: Find errors that moved to different line numbers
2. **Similar User Reports**: Group "User X not found" errors
3. **Code Duplication**: Identify similar error patterns across files
4. **Root Cause Analysis**: See if fixing one error resolves similar ones

### UI Display

On the error show page, you'll see a "Similar Errors" card showing:
- Similarity percentage (color-coded progress bar)
- Error type and message preview
- Platform and occurrence count
- Link to view the similar error

## Co-occurring Errors

### What It Does

Detects errors that happen together within a time window (default: 5 minutes). This helps identify:
- Cascading failures
- Related bugs
- Concurrent issues

### How It Works

```ruby
error = RailsErrorDashboard::ErrorLog.find(123)
co_occurring = error.co_occurring_errors(
  window_minutes: 5,
  min_frequency: 2,
  limit: 10
)

co_occurring.each do |result|
  error = result[:error]
  puts "#{error.error_type} occurs together #{result[:frequency]} times"
  puts "Average delay: #{result[:avg_delay_seconds]}s"
end
```

### Parameters

- **window_minutes** (default: 5): Time window for co-occurrence
- **min_frequency** (default: 2): Minimum times errors must co-occur
- **limit** (default: 10): Maximum results to return

### Algorithm

1. Get all occurrence timestamps for the target error
2. For each timestamp, find other errors within ±window_minutes
3. Count co-occurrences and calculate average delay
4. Return errors sorted by frequency

### Use Cases

1. **API Cascades**: When one API call fails, related calls fail too
2. **Dependency Issues**: Database error → Cache error → Timeout
3. **User Workflows**: Errors in multi-step processes
4. **Load Spikes**: Multiple services fail under high load

### UI Display

The "Co-occurring Errors" card shows:
- Error type and message
- Frequency of co-occurrence
- Average time delay between errors
- Link to the co-occurring error

## Error Cascades

### What It Does

Identifies parent-child relationships between errors:
- **Parents**: Errors that cause this error
- **Children**: Errors this error causes

### How It Works

The system automatically detects cascades using background jobs:

```ruby
# Manual cascade detection (runs hourly by default)
RailsErrorDashboard::Services::CascadeDetector.call

# Access cascade patterns for an error
error = RailsErrorDashboard::ErrorLog.find(123)
cascades = error.error_cascades(min_probability: 0.5)

puts "Parent errors (what causes this):"
cascades[:parents].each do |pattern|
  puts "  #{pattern.parent_error.error_type} → #{pattern.cascade_probability * 100}%"
end

puts "Child errors (what this causes):"
cascades[:children].each do |pattern|
  puts "  #{pattern.child_error.error_type} → #{pattern.cascade_probability * 100}%"
end
```

### Detection Algorithm

1. **Time Window**: Looks 0-60 seconds before/after each error
2. **Pattern Tracking**: If A then B happens >70% of time = cascade
3. **Probability Calculation**:
   ```
   probability = times_B_after_A / total_A_occurrences
   ```
4. **Minimum Frequency**: Requires 3+ occurrences to confirm pattern

### Cascade Probability Levels

- **High (70-100%)**: Strong cascade relationship
- **Medium (50-70%)**: Moderate cascade relationship
- **Low (<50%)**: Filtered out by default

### Background Job

Cascade detection runs automatically via `CascadeDetectionJob`:
- **Frequency**: Hourly
- **Lookback**: Last 24 hours
- **Updates**: Existing patterns are updated with new data

### Use Cases

1. **Root Cause**: Fix the parent error to resolve children
2. **Impact Analysis**: See downstream effects of an error
3. **Priority Setting**: Parent errors have higher impact
4. **Architecture Review**: Identify tight coupling issues

### UI Display

The "Error Cascades" section shows:
- Visual diagram: Parent → This Error → Children
- Cascade probability percentage
- Average delay between errors
- Links to parent and child errors

## Configuration

### Fuzzy Matching Configuration

```ruby
# In config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  # Fuzzy matching threshold (0.0 - 1.0)
  # Default: 0.6 (60% similar)
  # Higher = more strict, fewer matches
  # Lower = more lenient, more matches

  # No config needed - adjust via method parameters
end
```

### Cascade Detection Configuration

```ruby
# Cascade detection window (seconds)
# Default: 60 seconds
# Adjust via CascadeDetector parameters:

RailsErrorDashboard::Services::CascadeDetector.call(
  window_seconds: 120,  # 2-minute window
  min_frequency: 5,     # Require 5+ occurrences
  min_probability: 0.7  # 70% probability threshold
)
```

### Platform-Based Matching

Fuzzy matching compares errors from the same platform only. This is currently a sensible default and cannot be configured.

## Use Cases

### Scenario 1: After a Major Refactor

**Problem**: You refactored your authentication system. Now errors appear at different line numbers.

**Solution**: Use fuzzy matching to find related authentication errors:
1. View any auth error
2. Check "Similar Errors" card
3. See all related auth errors (even with different line numbers)
4. Fix the root cause once

### Scenario 2: Mysterious Cascading Failures

**Problem**: Users report multiple errors during checkout, but you're not sure which is the root cause.

**Solution**: Use cascade detection:
1. View the final error users see
2. Check "Error Cascades" → "Parent Errors"
3. Follow the chain back to the root cause
4. Fix the parent error to resolve all children

### Scenario 3: Load Spike Investigation

**Problem**: During peak hours, you see multiple different errors occurring.

**Solution**: Use co-occurring errors:
1. Pick any error from the spike
2. Check "Co-occurring Errors" card
3. See all errors that happen together
4. Identify if it's a database bottleneck, API timeout, etc.

### Scenario 4: Code Duplication Detection

**Problem**: You suspect similar error handling exists in multiple controllers.

**Solution**: Use fuzzy matching:
1. View an error from one controller
2. Check "Similar Errors" with threshold 0.5
3. See errors from other controllers with similar backtraces
4. Refactor common error handling into shared code

## Best Practices

### 1. Start with Default Thresholds

The defaults are well-tested:
- Fuzzy matching: 0.6 (60%)
- Cascade window: 60 seconds
- Co-occurrence window: 5 minutes

Only adjust if you have specific needs.

### 2. Monitor Cascade Detection

Check cascade patterns weekly:
- Are there unexpected cascades?
- Can you fix parent errors to prevent children?
- Are cascades indicating architectural issues?

### 3. Use Co-occurring Errors for Root Cause

When investigating production issues:
1. Find the most recent error
2. Check co-occurring errors
3. Look for the earliest error in the sequence
4. That's likely your root cause

### 4. Leverage Similar Errors for Cleanup

Periodically:
1. Sort errors by occurrence count
2. View top errors
3. Check "Similar Errors"
4. Group and fix related issues together

## Performance Considerations

### Fuzzy Matching
- **Computation**: O(n) where n = number of candidate errors
- **Caching**: Similarity scores are calculated on-demand
- **Limits**: Results limited to 10 by default

### Co-occurring Errors
- **Database**: Uses indexed occurred_at queries
- **Memory**: Loads error occurrences into memory
- **Performance**: Fast for normal error volumes (<10k/day)

### Cascade Detection
- **Background Job**: Runs hourly, doesn't block requests
- **Database**: Creates cascade_patterns table
- **Cleanup**: Old patterns (>90 days) should be cleaned periodically

## Troubleshooting

### "No similar errors found"

**Possible causes**:
- Error is unique (truly different from others)
- Threshold is too high (try 0.5)
- Different platforms (iOS vs Android)

**Solution**: Lower the threshold or check if the error is genuinely unique.

### "Too many co-occurring errors"

**Possible causes**:
- Time window too large (>5 minutes)
- High error volume during peak hours
- Many unrelated errors happening simultaneously

**Solution**:
- Reduce window_minutes to 2-3
- Increase min_frequency to filter noise
- Focus on specific error types

### "Cascade detection not working"

**Possible causes**:
- Background job not running
- ErrorOccurrence table doesn't exist (run migrations)
- Window too short (errors happen >60s apart)

**Solution**:
- Check `rails_error_dashboard_cascade_patterns` table exists
- Ensure background jobs are running (`rails jobs:work`)
- Increase window_seconds if needed

## Database Schema

### Similarity Tracking

No additional columns needed for fuzzy matching (computed on-demand).

### Error Occurrences

```ruby
create_table :rails_error_dashboard_error_occurrences do |t|
  t.references :error_log
  t.datetime :occurred_at, null: false
  t.integer :user_id
  t.string :request_id
  t.timestamps
end

add_index :rails_error_dashboard_error_occurrences, [:occurred_at, :error_log_id]
```

### Cascade Patterns

```ruby
create_table :rails_error_dashboard_cascade_patterns do |t|
  t.integer :parent_error_id, null: false
  t.integer :child_error_id, null: false
  t.integer :frequency, default: 0
  t.float :avg_delay_seconds
  t.float :cascade_probability
  t.datetime :last_detected_at
  t.timestamps
end

add_index :rails_error_dashboard_cascade_patterns, [:parent_error_id, :child_error_id]
```

## API Reference

### ErrorLog#similar_errors

```ruby
error.similar_errors(threshold: 0.6, limit: 10)
# Returns: [{ error: ErrorLog, similarity: 0.85 }, ...]
```

### ErrorLog#co_occurring_errors

```ruby
error.co_occurring_errors(window_minutes: 5, min_frequency: 2, limit: 10)
# Returns: [{ error: ErrorLog, frequency: 5, avg_delay_seconds: 12.5 }, ...]
```

### ErrorLog#error_cascades

```ruby
error.error_cascades(min_probability: 0.5)
# Returns: { parents: [CascadePattern, ...], children: [CascadePattern, ...] }
```

### Services::CascadeDetector.call

```ruby
RailsErrorDashboard::Services::CascadeDetector.call(
  lookback_hours: 24,
  window_seconds: 60,
  min_frequency: 3,
  min_probability: 0.7
)
# Returns: { detected: 5, updated: 3 }
```

## Further Reading

- [Baseline Monitoring Guide](BASELINE_MONITORING.md) - Statistical anomaly detection
- [Platform Comparison Guide](PLATFORM_COMPARISON.md) - iOS vs Android analysis
- [Occurrence Patterns Guide](OCCURRENCE_PATTERNS.md) - Temporal pattern detection
- [Error Correlation Guide](ERROR_CORRELATION.md) - Release and user correlation
