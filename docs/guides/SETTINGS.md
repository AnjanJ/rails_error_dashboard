# Settings Dashboard

The Settings page provides a read-only view of your Rails Error Dashboard configuration, making it easy to verify which features are enabled and review current settings without digging through initializer files.

---

## Accessing Settings

Navigate to the Settings page from the main dashboard:

1. Click the **gear icon** (⚙️) in the navigation bar
2. Or visit `/error_dashboard/settings` directly

**Authentication**: Requires HTTP Basic Auth (same credentials as dashboard access)

---

## Settings Overview

The Settings page is organized into six sections:

### 1. Core Features

Shows the status of fundamental dashboard features:

- **Error Middleware**: Whether the error-catching middleware is active
- **Rails.error Subscriber**: Whether Rails 7+ error reporter integration is active
- **Authentication**: Confirms HTTP Basic Auth is always enforced
- **Data Retention**: Number of days errors are kept before auto-deletion
- **Max Backtrace Lines**: Stack trace depth limit

**Example Display:**
```text
Error Middleware                 ✓ Enabled
Rails.error Subscriber          ✓ Enabled
Authentication                   🔒 Always Required
Data Retention                   90 days
Max Backtrace Lines              50 lines
```

---

### 2. Performance Features

Displays async logging and optimization settings:

- **Async Logging**: Whether errors are logged in background jobs
- **Async Adapter**: Which job backend is used (Sidekiq, Solid Queue, or :async)
- **Error Sampling**: Percentage of non-critical errors being logged
- **Rate Limiting**: API rate limiting status and threshold

**Example Display:**
```text
Async Logging                    ✓ Enabled
Async Adapter                    Sidekiq
Error Sampling                   100% (all errors)
Rate Limiting                    ✗ Disabled
```

**When sampling is active:**
```text
Error Sampling                   10% (critical always logged)
```

---

### 3. Notification Channels

Shows which notification channels are configured and active:

- **Slack Notifications**: Webhook URL (masked) and status
- **Email Notifications**: Recipients count and status
- **Discord Notifications**: Webhook URL (masked) and status
- **PagerDuty Notifications**: Integration key (masked) and status
- **Custom Webhooks**: Number of configured webhooks

**Example Display:**
```text
Slack Notifications              ✓ Enabled (https://hooks.slack...T123)
Email Notifications              ✓ Enabled (3 recipients)
Discord Notifications            ✗ Disabled
PagerDuty Notifications          ✓ Enabled (Critical errors only)
Custom Webhooks                  2 configured
```

**Security Note**: Webhook URLs and sensitive keys are partially masked for security (e.g., `https://hooks.slack.com/services/...T123`).

---

### 4. Advanced Analytics

Displays the status of all 7 advanced analytics features:

- **Similar Errors**: Fuzzy error matching with Jaccard/Levenshtein
- **Co-occurring Errors**: Errors happening together detection
- **Error Cascades**: Parent→child error relationship tracking
- **Error Correlation**: Version/user/time correlation analysis
- **Platform Comparison**: iOS vs Android vs Web health comparison
- **Occurrence Patterns**: Cyclical and burst pattern detection
- **Baseline Alerts**: Statistical anomaly detection

**Example Display:**
```text
Similar Errors                   ✓ Enabled
Co-occurring Errors              ✓ Enabled
Error Cascades                   ✗ Disabled
Error Correlation                ✓ Enabled
Platform Comparison              ✓ Enabled
Occurrence Patterns              ✗ Disabled
Baseline Alerts                  ✓ Enabled (2.0 std devs)
```

**Baseline Alert Details:**
When baseline alerts are enabled, additional information is shown:
- Threshold (standard deviations)
- Cooldown period (minutes between alerts)
- Severities being monitored

---

### 5. Database Configuration

Shows database and multi-app settings:

- **Application Name**: Current application identifier
- **Database Connection**: Which database is being used
- **Separate Database**: Whether errors use a dedicated database

**Example Display:**
```text
Application Name                 my-api-production
Database Connection              Primary database
Separate Database                ✗ Not configured
```

**With separate database:**
```text
Application Name                 my-api-production
Database Connection              errors (dedicated)
Separate Database                ✓ Configured
```

---

### 6. Enhanced Metrics

Displays additional context being tracked with errors:

- **App Version**: Application version string
- **Git SHA**: Git commit SHA being tracked
- **Git Repository**: Repository URL for commit links
- **Total Users**: User count for impact percentage calculations

**Example Display:**
```text
App Version                      1.2.3
Git SHA                          abc123def456
Git Repository                   https://github.com/user/repo
Total Users                      10,000 users
```

**When not configured:**
```text
App Version                      Not configured
Git SHA                          Not configured
Git Repository                   Not configured
Total Users                      Auto-detected
```

---

## Use Cases

