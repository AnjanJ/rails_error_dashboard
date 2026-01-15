# Plugin System Guide

Rails Error Dashboard includes a powerful plugin system that allows you to extend functionality and integrate with external services.

## Overview

The plugin system provides event hooks throughout the error lifecycle, allowing you to:

- 📊 **Track custom metrics** (StatsD, Datadog, Prometheus)
- 📝 **Log audit trails** for compliance
- 🎫 **Create tickets** in project management tools (Jira, Linear, GitHub Issues)
- 📢 **Send custom notifications** beyond built-in backends
- 🔍 **Analyze error patterns** with ML/AI services
- 💾 **Store errors** in external databases or data warehouses
- 🔔 **Trigger custom workflows** based on error events

## Quick Start

### 1. Create a Plugin

```ruby
# config/initializers/error_dashboard_plugins.rb

class MyCustomPlugin < RailsErrorDashboard::Plugin
  def name
    "My Custom Plugin"
  end

  def description
    "Does something awesome with errors"
  end

  def on_error_logged(error_log)
    # Called when a new error occurs
    puts "New error: #{error_log.error_type}"
  end
end
```

### 2. Register the Plugin

```ruby
# config/initializers/error_dashboard_plugins.rb

RailsErrorDashboard.register_plugin(MyCustomPlugin.new)
```

That's it! Your plugin will now receive events whenever errors are logged.

---

## Available Event Hooks

The plugin system provides six event hooks:

### 1. `on_error_logged(error_log)`

**When**: A new error occurs (first occurrence)

**Parameters**:
- `error_log` (ErrorLog) - The newly created error record

**Example**:
```ruby
def on_error_logged(error_log)
  # Send to metrics service
  Metrics.increment("errors.new")

  # Create Jira ticket for critical errors
  if error_log.critical?
    JiraService.create_ticket(error_log)
  end
end
```

### 2. `on_error_recurred(error_log)`

**When**: An existing error occurs again (subsequent occurrences)

**Parameters**:
- `error_log` (ErrorLog) - The updated error record with incremented occurrence_count

**Example**:
```ruby
def on_error_recurred(error_log)
  # Alert if error occurs frequently
  if error_log.occurrence_count > 10
    AlertService.send_alert("Error #{error_log.id} has occurred #{error_log.occurrence_count} times!")
  end
end
```

### 3. `on_error_resolved(error_log)`

**When**: An error is marked as resolved (single error)

**Parameters**:
- `error_log` (ErrorLog) - The resolved error record

**Example**:
```ruby
def on_error_resolved(error_log)
  # Update Jira ticket status
  JiraService.resolve_ticket(error_log)

  # Track resolution metrics
  Metrics.increment("errors.resolved")
  Metrics.timing("errors.time_to_resolve", error_log.resolved_at - error_log.first_seen_at)
end
```

### 4. `on_errors_batch_resolved(error_logs)`

**When**: Multiple errors are resolved via batch operation

**Parameters**:
- `error_logs` (Array<ErrorLog>) - Array of resolved error records

**Example**:
```ruby
def on_errors_batch_resolved(error_logs)
  # Log batch resolution for audit trail
  AuditLog.create(
    action: "batch_resolve",
    count: error_logs.size,
    error_ids: error_logs.map(&:id)
  )
end
```

### 5. `on_errors_batch_deleted(error_ids)`

**When**: Multiple errors are deleted via batch operation

**Parameters**:
- `error_ids` (Array<Integer>) - Array of deleted error IDs

**Example**:
```ruby
def on_errors_batch_deleted(error_ids)
  # Archive deleted errors to external storage
  ArchiveService.archive_errors(error_ids)

  # Log for compliance
  AuditLog.create(
    action: "batch_delete",
    count: error_ids.size
  )
end
```

### 6. `on_error_viewed(error_log)`

**When**: An error is viewed in the dashboard

**Parameters**:
- `error_log` (ErrorLog) - The viewed error record

