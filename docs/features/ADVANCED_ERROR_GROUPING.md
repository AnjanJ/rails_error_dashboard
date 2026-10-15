---
layout: default
title: "Advanced Error Grouping"
permalink: /docs/features/ADVANCED_ERROR_GROUPING
---

# Advanced Error Grouping

This guide covers three features that show related errors on an error's page: fuzzy error matching, co-occurring error detection, and error cascade identification. They don't merge or regroup anything: each error keeps its own group.

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

Ways to find related errors beyond simple error type matching:

- **Fuzzy Matching**: Find similar errors even when error_hash differs
- **Co-occurring Errors**: Find errors that happen within minutes of this one
- **Cascade Detection**: Find errors that often follow this one within 60 seconds, or that it often follows — temporal association, not proven causation

These features help you:
- Find related errors that grouping kept apart
- Spot a likely root cause among errors that arrive together
- Fix related errors together

## Fuzzy Error Matching

### What It Does

Fuzzy matching finds errors that are similar but not identical. It uses:
- **Backtrace similarity**: Compares stack frames (70% weight)
- **Message similarity**: Uses Levenshtein distance (30% weight)

### How It Works

```ruby
# The error page shows similar errors when the feature is on. In code:
error = RailsErrorDashboard::ErrorLog.find(123)
similar = error.similar_errors(threshold: 0.6, limit: 10)

similar.each do |result|
  puts "#{result[:error].error_type} - #{(result[:similarity] * 100).round}% similar"
end
```

`similarity` is a score from 0.0 to 1.0, rounded to three places: 0.853 means 85% similar.

### Similarity Calculation

1. **Backtrace Frames** (70%):
   - Takes the first 20 lines of each backtrace
   - Keeps the file name and method of each Ruby (`.rb`) frame, without the directory or the line number (line numbers change with code edits)
   - Uses Jaccard similarity on the two sets of frames: shared frames divided by all frames
   - Example: `app/controllers/users_controller.rb:42:in 'UsersController#create'` becomes `users_controller.rb:create`
   - A backtrace with no Ruby frames scores 0 here. An error reported with a JavaScript or mobile backtrace can reach at most 0.3 in total, below the 0.6 the error page uses

2. **Message Similarity** (30%):
   - Normalizes messages: quoted strings become `""` or `''`, hex addresses and object inspections are masked, numbers become `n`, and everything is lowercased
   - Calculates Levenshtein distance, as 1 − (distance ÷ length of the longer message)
   - Example: "User 123 not found" → "user n not found"

3. **Combined Score**:
   ```text
   similarity = (backtrace_score * 0.7) + (message_score * 0.3)
   ```

### Candidates

Fuzzy matching doesn't compare an error with every other error. It scores at most 50 candidates:

1. Errors with the same backtrace signature (up to 50)
2. If that finds fewer than 20, errors of the same type (up to 30 more)
3. If there are still fewer than 20, errors on the same platform whose type contains the first word of this error's class name (up to 20 more; for `NoMethodError` the word is `No`)

Candidates are not limited to the error's application.

### Configuration

There is no setting for the threshold. The error page uses **0.6 (60% similar)** and shows the top 5. Other values work only when you call the method yourself:

```ruby
# Adjust threshold for your needs
similar = error.similar_errors(threshold: 0.7)  # More strict (fewer results)
similar = error.similar_errors(threshold: 0.5)  # More lenient (more results)
```

### Platform-Based Matching

Fuzzy matching only scores errors from the **same platform** (iOS to iOS, Android to Android): an error on another platform scores 0. An error with no platform is compared with any platform. This is because:
- Platform-specific code differs significantly
- Matches on the same platform are more relevant for debugging

### Use Cases

1. **After Refactoring**: Find errors that moved to different line numbers
2. **Similar User Reports**: Group "User X not found" errors
3. **Code Duplication**: Identify similar error patterns across files
4. **Root Cause Analysis**: See if fixing one error resolves similar ones

### UI Display

On the error page, the "Similar Errors" card lists up to 5 errors that are 60% similar or more:
- Similarity percentage (progress bar)
- Error type and message preview
- Platform and occurrence count
- A View link to the similar error

The card is hidden when no error reaches 60%.

## Co-occurring Errors

### What It Does

Finds other errors that happened within a time window (default: 5 minutes) before or after this error's occurrences. This helps identify:
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
  other = result[:error]
  puts "#{other.error_type} occurs together #{result[:frequency]} times"
  puts "Average delay: #{result[:avg_delay_seconds]}s" # negative: the other error came first