### 1. Verify Feature Activation

**Scenario**: You enabled baseline alerts in the initializer but want to confirm it's active.

**Solution**: Check the "Advanced Analytics" section for "Baseline Alerts" status.

---

### 2. Audit Production Configuration

**Scenario**: Before deploying to production, verify which features are enabled.

**Solution**: Review all sections to ensure:
- Async logging is enabled
- Appropriate notification channels are active
- Sampling rate is configured correctly
- Database settings match infrastructure

---

### 3. Troubleshoot Notification Issues

**Scenario**: Slack notifications aren't arriving.

**Solution**: Check "Notification Channels" section to verify:
1. Slack Notifications shows "Enabled"
2. Webhook URL is present and correct (last 4 chars match your webhook)
3. Email also shows recipients if configured

---

### 4. Review Data Retention Policy

**Scenario**: Database growing too large, want to check retention settings.

**Solution**: Check "Core Features" section for "Data Retention" setting. If it's 90 days and you want less, update initializer to 30 days.

---

### 5. Verify Advanced Analytics Features

**Scenario**: Correlation analysis isn't showing data.

**Solution**: Check "Advanced Analytics" section - if "Error Correlation" shows "Disabled", enable it in the initializer.

---

## Important Notes

### Read-Only View

The Settings page is **read-only**. To change settings:

1. Edit `config/initializers/rails_error_dashboard.rb`
2. Restart your Rails server
3. Refresh the Settings page to see updated values

**Example:**
```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  config.enable_baseline_alerts = true  # Change this
end
```

After restarting, Settings page will show:
```text
Baseline Alerts                  ✓ Enabled (2.0 std devs)
```

---

### Security Considerations

**Masked Sensitive Data:**
- Webhook URLs show only protocol and last 4 characters
- API keys show only last 4 characters
- Passwords are never displayed

**Access Control:**
- Settings page requires HTTP Basic Auth
- No API endpoint for programmatic access (security by design)
- Only accessible to authenticated dashboard users

---

### Configuration Validation

The Settings page shows **current active configuration**, not what's in the file. This is useful for:

1. **Environment Variable Overrides**: If ENV vars override initializer, Settings shows actual active value
2. **Default Values**: Shows what defaults are being used when not explicitly configured
3. **Feature Detection**: Confirms which optional features are actually loaded

**Example:**
If your initializer has:
```ruby
config.slack_webhook_url = ENV["SLACK_WEBHOOK_URL"]
```

Settings page will show:
- "Not configured" if `SLACK_WEBHOOK_URL` is not set
- Masked webhook URL if the environment variable is present

---

## Troubleshooting

### Settings Page Shows Different Values Than Initializer

**Cause**: Environment variables might be overriding initializer values.

**Solution**: Check for ENV var usage in initializer:
```ruby
# This will use ENV var if present, initializer value as fallback
config.option = ENV.fetch("OPTION", "default_value")
```

Run `echo $OPTION` in your shell to see actual environment value.

---

### Feature Shows "Enabled" But Not Working

**Possible Causes:**

1. **Background Jobs Not Running**:
   - Async logging enabled but Sidekiq/Solid Queue not running
   - Check: `ps aux | grep sidekiq`

2. **Missing Dependencies**:
   - Notification channel enabled but webhook URL not configured
   - Check: Settings page shows "Not configured" for webhook

3. **Insufficient Data**:
   - Advanced analytics enabled but minimum data not available yet
   - Check: Analytics pages for "Insufficient data" messages

---

### Cannot Access Settings Page

**Problem**: 401 Unauthorized or authentication prompt loops.

**Solution**:
1. Verify credentials in initializer match what you're entering
2. Check for browser cached credentials (clear browser cache)
3. Try incognito/private browsing window
4. Verify `dashboard_username` and `dashboard_password` are set

---

## Navigating from Settings

From the Settings page, you can:

- **Back to Dashboard**: Click "Back to Dashboard" button
- **Main navigation**: Use navbar to access other sections
- **Direct links**: Settings page has no direct links to other pages (read-only view)

---

## API Access

**Note**: There is no API endpoint for accessing settings programmatically. This is intentional for security reasons.

**Alternative**: If you need programmatic access to configuration:
```ruby
# In Rails console or application code
config = RailsErrorDashboard.configuration
config.async_logging  # => true
config.retention_days  # => 90
```

---

## Related Documentation

- **[Configuration Guide](CONFIGURATION.md)** - Complete configuration options
- **[Configuration Defaults Reference](CONFIGURATION.md#configuration-defaults-reference)** - All defaults in one table
- **[Troubleshooting](CONFIGURATION.md#troubleshooting)** - Configuration-related issues

---

**Pro Tip**: Bookmark the Settings page URL (`/error_dashboard/settings`) for quick configuration verification during deployments.