**Example**:
```ruby
def on_error_viewed(error_log)
  # Track error views for analytics
  Analytics.track("error_viewed", {
    error_id: error_log.id,
    error_type: error_log.error_type
  })
end
```

---

## Plugin API Reference

### Base Plugin Class

```ruby
class RailsErrorDashboard::Plugin
  # Required: Plugin name (must be unique)
  def name
    raise NotImplementedError
  end

  # Optional: Plugin description
  def description
    "No description provided"
  end

  # Optional: Plugin version
  def version
    "1.0.0"
  end

  # Optional: Called when plugin is registered
  def on_register
    # Initialization logic
  end

  # Optional: Check if plugin should run
  def enabled?
    true
  end

  # Event hooks (all optional, implement as needed)
  def on_error_logged(error_log); end
  def on_error_recurred(error_log); end
  def on_error_resolved(error_log); end
  def on_errors_batch_resolved(error_logs); end
  def on_errors_batch_deleted(error_ids); end
  def on_error_viewed(error_log); end
end
```

### Registration Methods

```ruby
# Register a plugin
RailsErrorDashboard.register_plugin(plugin_instance)
# => true (success) or false (already registered)

# Unregister a plugin by name
RailsErrorDashboard.unregister_plugin("My Plugin Name")

# Get all registered plugins
RailsErrorDashboard.plugins
# => [plugin1, plugin2, ...]

# Access plugin registry directly
RailsErrorDashboard::PluginRegistry.count
# => 3

RailsErrorDashboard::PluginRegistry.names
# => ["Plugin 1", "Plugin 2", "Plugin 3"]

RailsErrorDashboard::PluginRegistry.info
# => [{ name: "...", version: "...", description: "...", enabled: true }, ...]
```

---

## Example Plugins

### Example 1: Metrics Tracking (StatsD/Datadog)

```ruby
class MetricsPlugin < RailsErrorDashboard::Plugin
  def name
    "Metrics Tracker"
  end

  def on_error_logged(error_log)
    StatsD.increment("errors.new")
    StatsD.increment("errors.by_type.#{sanitize(error_log.error_type)}")
    StatsD.increment("errors.by_platform.#{error_log.platform}")
  end

  def on_error_resolved(error_log)
    StatsD.increment("errors.resolved")

    # Track time to resolution
    resolution_time = error_log.resolved_at - error_log.first_seen_at
    StatsD.timing("errors.time_to_resolve", resolution_time)
  end

  private

  def sanitize(name)
    name.gsub('::', '.').downcase
  end
end

# Register
RailsErrorDashboard.register_plugin(MetricsPlugin.new)
```

### Example 2: Audit Logging

```ruby
class AuditLogPlugin < RailsErrorDashboard::Plugin
  def initialize(logger: Rails.logger)
    @logger = logger
  end

  def name
    "Audit Logger"
  end

  def on_error_logged(error_log)
    log_event("error_logged", error_log)
  end

  def on_error_resolved(error_log)
    log_event("error_resolved", error_log, {
      resolved_by: error_log.resolved_by_name,
      resolution_comment: error_log.resolution_comment
    })
  end

  def on_errors_batch_deleted(error_ids)
    @logger.info("[Audit] Batch deleted #{error_ids.size} errors: #{error_ids.join(', ')}")
  end

  private

  def log_event(event, error_log, extra = {})
    @logger.info("[Audit] #{event}: #{error_log.id} (#{error_log.error_type}) #{extra.to_json}")
  end
end

# Register
RailsErrorDashboard.register_plugin(AuditLogPlugin.new)
```

### Example 3: Jira Integration

