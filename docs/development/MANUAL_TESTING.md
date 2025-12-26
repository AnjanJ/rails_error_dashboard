# Manual Installation Generator Testing Guide

This document provides step-by-step instructions to manually test the installation flow with feature selection.

## Setup

1. Navigate to the gem directory:
   ```bash
   cd /Users/aj/code/rails_error_dashboard
   ```

2. Build the gem (if needed):
   ```bash
   gem build rails_error_dashboard.gemspec
   ```

## Test 1: Non-Interactive Installation with No Features

```bash
cd /Users/aj/code/audio_intelli_api
rails generate rails_error_dashboard:install --no-interactive
```

**Expected Output:**
- Creates `config/initializers/rails_error_dashboard.rb`
- All optional features should be DISABLED
- Core features should be ENABLED
- Routes should be added

**Verification:**
```bash
grep "enable_slack_notifications = false" config/initializers/rails_error_dashboard.rb
grep "async_logging = false" config/initializers/rails_error_dashboard.rb
grep "enable_baseline_alerts = false" config/initializers/rails_error_dashboard.rb
```

## Test 2: Non-Interactive Installation with Slack

```bash
# First, remove the existing initializer if it exists
rm config/initializers/rails_error_dashboard.rb

rails generate rails_error_dashboard:install --no-interactive --slack
```

**Expected Output:**
- Slack notifications should be ENABLED
- Other features should be DISABLED

**Verification:**
```bash
grep "Slack Notifications - ENABLED" config/initializers/rails_error_dashboard.rb
grep "config.enable_slack_notifications = true" config/initializers/rails_error_dashboard.rb
grep "enable_email_notifications = false" config/initializers/rails_error_dashboard.rb
```

## Test 3: Non-Interactive with Multiple Features

```bash
rm config/initializers/rails_error_dashboard.rb

rails generate rails_error_dashboard:install --no-interactive \
  --slack \
  --email \
  --async_logging \
  --baseline_alerts \
  --similar_errors
```

**Expected Output:**
- Slack: ENABLED
- Email: ENABLED
- Async Logging: ENABLED
- Baseline Alerts: ENABLED
- Similar Errors: ENABLED
- Other features: DISABLED

**Verification:**
```bash
grep "Slack Notifications - ENABLED" config/initializers/rails_error_dashboard.rb
grep "Email Notifications - ENABLED" config/initializers/rails_error_dashboard.rb
grep "Async Error Logging - ENABLED" config/initializers/rails_error_dashboard.rb
grep "Baseline Anomaly Alerts - ENABLED" config/initializers/rails_error_dashboard.rb
grep "Fuzzy Error Matching - ENABLED" config/initializers/rails_error_dashboard.rb

# Verify disabled features
grep "Discord Notifications - DISABLED" config/initializers/rails_error_dashboard.rb
grep "PagerDuty Integration - DISABLED" config/initializers/rails_error_dashboard.rb
```

## Test 4: Interactive Mode

```bash
rm config/initializers/rails_error_dashboard.rb

rails generate rails_error_dashboard:install
```

**Expected Behavior:**
- Should display welcome message
- Should prompt for each feature (15 total)
- Each prompt should show:
  - Feature number (e.g., [1/15])
  - Feature name
  - Description
  - Enable prompt (y/N)

**Manual Test Steps:**
1. Answer "y" to Slack
2. Answer "n" to Email
3. Answer "y" to async_logging
4. Answer "n" to all others

**Verification:**
```bash
grep "config.enable_slack_notifications = true" config/initializers/rails_error_dashboard.rb
grep "config.enable_email_notifications = false" config/initializers/rails_error_dashboard.rb
grep "config.async_logging = true" config/initializers/rails_error_dashboard.rb
```

## Test 5: All Features Enabled

