# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2024-12-24

### 🎉 Initial Beta Release

Rails Error Dashboard is now available as a beta gem! This release includes core error tracking functionality (Phase 1) with comprehensive testing across multiple Rails and Ruby versions.

### ✨ Added

#### Core Error Tracking (Phase 1 - Complete)
- **Error Logging & Deduplication**
  - Automatic error capture via middleware
  - Smart deduplication by error hash (type + message + location)
  - Occurrence counting for duplicate errors
  - Controller and action context tracking
  - Request metadata (URL, HTTP method, parameters, headers)
  - User information tracking (user_id, IP address)

- **Beautiful Dashboard UI**
  - Clean, modern interface for viewing errors
  - Pagination with Pagy
  - Error filtering and search
  - Individual error detail pages
  - Stack trace viewer with syntax highlighting
  - Mark errors as resolved

- **Platform Detection**
  - Automatic detection of iOS, Android, Web, API platforms
  - Platform-specific filtering
  - Browser and device information

- **Time-Based Features**
  - Recent errors view (last 24 hours, 7 days, 30 days)
  - First and last occurrence tracking
  - Occurred_at timestamps

#### Multi-Channel Notifications (Phase 2 - Complete)
- **Slack Integration**
  - Real-time error notifications to Slack channels
  - Rich message formatting with error details
  - Configurable webhooks

- **Email Notifications**
  - HTML and text email templates
  - Error alerts via Action Mailer
  - Customizable recipient lists

- **Discord Integration**
  - Webhook-based notifications
  - Formatted error messages

- **PagerDuty Integration**
  - Critical error escalation
  - Incident creation with severity levels

- **Custom Webhooks**
  - Send errors to any HTTP endpoint
  - Flexible payload configuration

#### Advanced Features
- **Batch Operations** (Phase 3 - Complete)
  - Bulk resolve multiple errors
  - Bulk delete errors
  - API endpoints for batch operations

- **Analytics & Insights** (Phase 4 - Complete)
  - Error trends over time
  - Most common errors
  - Error distribution by platform
  - Developer insights (errors by controller/action)
  - Dashboard statistics

- **Plugin System** (Phase 5 - Complete)
  - Extensible plugin architecture
  - Built-in plugins:
    - Jira Integration Plugin
    - Metrics Plugin (Prometheus/StatsD)
    - Audit Log Plugin
  - Event hooks for error lifecycle
  - Easy custom plugin development

#### Configuration & Deployment
- **Flexible Configuration**
  - Initializer-based setup
  - Per-environment settings
  - Optional features can be disabled

- **Separate Database Support**
  - Use dedicated database for error logs
  - Migration guide included
  - Production-ready setup

- **Mobile App Integration**
  - RESTful API for error reporting
  - React Native and Expo examples
  - Flutter integration guide

### 🧪 Testing & Quality

- **Comprehensive Test Suite**
  - 111 RSpec examples for Phase 1
  - Factory Bot for test data
  - Database Cleaner integration
  - SimpleCov code coverage

- **Multi-Version CI**
  - Tested on Ruby 3.2 and 3.3
  - Tested on Rails 7.0, 7.1, 7.2, and 8.0
  - All 8 combinations passing in CI
  - GitHub Actions workflow

### 📚 Documentation

- **User Guides**
  - Comprehensive README with examples
  - Mobile App Integration Guide
  - Notification Configuration Guide
  - Batch Operations Guide
  - Plugin Development Guide

- **Operations Guides**
  - Separate Database Migration Guide
  - Multi-Version Testing Guide
  - CI Troubleshooting Guide (for contributors)

- **Navigation**
  - Documentation Index for easy discovery
  - Cross-referenced guides

### 🔧 Technical Details

- **Requirements**
  - Ruby >= 3.2.0
  - Rails >= 7.0.0

- **Dependencies**
  - pagy ~> 9.0 (pagination)
  - browser ~> 6.0 (platform detection)
  - groupdate ~> 6.0 (time-based queries)
  - httparty ~> 0.21 (HTTP client)
  - concurrent-ruby ~> 1.3.0, < 1.3.5 (Rails 7.0 compatibility)

### ⚠️ Beta Notice

This is a **beta release**. The core functionality is stable and tested, but:
- API may change before v1.0.0
- Not all features have extensive real-world testing
- Feedback and contributions welcome!

### 🚀 What's Next

Future releases will focus on:
- Additional test coverage for Phases 2-5
- Performance optimizations
- Additional integration options
- User feedback and bug fixes

### 🙏 Acknowledgments

Thanks to the Rails community for the excellent tools and libraries that made this gem possible.

---

## Version History

- **0.1.0** (2024-12-24) - Initial beta release with complete feature set

[Unreleased]: https://github.com/AnjanJ/rails_error_dashboard/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/AnjanJ/rails_error_dashboard/releases/tag/v0.1.0