```ruby
class JiraIntegrationPlugin < RailsErrorDashboard::Plugin
  def initialize(jira_client:, project_key:, only_critical: true)
    @jira = jira_client
    @project_key = project_key
    @only_critical = only_critical
  end

  def name
    "Jira Integration"
  end

  def enabled?
    @jira.present?
  end

  def on_error_logged(error_log)
    return if @only_critical && !error_log.critical?

    create_jira_issue(error_log)
  end

  def on_error_resolved(error_log)
    # Find related Jira ticket and resolve it
    resolve_jira_issue(error_log)
  end

  private

  def create_jira_issue(error_log)
    issue = @jira.Issue.build
    issue.save({
      "fields" => {
        "project" => { "key" => @project_key },
        "summary" => "[#{error_log.environment}] #{error_log.error_type}",
        "description" => build_description(error_log),
        "issuetype" => { "name" => "Bug" },
        "priority" => { "name" => jira_priority(error_log) }
      }
    })

    # Store Jira ticket ID in error metadata
    error_log.update(metadata: error_log.metadata.merge(jira_ticket: issue.key))
  end

  def build_description(error_log)
    <<~DESC
      Error Type: #{error_log.error_type}
      Message: #{error_log.message}
      Platform: #{error_log.platform}
      Environment: #{error_log.environment}

      View in Dashboard: #{dashboard_url(error_log)}
    DESC
  end

  def jira_priority(error_log)
    case error_log.severity.to_s
    when "critical" then "Highest"
    when "high" then "High"
    when "medium" then "Medium"
    else "Low"
    end
  end

  def dashboard_url(error_log)
    "#{RailsErrorDashboard.configuration.dashboard_base_url}/error_dashboard/errors/#{error_log.id}"
  end

  def resolve_jira_issue(error_log)
    ticket_key = error_log.metadata&.dig("jira_ticket")
    return unless ticket_key

    issue = @jira.Issue.find(ticket_key)
    issue.transition("Done")
  end
end

# Register with Jira client
jira_client = JIRA::Client.new(
  username: ENV['JIRA_USERNAME'],
  password: ENV['JIRA_API_TOKEN'],
  site: ENV['JIRA_URL'],
  context_path: '',
  auth_type: :basic
)

RailsErrorDashboard.register_plugin(
  JiraIntegrationPlugin.new(
    jira_client: jira_client,
    project_key: "MYPROJECT",
    only_critical: true
  )
)
```

### Example 4: Conditional Plugin (Production Only)

```ruby
class ProductionOnlyPlugin < RailsErrorDashboard::Plugin
  def name
    "Production Alert Plugin"
  end

  def enabled?
    Rails.env.production?
  end

  def on_error_logged(error_log)
    # Only runs in production
    ProductionAlertService.send_alert(error_log)
  end
end

RailsErrorDashboard.register_plugin(ProductionOnlyPlugin.new)
```

### Example 5: ML Error Classification

```ruby
class ErrorClassificationPlugin < RailsErrorDashboard::Plugin
  def name
    "ML Error Classifier"
  end

  def on_error_logged(error_log)
    # Use ML to classify error severity/category
    classification = MLService.classify_error(
      error_type: error_log.error_type,
      message: error_log.message,
      backtrace: error_log.backtrace
    )

    # Store ML insights in metadata
    error_log.update(
      metadata: error_log.metadata.merge(
        ml_category: classification[:category],
        ml_confidence: classification[:confidence],
        ml_similar_errors: classification[:similar_ids]
      )
    )
  end
end

RailsErrorDashboard.register_plugin(ErrorClassificationPlugin.new)
```

---

## Built-in Example Plugins

Rails Error Dashboard includes three example plugins you can use as templates:

### 1. MetricsPlugin

**Location**: `lib/rails_error_dashboard/plugins/metrics_plugin.rb`

**Purpose**: Track error metrics and send to monitoring services

**Usage**:
```ruby
require 'rails_error_dashboard/plugins/metrics_plugin'

RailsErrorDashboard.register_plugin(
  RailsErrorDashboard::Plugins::MetricsPlugin.new
)
```

### 2. AuditLogPlugin

**Location**: `lib/rails_error_dashboard/plugins/audit_log_plugin.rb`

**Purpose**: Log all error dashboard activities for compliance

**Usage**:
```ruby
require 'rails_error_dashboard/plugins/audit_log_plugin'

RailsErrorDashboard.register_plugin(
  RailsErrorDashboard::Plugins::AuditLogPlugin.new(logger: Rails.logger)
)
```