end
```

### Parameters

- **window_minutes** (default: 5): How far before and after each occurrence to look
- **min_frequency** (default: 2): Minimum number of pairs (see below)
- **limit** (default: 10): Maximum results to return

The error page uses 5 minutes, at least 2 pairs and the top 5. Other values work only when you call the method yourself.

### Algorithm

1. Take the newest 500 occurrences of this error
2. Put a window of ± `window_minutes` around each one, and merge windows that overlap
3. Read other errors' occurrences inside those windows, newest first, at most 20,000
4. Count pairs: an occurrence of another error counts once for each of this error's occurrences within `window_minutes` of it. One occurrence near three of this error's counts 3
5. Average the delay (the other error's time minus this error's) over its pairs. A negative delay means the other error tends to come first
6. Keep the errors with at least `min_frequency` pairs, most pairs first

It compares against every other error's occurrences, in every application and on every platform.

### Use Cases

1. **API Cascades**: When one API call fails, related calls fail too
2. **Dependency Issues**: Database error → Cache error → Timeout
3. **User Workflows**: Errors in multi-step processes
4. **Load Spikes**: Multiple services fail under high load

### UI Display

The "Co-occurring Errors" card shows up to 5 errors:
- Error type and message
- Platform
- Frequency (the number of pairs)
- Average delay, shown as "N s before" (the other error tends to come first), "N s after", or "simultaneous"
- A View link to the co-occurring error

## Error Cascades

### What It Does

Records pairs of errors where one often follows the other within 60 seconds:
- **Parents** ("Triggered By" on the error page): errors that this error tends to follow
- **Children** ("Triggers"): errors that tend to follow this error

### How It Works

Cascades are detected by `RailsErrorDashboard::CascadeDetectionJob`. Nothing in the gem schedules
it: add it to your scheduler alongside the other periodic jobs (see [Scheduling](#scheduling)),
hourly with `lookback_hours: 1`, so each run scans only the occurrences since the last one.

```ruby
# What the job runs; from a console, for one window
RailsErrorDashboard::Services::CascadeDetector.call(lookback_hours: 1)

# Read the cascades for an error. Each one is a Hash:
# { error:, frequency:, probability:, avg_delay_seconds: }
error = RailsErrorDashboard::ErrorLog.find(123)
cascades = error.error_cascades(min_probability: 0.5)

puts "Parent errors (come before this one):"
cascades[:parents].each do |cascade|
  puts "  #{cascade[:error].error_type} → #{(cascade[:probability] * 100).round(1)}%"
end

puts "Child errors (come after this one):"
cascades[:children].each do |cascade|
  puts "  #{cascade[:error].error_type} → #{(cascade[:probability] * 100).round(1)}%"
end
```

### Detection Algorithm

1. **Time Window**: For each occurrence of error A, looks at the 60 seconds after it
2. **Pattern Tracking**: Each occurrence of B in that window counts once for that A. One A followed
   by three Bs counts 3, and so does one B that follows three As
3. **Minimum Frequency**: A pair counted 3+ times in the lookback is stored as a cascade, with that
   count as its frequency
4. **Later runs**: Each later run that counts the pair 3+ times again adds 1 to its frequency,
   however many it counted
5. **Probability Calculation**, recalculated on every run that finds the pair:
   ```text
   probability = frequency / all of A's stored occurrences
   ```

Because several Bs after one A each count, the probability can be over 100%, even after one run.
Read it as how strongly B follows A, not as a true percentage.

### Cascade Probability Levels

- **70% and up**: Red badge on the error page. Its footnote calls these strong cascades, together with a frequency of 3 or more
- **50% to 70%**: Yellow badge
- **Below 50%**: Not shown: `error_cascades` leaves them out by default (`min_probability: 0.5`)

### Scheduling

Nothing in the gem schedules cascade detection. Since 0.15.0, schedule
`RailsErrorDashboard::CascadeDetectionJob` with `lookback_hours` equal to the time between runs. It
does nothing while `enable_error_cascades` is off. Windows that overlap count the same errors again:
an hourly run that looks back 24 hours finds the same pairs 24 times a day, adds 1 to their
frequency each time, and pushes the probability up with no new errors.

With Solid Queue, in `config/recurring.yml` (as in [Running in Production](../PRODUCTION.md#2-schedule-the-periodic-jobs)):

```yaml
production:
  red_cascades:
    class: RailsErrorDashboard::CascadeDetectionJob
    args: [ { lookback_hours: 1 } ]
    schedule: every hour
