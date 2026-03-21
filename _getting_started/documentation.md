---
layout: default
title: "Rails Error Dashboard Documentation"
order: 1
---

# Rails Error Dashboard Documentation

Welcome to the Rails Error Dashboard documentation! This guide will help you get started, customize your setup, and make the most of the advanced features.

## Documentation Structure

### Getting Started
- **[Quickstart Guide](/rails_error_dashboard/docs/quickstart/)** - Get up and running in 5 minutes
- **[Installation](https://github.com/AnjanJ/rails_error_dashboard/blob/main/README.md#installation)** - Detailed installation instructions
- **[Configuration](/rails_error_dashboard/docs/guides/configuration/)** - Complete configuration reference
- **[Migration & Upgrade Strategy](/rails_error_dashboard/docs/reference/migration-strategy/)** - Squashed migrations and v0.2.0 upgrade guide
- **[Uninstall Guide](/rails_error_dashboard/docs/reference/uninstall/)** - Complete removal instructions (manual + automated)
- **[FAQ](/rails_error_dashboard/docs/reference/faq/)** - Common questions answered

### Core Features
- **[Error Tracking & Capture](/rails_error_dashboard/docs/features/#error-tracking--capture)** - Understanding the main dashboard
- **[Workflow Management](/rails_error_dashboard/docs/features/#workflow-management)** - Managing and resolving errors
- **[Notifications](/rails_error_dashboard/docs/guides/notifications/)** - Setting up alerts (Slack, Email, Discord, PagerDuty)

### Monitoring & Health (v0.3)
- **[System Health Snapshots](/rails_error_dashboard/docs/features/#system-health-snapshot)** - GC stats, threads, connection pool, memory, RubyVM cache, YJIT stats
- **[N+1 Query Detection](/rails_error_dashboard/docs/features/#n1-query-detection)** - Detect N+1 queries from breadcrumbs
- **[Job Health](/rails_error_dashboard/docs/features/#job-health)** - Background job queue stats (Sidekiq, SolidQueue, GoodJob)
- **[Database Health](/rails_error_dashboard/docs/features/#database-health)** - PgHero-style connection pool and table stats
- **[Cache Health](/rails_error_dashboard/docs/features/#cache-health)** - Cache hit rates and miss patterns
- **[Deprecation Tracking](/rails_error_dashboard/docs/features/#deprecation-tracking)** - Track Rails deprecation warnings

### Deep Debugging (v0.4)
- **[Local Variable Capture](/rails_error_dashboard/docs/features/#local-variable-capture)** - Capture local variables at the point of exception via TracePoint
- **[Instance Variable Capture](/rails_error_dashboard/docs/features/#instance-variable-capture)** - Capture instance variables from the raising object
- **[Swallowed Exception Detection](/rails_error_dashboard/docs/features/#swallowed-exception-detection)** - Detect silently rescued exceptions (Ruby 3.3+)
- **[On-Demand Diagnostic Dump](/rails_error_dashboard/docs/features/#on-demand-diagnostic-dump)** - Snapshot system state on demand
- **[Rack Attack Event Tracking](/rails_error_dashboard/docs/features/#rack-attack-event-tracking)** - Track throttle/blocklist events as breadcrumbs
- **[Process Crash Capture](/rails_error_dashboard/docs/features/#process-crash-capture)** - Capture crashes via at_exit hook

### Advanced Analytics
- **[Source Code Integration](/rails_error_dashboard/docs/features/source-code-integration/)** - View source code, git blame, and repository links in errors
- **[Advanced Error Grouping](/rails_error_dashboard/docs/features/advanced-error-grouping/)** - Fuzzy matching, co-occurring errors, cascades
- **[Baseline Monitoring](/rails_error_dashboard/docs/features/baseline-monitoring/)** - Statistical anomaly detection and alerts
- **[Platform Comparison](/rails_error_dashboard/docs/features/platform-comparison/)** - iOS vs Android vs API health analysis
- **[Occurrence Patterns](/rails_error_dashboard/docs/features/occurrence-patterns/)** - Cyclical patterns and burst detection
- **[Error Correlation](/rails_error_dashboard/docs/features/error-correlation/)** - Release and user correlation analysis

### Customization
- **[Multi-App Support](/rails_error_dashboard/docs/features/multi-app-performance/)** - Track multiple applications from one dashboard
- **[Customization Guide](/rails_error_dashboard/docs/guides/customization/)** - Customize views, severity rules, and behavior
- **[Settings Dashboard](/rails_error_dashboard/docs/guides/settings/)** - View current configuration and verify feature status
- **[Plugin System](/rails_error_dashboard/docs/features/plugin-system/)** - Build custom plugins and integrations
- **[Database Options](/rails_error_dashboard/docs/guides/database-options/)** - Using a separate database

### Integration
- **[Mobile App Integration](/rails_error_dashboard/docs/guides/mobile-app-integration/)** - Integrate with React Native, Flutter, etc.
- **[Batch Operations](/rails_error_dashboard/docs/guides/batch-operations/)** - Bulk error management
- **[API Reference](/rails_error_dashboard/docs/reference/api-reference/)** - Complete API documentation
- **[Real-Time Updates](/rails_error_dashboard/docs/guides/real-time-updates/)** - Turbo Streams and live updates
- **[Solid Queue Setup](/rails_error_dashboard/docs/guides/solid-queue-setup/)** - Configure Solid Queue for async logging

### Performance & Optimization
- **[Database Optimization](/rails_error_dashboard/docs/guides/database-optimization/)** - Query performance and indexing
- **[Backtrace Limiting](/rails_error_dashboard/docs/guides/backtrace-limiting/)** - Reduce storage size
- **[Error Sampling & Filtering](/rails_error_dashboard/docs/guides/error-sampling-and-filtering/)** - High-volume error handling
- **[Error Trend Visualizations](/rails_error_dashboard/docs/guides/error-trend-visualizations/)** - Analytics and charting

### Development
- **[Changelog](https://github.com/AnjanJ/rails_error_dashboard/blob/main/CHANGELOG.md)** - Version history and updates
- **[Testing](/rails_error_dashboard/docs/reference/testing/)** - Running and writing tests
- **[Troubleshooting](/rails_error_dashboard/docs/reference/troubleshooting/)** - Common problems and solutions
- **[Security Policy](https://github.com/AnjanJ/rails_error_dashboard/blob/main/SECURITY.md)** - Report vulnerabilities and security best practices

## Quick Links

### For New Users
1. [Quickstart Guide](/rails_error_dashboard/docs/quickstart/) - 5-minute setup
2. [Configuration](/rails_error_dashboard/docs/guides/configuration/) - Basic configuration
3. [Notifications](/rails_error_dashboard/docs/guides/notifications/) - Set up Slack alerts

### For Advanced Users
1. [Local Variable Capture](/rails_error_dashboard/docs/features/#local-variable-capture) - Debug with exact variable values
2. [Swallowed Exception Detection](/rails_error_dashboard/docs/features/#swallowed-exception-detection) - Find silently rescued exceptions
3. [Diagnostic Dumps](/rails_error_dashboard/docs/features/#on-demand-diagnostic-dump) - Snapshot system state on demand
4. [Plugin System](/rails_error_dashboard/docs/features/plugin-system/) - Custom integrations

### For Developers
1. [API Reference](/rails_error_dashboard/docs/reference/api-reference/) - Complete API docs
2. [Plugin Development](/rails_error_dashboard/docs/features/plugin-system/#creating-plugins) - Build plugins
3. [Testing Guide](/rails_error_dashboard/docs/reference/testing/) - Test your setup

## Documentation by Use Case

### "I want to get started quickly"
→ [Quickstart Guide](/rails_error_dashboard/docs/quickstart/)

### "I need to customize error severity levels"
→ [Customization Guide](/rails_error_dashboard/docs/guides/customization/#custom-severity-rules)

### "I want Slack notifications for critical errors"
→ [Notifications Guide](/rails_error_dashboard/docs/guides/notifications/#slack-setup)

### "I need to track errors by app version"
→ [Error Correlation](/rails_error_dashboard/docs/features/error-correlation/#release-correlation)

### "I want to build a custom integration"
→ [Plugin System Guide](/rails_error_dashboard/docs/features/plugin-system/)

### "I need to understand platform stability"
→ [Platform Comparison](/rails_error_dashboard/docs/features/platform-comparison/)

### "I want proactive alerting for anomalies"
→ [Baseline Monitoring](/rails_error_dashboard/docs/features/baseline-monitoring/)

### "I want to see exact variable values when an exception occurs"
→ [Local Variable Capture](/rails_error_dashboard/docs/features/#local-variable-capture) (enable `enable_local_variables` and/or `enable_instance_variables`)

### "I want to find exceptions that are silently rescued"
→ [Swallowed Exception Detection](/rails_error_dashboard/docs/features/#swallowed-exception-detection) (requires Ruby 3.3+)

### "I want to snapshot my app's system state on demand"
→ [On-Demand Diagnostic Dump](/rails_error_dashboard/docs/features/#on-demand-diagnostic-dump) (dashboard button or rake task)

### "I want to capture errors from process crashes"
→ [Process Crash Capture](/rails_error_dashboard/docs/features/#process-crash-capture) (at_exit hook writes to disk, imported on next boot)

### "I want to see source code directly in error details"
→ [Source Code Integration](/rails_error_dashboard/docs/features/source-code-integration/)

### "I want to find N+1 queries or cache issues across all errors"
→ [Breadcrumbs](/rails_error_dashboard/docs/features/#breadcrumbs--request-activity-trail-new) (enable breadcrumbs, then visit N+1 Queries or Cache Health pages)

### "I need to track multiple Rails applications"
→ [Multi-App Support](/rails_error_dashboard/docs/features/multi-app-performance/)

### "I need to uninstall Rails Error Dashboard"
→ [Uninstall Guide](/rails_error_dashboard/docs/reference/uninstall/)

## Searching the Documentation

- **Configuration options**: See [Configuration Guide](/rails_error_dashboard/docs/guides/configuration/)
- **API methods**: See [API Reference](/rails_error_dashboard/docs/reference/api-reference/)
- **Term definitions**: See [Glossary](/rails_error_dashboard/docs/reference/glossary/)
- **Code examples**: Most guides include code examples
- **Troubleshooting**: Each guide has a troubleshooting section

## Getting Help

- **Issues**: [GitHub Issues](https://github.com/AnjanJ/rails_error_dashboard/issues)
- **Discussions**: [GitHub Discussions](https://github.com/AnjanJ/rails_error_dashboard/discussions)
- **Security**: [Security Policy](https://github.com/AnjanJ/rails_error_dashboard/blob/main/SECURITY.md) - Report security vulnerabilities
- **Stack Overflow**: Tag your questions with `rails-error-dashboard`

## Documentation Versions

This documentation is for **Rails Error Dashboard v0.4.0** (Latest).

For version history, see the [Changelog](https://github.com/AnjanJ/rails_error_dashboard/blob/main/CHANGELOG.md).

---

**Need help?** Check the guides above or [open an issue](https://github.com/AnjanJ/rails_error_dashboard/issues).