### 3. JiraIntegrationPlugin

**Location**: `lib/rails_error_dashboard/plugins/jira_integration_plugin.rb`

**Purpose**: Automatically create Jira tickets for critical errors

**Usage**:
```ruby
require 'rails_error_dashboard/plugins/jira_integration_plugin'

RailsErrorDashboard.register_plugin(
  RailsErrorDashboard::Plugins::JiraIntegrationPlugin.new(
    jira_url: ENV['JIRA_URL'],
    jira_username: ENV['JIRA_USERNAME'],
    jira_api_token: ENV['JIRA_API_TOKEN'],
    jira_project_key: ENV['JIRA_PROJECT_KEY'],
    only_critical: true
  )
)
```

---

## Best Practices

### 1. Error Handling

Always handle errors gracefully in plugins to prevent breaking the main application:

```ruby
def on_error_logged(error_log)
  send_to_external_service(error_log)
rescue => e
  # Plugin errors are automatically logged by safe_execute
  # But you can add custom handling
  Rails.logger.error("My plugin failed: #{e.message}")
end
```

**Note**: The base `Plugin` class includes `safe_execute` that wraps all event hooks with error handling.

### 2. Conditional Execution

Use `enabled?` to control when plugins run:

```ruby
def enabled?
  # Only run if configuration present
  ENV['EXTERNAL_SERVICE_API_KEY'].present? &&
  # Only run in production
  Rails.env.production? &&
  # Only run during business hours
  Time.current.hour.between?(9, 17)
end
```

### 3. Async Processing

For slow operations, use background jobs:

```ruby
def on_error_logged(error_log)
  # Don't block error logging with slow API calls
  ExternalServiceJob.perform_later(error_log.id)
end
```

### 4. Initialization

Use `on_register` for one-time setup:

```ruby
def on_register
  @client = ExternalService::Client.new(api_key: ENV['API_KEY'])
  @cache = Rails.cache

  Rails.logger.info("#{name} initialized successfully")
end
```

### 5. Plugin Dependencies

Check for required gems/services:

```ruby
def enabled?
  return false unless defined?(Datadog)

  ENV['DATADOG_API_KEY'].present?
end
```

---

## Configuration Examples

### Multi-Plugin Setup

```ruby
# config/initializers/error_dashboard_plugins.rb

Rails.application.configure do
  # Metrics tracking
  RailsErrorDashboard.register_plugin(
    RailsErrorDashboard::Plugins::MetricsPlugin.new
  )

  # Audit logging
  RailsErrorDashboard.register_plugin(
    RailsErrorDashboard::Plugins::AuditLogPlugin.new(
      logger: Logger.new(Rails.root.join('log', 'error_audit.log'))
    )
  )

  # Jira integration (production only)
  if Rails.env.production?
    RailsErrorDashboard.register_plugin(
      RailsErrorDashboard::Plugins::JiraIntegrationPlugin.new(
        jira_url: ENV['JIRA_URL'],
        jira_username: ENV['JIRA_USERNAME'],
        jira_api_token: ENV['JIRA_API_TOKEN'],
        jira_project_key: 'PROD',
        only_critical: true
      )
    )
  end
end
```

### Environment-Specific Plugins

```ruby
# config/initializers/error_dashboard_plugins.rb

Rails.application.configure do
  case Rails.env
  when 'production'
    # Production: Full monitoring stack
    RailsErrorDashboard.register_plugin(DatadogPlugin.new)
    RailsErrorDashboard.register_plugin(PagerDutyPlugin.new)
    RailsErrorDashboard.register_plugin(JiraPlugin.new)

  when 'staging'
    # Staging: Metrics only
    RailsErrorDashboard.register_plugin(MetricsPlugin.new)

  when 'development'
    # Development: Console logging only
    RailsErrorDashboard.register_plugin(ConsoleLoggerPlugin.new)
  end
end
```

---

## Debugging Plugins

### Check Registered Plugins