```

With cron, once a day:
`bin/rails runner 'RailsErrorDashboard::CascadeDetectionJob.perform_now(lookback_hours: 24)'`.

### Use Cases

1. **Root Cause**: Check whether fixing the parent error stops the children
2. **Impact Analysis**: See which errors tend to follow this one
3. **Priority Setting**: A parent with many children may be worth fixing first
4. **Architecture Review**: Identify tight coupling issues

### UI Display

The "Error Cascades" card has up to two tables, "Triggered By" (parents) and "Triggers" (children). Each row shows:
- Error type and message
- Cascade probability percentage (red at 70% and up, yellow below)
- Frequency
- Average delay between the two errors
- A View link to the parent or child error

The card is hidden when the error has no cascades at 50% or more.

## Configuration

### Fuzzy Matching Configuration

There is no setting for fuzzy matching. The threshold is a method parameter, from 0.0 to 1.0
(higher is stricter, fewer matches). The error page always uses 0.6; pass another value to
`similar_errors(threshold:)` in code.

### Cascade Detection Configuration

The 60-second window and the minimum of 3 are constants. `lookback_hours` is the only option. Keep
it equal to the time between runs (see [Scheduling](#scheduling)); for a run every two days:

```ruby
RailsErrorDashboard::Services::CascadeDetector.call(lookback_hours: 48)
```

To see only strong cascades, filter by probability when you read them:

```ruby
error.error_cascades(min_probability: 0.7)
```

### Platform-Based Matching

Fuzzy matching compares errors from the same platform only. This cannot be configured.

## Use Cases

### Scenario 1: After a Major Refactor

**Problem**: You refactored your authentication system. Now errors appear at different line numbers.

**Solution**: Use fuzzy matching to find related authentication errors:
1. View any auth error
2. Check "Similar Errors" card
3. See related auth errors (line numbers don't count towards the score)
4. Fix the root cause once

### Scenario 2: Mysterious Cascading Failures

**Problem**: Users report multiple errors during checkout, but you're not sure which is the root cause.

**Solution**: Use cascade detection:
1. View the final error users see
2. Check "Error Cascades" → "Triggered By"
3. Follow the chain back through each parent's own page
4. Check whether fixing the first error stops the rest

### Scenario 3: Load Spike Investigation

**Problem**: During peak hours, you see multiple different errors occurring.

**Solution**: Use co-occurring errors:
1. Pick any error from the spike
2. Check "Co-occurring Errors" card
3. See the errors that happen within 5 minutes of it
4. Identify if it's a database bottleneck, API timeout, etc.

### Scenario 4: Code Duplication Detection

**Problem**: You suspect similar error handling exists in multiple controllers.

**Solution**: Use fuzzy matching:
1. Find an error from one controller
2. In a console, call `error.similar_errors(threshold: 0.5)` (the card always uses 0.6)
3. See errors from other controllers with similar backtraces
4. Refactor common error handling into shared code

## Best Practices

### 1. Start with the Defaults

The error page uses:
- Fuzzy matching: 0.6 (60%)
- Co-occurrence: a 5-minute window and at least 2 pairs
- Cascades: probability 50% and up

The cascade window (60 seconds) and minimum frequency (3) are fixed.

### 2. Monitor Cascade Detection

Check cascade patterns weekly:
- Are there unexpected cascades?
- Can you fix parent errors to prevent children?
- Are cascades indicating architectural issues?

### 3. Use Co-occurring Errors for Root Cause

When investigating production issues:
1. Open the error users see
2. Check co-occurring errors
3. Look for errors marked "before": they tend to happen first
4. Those are your root-cause candidates

### 4. Leverage Similar Errors for Cleanup

Periodically:
1. Sort errors by occurrence count
2. View top errors
3. Check "Similar Errors"
4. Group and fix related issues together

## Performance Considerations

### Fuzzy Matching
- **Computation**: Scores at most 50 candidate errors
- **Caching**: Scores are computed on every render of the error page; only the card's HTML is cached
- **Limits**: Results limited to 10 by default; the card shows 5

### Co-occurring Errors
- **Queries**: At most four, whatever the volume: the error exists, its newest 500 occurrence times, other errors' occurrences in those windows, and the co-occurring errors themselves
- **Database**: The windows use the `[occurred_at, error_log_id]` index on occurrences
- **Memory**: At most 500 of this error's occurrence times and 20,000 (error, time) pairs for other errors
- **Bounds**: Only the newest 500 occurrences of the error are compared. When the windows hold more than 20,000 occurrences of other errors, the newest 20,000 are read, so counts for the older windows can come out low
- Runs on every render of the error page while the feature is on

### Cascade Detection
- **Background Job**: Runs when your scheduler runs `CascadeDetectionJob`, never in a request
- **Memory**: Loads one (error, time) pair for every occurrence in the lookback
- **Cleanup**: Retention cleanup deletes a cascade when it deletes either of its errors; nothing else expires them

## Troubleshooting

### "No similar errors found"

**Possible causes**:
- Error is unique (truly different from others)
- Threshold is too high: the card uses 0.6; try `error.similar_errors(threshold: 0.5)` in a console
- Different platforms (iOS vs Android): they score 0
- The backtrace has no Ruby frames (a JavaScript or mobile error), so the score can't pass 0.3
- No candidate: only errors with the same backtrace signature or type, or a type that shares its first word, are compared

**Solution**: Lower the threshold or check if the error is genuinely unique.

### "Too many co-occurring errors"

**Possible causes**:
- High error volume during peak hours
- Many unrelated errors happening simultaneously

**Solution**:
- The card's values are fixed. In a console, pass a smaller `window_minutes` (2-3)
- Increase min_frequency to filter noise
- Focus on specific error types

### "Cascade detection not working"

**Possible causes**:
- Nothing runs `CascadeDetectionJob` (see [Scheduling](#scheduling))
- `enable_error_cascades` is off: the job skips detection, and the error page doesn't show them
- The errors happen more than 60 seconds apart, or fewer than 3 times in the lookback

**Solution**:
- Schedule `CascadeDetectionJob`, or run `RailsErrorDashboard::CascadeDetectionJob.perform_now` once
  from a console to check
- Check the `rails_error_dashboard_cascade_patterns` table exists (run migrations)

## Database Schema

### Similarity Tracking

No additional columns needed for fuzzy matching (computed on-demand from `backtrace`, `message`, `platform` and `backtrace_signature`).

### Error Occurrences

```ruby
create_table :rails_error_dashboard_error_occurrences do |t|
  t.references :error_log, null: false, foreign_key: { to_table: :rails_error_dashboard_error_logs }
  t.datetime :occurred_at, null: false
  t.integer :user_id
  t.string :request_id
  t.string :session_id
  t.string :app_version # app_version and git_sha were added by a later migration
  t.string :git_sha
  t.timestamps