```bash
rm config/initializers/rails_error_dashboard.rb

rails generate rails_error_dashboard:install --no-interactive \
  --slack \
  --email \
  --discord \
  --pagerduty \
  --webhooks \
  --async_logging \
  --error_sampling \
  --separate_database \
  --baseline_alerts \
  --similar_errors \
  --co_occurring_errors \
  --error_cascades \
  --error_correlation \
  --platform_comparison \
  --occurrence_patterns
```

**Expected Output:**
- Feature summary should show ALL features enabled
- Configuration instructions for all enabled features

**Verification:**
```bash
# Count enabled features (should be 15)
grep "= true" config/initializers/rails_error_dashboard.rb | wc -l

# Verify sampling rate is set to 0.1
grep "config.sampling_rate = 0.1" config/initializers/rails_error_dashboard.rb
```

## Test 6: Generator Summary Display

Run any installation and verify the summary displays:

**Should show:**
- ✓ Installation Complete header
- Core Features section (always shown)
- Notifications section (if any notification enabled)
- Performance section (if any performance feature enabled)
- Advanced Analytics section (if any analytics feature enabled)
- Configuration Required section (with specific ENV vars needed)
- Next Steps section
- Documentation links

## Test 7: Route Mounting

```bash
grep "mount RailsErrorDashboard::Engine" config/routes.rb
```

**Expected:**
```ruby
mount RailsErrorDashboard::Engine => '/error_dashboard'
```

## Test 8: Migrations

```bash
rails db:migrate:status | grep rails_error_dashboard
```

**Expected:**
- Should show all rails_error_dashboard migrations as pending or up

## Automated Test Script

Create a script to run all tests automatically:

```bash
#!/bin/bash

# Save this as test_installation.sh

echo "🧪 Testing Rails Error Dashboard Installation Flow"
echo "=================================================="

# Function to cleanup
cleanup() {
  rm -f config/initializers/rails_error_dashboard.rb
  git checkout config/routes.rb 2>/dev/null || true
}

# Test 1
echo ""
echo "✓ Test 1: No features"
cleanup
rails generate rails_error_dashboard:install --no-interactive
grep -q "enable_slack_notifications = false" config/initializers/rails_error_dashboard.rb && echo "  ✓ Slack disabled" || echo "  ✗ Slack check failed"

# Test 2
echo ""
echo "✓ Test 2: Slack only"
cleanup
rails generate rails_error_dashboard:install --no-interactive --slack
grep -q "enable_slack_notifications = true" config/initializers/rails_error_dashboard.rb && echo "  ✓ Slack enabled" || echo "  ✗ Slack check failed"

# Test 3
echo ""
echo "✓ Test 3: Multiple features"
cleanup
rails generate rails_error_dashboard:install --no-interactive --slack --email --async_logging
grep -q "enable_slack_notifications = true" config/initializers/rails_error_dashboard.rb && echo "  ✓ Slack enabled" || echo "  ✗ Slack check failed"
grep -q "enable_email_notifications = true" config/initializers/rails_error_dashboard.rb && echo "  ✓ Email enabled" || echo "  ✗ Email check failed"
grep -q "async_logging = true" config/initializers/rails_error_dashboard.rb && echo "  ✓ Async enabled" || echo "  ✗ Async check failed"

# Test 4
echo ""
echo "✓ Test 4: All features"
cleanup
rails generate rails_error_dashboard:install --no-interactive \
  --slack --email --discord --pagerduty --webhooks \
  --async_logging --error_sampling --separate_database \
  --baseline_alerts --similar_errors --co_occurring_errors \
  --error_cascades --error_correlation --platform_comparison --occurrence_patterns

COUNT=$(grep -c "= true" config/initializers/rails_error_dashboard.rb)
if [ "$COUNT" -ge "15" ]; then
  echo "  ✓ All $COUNT features enabled"
else
  echo "  ✗ Only $COUNT features enabled (expected >= 15)"
fi

echo ""
echo "=================================================="
echo "✅ Installation flow tests complete!"
cleanup
```

## Usage

```bash
chmod +x test_installation.sh
./test_installation.sh
```