```ruby
# Rails console

# List all plugins
RailsErrorDashboard.plugins
# => [#<MetricsPlugin>, #<AuditLogPlugin>]

# Get plugin names
RailsErrorDashboard::PluginRegistry.names
# => ["Metrics Tracker", "Audit Logger"]

# Get plugin info
RailsErrorDashboard::PluginRegistry.info
# => [
#   { name: "Metrics Tracker", version: "1.0.0", description: "...", enabled: true },
#   { name: "Audit Logger", version: "1.0.0", description: "...", enabled: true }
# ]

# Find specific plugin
RailsErrorDashboard::PluginRegistry.find("Metrics Tracker")
# => #<MetricsPlugin>
```

### Test Plugin Events

```ruby
# Rails console

# Create test error
error = begin
  raise StandardError, "Test error"
rescue => e
  e
end

error_log = RailsErrorDashboard::Commands::LogError.call(error, {
  controller_name: "TestController",
  action_name: "test"
})

# Manually trigger plugin events
RailsErrorDashboard::PluginRegistry.dispatch(:on_error_logged, error_log)

# Check plugin is enabled
plugin = RailsErrorDashboard::PluginRegistry.find("My Plugin")
plugin.enabled?
# => true/false
```

### Plugin Logs

Plugin errors are automatically logged:

```text
# log/production.log
Plugin 'My Plugin' failed in on_error_logged: Connection refused
/path/to/plugin.rb:45:in `send_to_service'
/path/to/plugin.rb:12:in `on_error_logged'
```

---

## Performance Considerations

### 1. Async Operations

Plugins run synchronously during error logging. Keep operations fast:

```ruby
# Bad: Slow synchronous API call
def on_error_logged(error_log)
  SlowExternalAPI.send_error(error_log) # Blocks error logging
end

# Good: Async job
def on_error_logged(error_log)
  SendErrorJob.perform_later(error_log.id) # Non-blocking
end
```

### 2. Bulk Operations

Use batch hooks efficiently:

```ruby
# Good: Single API call for batch
def on_errors_batch_resolved(error_logs)
  ExternalAPI.bulk_update(error_logs.map(&:id))
end

# Bad: N API calls
def on_errors_batch_resolved(error_logs)
  error_logs.each do |error_log|
    ExternalAPI.update(error_log.id) # N+1 API calls
  end
end
```

### 3. Caching

Cache expensive operations:

```ruby
def on_error_logged(error_log)
  client = Rails.cache.fetch("external_api_client", expires_in: 1.hour) do
    ExternalAPI::Client.new(api_key: ENV['API_KEY'])
  end

  client.send_error(error_log)
end
```

---

## Security Considerations

### 1. Sensitive Data

Be careful with error messages and backtraces:

```ruby
def on_error_logged(error_log)
  # Filter sensitive data before sending externally
  sanitized_message = sanitize_sensitive_data(error_log.message)

  ExternalService.send(
    error_type: error_log.error_type,
    message: sanitized_message
    # Don't send: passwords, tokens, API keys, PII
  )
end

private

def sanitize_sensitive_data(message)
  message
    .gsub(/password[=:]\s*\S+/i, 'password=REDACTED')
    .gsub(/token[=:]\s*\S+/i, 'token=REDACTED')
    .gsub(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, 'EMAIL_REDACTED')
end
```

### 2. API Keys

Store credentials securely:

```ruby
# Good: Environment variables
def initialize
  @api_key = ENV['EXTERNAL_SERVICE_API_KEY']
end

# Bad: Hardcoded
def initialize
  @api_key = "secret_key_123" # Never do this
end
```

### 3. Rate Limiting

Implement rate limiting to prevent abuse:

```ruby
def on_error_logged(error_log)
  # Only send first 100 errors per hour to external service
  count = Rails.cache.increment("plugin_events:#{Time.current.hour}", 1, expires_in: 1.hour)

  return if count > 100

  ExternalService.send(error_log)
end
```

---

## Testing Plugins

### RSpec Example