end

add_index :rails_error_dashboard_error_occurrences, [:occurred_at, :error_log_id]
```

### Cascade Patterns

```ruby
create_table :rails_error_dashboard_cascade_patterns do |t|
  t.references :parent_error, null: false, foreign_key: { to_table: :rails_error_dashboard_error_logs }
  t.references :child_error, null: false, foreign_key: { to_table: :rails_error_dashboard_error_logs }
  t.integer :frequency, default: 1, null: false
  t.float :avg_delay_seconds
  t.float :cascade_probability
  t.datetime :last_detected_at
  t.timestamps
end

add_index :rails_error_dashboard_cascade_patterns, [:parent_error_id, :child_error_id], unique: true
```

## API Reference

All three methods return empty results (`[]`, or empty `parents` and `children`) while their feature is off.

### ErrorLog#similar_errors

```ruby
error.similar_errors(threshold: 0.6, limit: 10)
# Returns: [{ error: ErrorLog, similarity: 0.853 }, ...]  (most similar first)
```

### ErrorLog#co_occurring_errors

```ruby
error.co_occurring_errors(window_minutes: 5, min_frequency: 2, limit: 10)
# Returns: [{ error: ErrorLog, frequency: 5, avg_delay_seconds: -12.5 }, ...]  (most pairs first)
```

### ErrorLog#error_cascades

```ruby
error.error_cascades(min_probability: 0.5)
# Returns: {
#   parents:  [{ error: ErrorLog, frequency: 4, probability: 0.8, avg_delay_seconds: 12.5 }, ...],
#   children: [{ error: ErrorLog, frequency: 3, probability: 0.6, avg_delay_seconds: 4.0 }, ...]
# }  (highest probability first)
```

### Services::CascadeDetector.call

```ruby
RailsErrorDashboard::Services::CascadeDetector.call(lookback_hours: 24)
# Returns: { detected: 5, updated: 3 }
```

`lookback_hours` is its only option. A cascade is a child error that follows its parent within 60
seconds, at least 3 times; both are constants, not options. Each cascade's probability is stored,
and `error_cascades(min_probability:)` filters on it.

## Further Reading

- [Baseline Monitoring Guide](BASELINE_MONITORING.md) - Statistical anomaly detection
- [Platform Comparison Guide](PLATFORM_COMPARISON.md) - iOS vs Android analysis
- [Occurrence Patterns Guide](OCCURRENCE_PATTERNS.md) - Temporal pattern detection
- [Error Correlation Guide](ERROR_CORRELATION.md) - Release and user correlation