```ruby
# spec/plugins/my_plugin_spec.rb

RSpec.describe MyPlugin do
  let(:plugin) { described_class.new }
  let(:error_log) { create(:error_log, error_type: "StandardError") }

  describe "#name" do
    it "returns plugin name" do
      expect(plugin.name).to eq("My Plugin")
    end
  end

  describe "#enabled?" do
    it "is enabled when API key is present" do
      allow(ENV).to receive(:[]).with('API_KEY').and_return('key123')
      expect(plugin.enabled?).to be true
    end

    it "is disabled when API key is missing" do
      allow(ENV).to receive(:[]).with('API_KEY').and_return(nil)
      expect(plugin.enabled?).to be false
    end
  end

  describe "#on_error_logged" do
    it "sends error to external service" do
      expect(ExternalService).to receive(:send).with(error_log)
      plugin.on_error_logged(error_log)
    end

    it "handles errors gracefully" do
      allow(ExternalService).to receive(:send).and_raise(StandardError, "API error")

      expect {
        plugin.on_error_logged(error_log)
      }.not_to raise_error
    end
  end
end
```

### Integration Testing

```ruby
# spec/integration/plugin_system_spec.rb

RSpec.describe "Plugin System" do
  before do
    RailsErrorDashboard::PluginRegistry.clear
  end

  it "dispatches events to registered plugins" do
    plugin = MyPlugin.new
    RailsErrorDashboard.register_plugin(plugin)

    expect(plugin).to receive(:on_error_logged)

    error = begin
      raise StandardError, "Test"
    rescue => e
      e
    end

    RailsErrorDashboard::Commands::LogError.call(error, {})
  end
end
```

---

## FAQ

### Q: Can plugins modify error_log records?

**A**: Yes, plugins can call `error_log.update(...)` to add custom data:

```ruby
def on_error_logged(error_log)
  error_log.update(
    metadata: error_log.metadata.merge(
      external_ticket_id: create_ticket(error_log)
    )
  )
end
```

### Q: What happens if a plugin crashes?

**A**: Plugins are wrapped in `safe_execute` which catches errors and logs them without breaking the main application:

```text
Plugin 'My Plugin' failed in on_error_logged: Connection refused
```

### Q: Can I use background jobs in plugins?

**A**: Yes, recommended for slow operations:

```ruby
def on_error_logged(error_log)
  MyPluginJob.perform_later(error_log.id)
end
```

### Q: How do I unregister a plugin?

**A**:
```ruby
RailsErrorDashboard.unregister_plugin("Plugin Name")
```

### Q: Can plugins depend on each other?

**A**: Not directly. Keep plugins independent. If you need shared logic, extract it to a service class.

### Q: How many plugins can I register?

**A**: No hard limit, but be mindful of performance. Each event dispatches to all enabled plugins.

---

## Troubleshooting

### Plugin Not Receiving Events

1. Check plugin is registered:
```ruby
RailsErrorDashboard::PluginRegistry.names
```

2. Check `enabled?` returns true:
```ruby
plugin = RailsErrorDashboard::PluginRegistry.find("My Plugin")
plugin.enabled?
```

3. Check for errors in logs:
```bash
tail -f log/production.log | grep "Plugin"
```

### Plugin Registered Multiple Times

Plugins are only registered once. Subsequent registrations with the same name are ignored:

```ruby
RailsErrorDashboard.register_plugin(MyPlugin.new) # Registered
RailsErrorDashboard.register_plugin(MyPlugin.new) # Skipped (logs warning)
```

### Performance Issues

If plugins slow down error logging:

1. Move slow operations to background jobs
2. Use `enabled?` to conditionally run plugins
3. Cache expensive operations
4. Profile plugin code

---

## Related Documentation

- [Main README](../README.md) - Overall gem documentation
- [Notifications](guides/NOTIFICATIONS.md) - Built-in notification backends
- [Batch Operations](guides/BATCH_OPERATIONS.md) - Batch operations

---

**Plugin system is fully functional!** 🎉
