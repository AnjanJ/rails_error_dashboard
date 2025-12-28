# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.5] - 2025-12-28

### ✨ Features

#### Configuration Dashboard
- **Settings Page** - New comprehensive configuration viewer
  - Read-only view of all 40+ configuration options at `/error_dashboard/settings`
  - Displays enabled/disabled status with color-coded badges (green/gray)
  - Shows all notification channels (Slack, Email, Discord, PagerDuty, Webhooks) with status
  - Lists all advanced analytics features with enable/disable state
  - Displays active plugins with name, version, description, and status
  - Shows performance settings (async logging, separate database, sampling rate)
  - Includes enhanced metrics (app version, git SHA, total users)
  - Helpful information panel linking to initializer file for configuration changes

#### Navigation Improvements
- **Deep Links from Analytics Page**
  - Platform chart now includes quick links to filter errors by platform (iOS, Android, Web, API)
  - Top 10 Affected Users table adds "View Errors" button for each user (filters by email)
  - MTTR by Severity table adds "View" button to filter errors by severity level
  - Error Type breakdown table maintains existing "View Errors" functionality

- **Deep Links from Platform Comparison Page**
  - Each platform health card now includes "View {Platform} Errors" button in footer
  - Direct navigation from platform metrics to filtered error list

- **Deep Links from Correlation Page**
  - Problematic Releases table adds "View" button to filter errors by version
  - Multi-Error Users table adds "View" button to filter errors by user email

- **Enhanced Quick Filters in Sidebar**
  - Added "Critical" filter (filters by critical severity with danger icon)
  - Added "High Priority" filter (filters by high priority with warning icon)
  - Maintains existing filters: Unresolved, iOS Errors, Android Errors
  - Color-coded icons for better visual hierarchy and quick identification

### 🎨 UI/UX Enhancements

- **Application Branding**
  - Navbar now displays Rails application name dynamically
  - Format: "{AppName} | Error Dashboard" on desktop
  - Responsive design: Shows only app name on mobile, full branding on desktop
  - Page title updated to include app name: "{AppName} - Error Dashboard"

- **Settings Navigation**
  - Added "Settings" link to main sidebar navigation
  - Accessible from all dashboard pages
  - Gear icon for easy identification

### 📚 Documentation

- All 16 features now have clear, documented navigation paths
- Settings page provides visibility into gem configuration without code inspection
- Improved feature discoverability through enhanced quick filters

### 🔧 Technical Details

This release focuses on improving user experience through better navigation and configuration visibility. No breaking changes or API modifications.

**Key Improvements:**
- Users can now see all enabled features without inspecting initializer file
- Every analytics view provides direct navigation to filtered error lists
- Quick filters make common error queries one-click accessible
- Application branding improves multi-tenant dashboard identification

**Upgrade Instructions:**
```ruby
# Gemfile
gem "rails_error_dashboard", "~> 0.1.5"
```

Then run:
```bash
bundle update rails_error_dashboard
```

No migrations or configuration changes required.

**New Routes:**
- `GET /error_dashboard/settings` - Configuration dashboard (read-only)

## [0.1.4] - 2025-12-27

### 🐛 Bug Fixes

#### Test Suite Stability
- **Flaky Test Elimination** - Fixed all test order dependencies for 100% reliability
  - Added `async_logging = false` configuration to 4 spec files to prevent state bleeding
  - Fixed pattern detector test that failed on weekends by freezing time to Wednesday
  - Fixed schema version incompatibility (Rails 8.0 schema in Rails 7.0 tests)
  - All 889 RSpec examples now pass consistently across all random seeds
  - Verified with seeds: 1, 42, 777, 3333, 5000, 12345, 42210, 58372, 99999

#### Developer Experience
- **Lefthook Optimization** - Dramatically improved pre-commit hook performance
  - Reduced execution time from 8-10+ seconds to ~1 second
  - Changed from pre-push to pre-commit for faster feedback
  - Implemented glob patterns to run only on staged files
  - Fixed infinite loop bug in pre-push hook that spawned hundreds of processes
  - Added manual commands: `lefthook run qa`, `quick`, `fix`, `full`

### ✨ Features

#### Uninstall System
- **Comprehensive Uninstall Generator** - Full-featured uninstall automation
  - Interactive generator with component detection and confirmation prompts
  - Automated removal: initializer, routes, migrations, database tables
  - Manual instructions provided when automation not possible
  - Safety features: double confirmation for data deletion, `--keep-data` flag
  - Rake task `rails_error_dashboard:db:drop` for manual table cleanup
  - Complete documentation in `docs/UNINSTALL.md` with troubleshooting guide
  - Test coverage for all uninstall components

### 🧹 Maintenance

- **CI/CD Improvements**
  - All GitHub Actions workflows passing across 15 Ruby/Rails combinations
  - Ruby 3.2, 3.3, 3.4 × Rails 7.0, 7.1, 7.2, 8.0, 8.1
  - Zero flaky tests, zero random failures
  - Optimized git hooks for development workflow

### 📚 Documentation

- **Uninstall Guide** - New comprehensive uninstall documentation
  - Step-by-step automated uninstall instructions
  - Manual uninstall procedures for edge cases
  - Troubleshooting section for common issues
  - Verification steps to confirm complete removal
  - Reinstall guide if needed

### 🔧 Technical Details

This patch release focuses on developer experience, test reliability, and providing proper uninstall tooling. No breaking changes or API modifications.

**Upgrade Instructions:**
```ruby
# Gemfile
gem "rails_error_dashboard", "~> 0.1.4"
```

Then run:
```bash
bundle update rails_error_dashboard
```

**New Uninstall Feature:**
```bash
# Interactive uninstall (recommended)
rails generate rails_error_dashboard:uninstall

# Keep data, remove code only
rails generate rails_error_dashboard:uninstall --keep-data

# Non-interactive (use defaults)
rails generate rails_error_dashboard:uninstall --skip-confirmation
```

## [0.1.1] - 2025-12-25

### 🐛 Bug Fixes

#### UI & User Experience
- **Dark Mode Persistence** - Fixed dark mode theme resetting to light on page navigation
  - Theme now applied immediately before page render (no flash of light mode)
  - Dual selector approach (`body.dark-mode` + `html[data-theme="dark"]`)
  - Theme preference preserved across all page loads and form submissions

- **Dark Mode Contrast** - Improved text visibility in dark mode
  - Changed text color from `#9CA3AF` to `#D1D5DB` for better contrast
  - Text now clearly readable against dark backgrounds

- **Error Resolution** - Fixed resolve button not marking errors as resolved
  - Corrected form HTTP method from PATCH to POST to match route definition
  - Resolve action now works correctly with 200 OK response

- **Error Filtering** - Fixed unresolved checkbox and default filter behavior
  - Dashboard now shows only unresolved errors by default (cleaner view)
  - Unresolved checkbox properly toggles between unresolved-only and all errors
  - Added hidden field for proper false value submission

- **User Association** - Fixed crashes when User model not defined in host app
  - Added `respond_to?(:user)` checks before accessing user associations
  - Graceful fallback to user_id display when User model unavailable
  - Error show page no longer crashes on apps without User model

#### Code Quality & CI
- **RuboCop Compliance** - Fixed Style/RedundantReturn violation
  - Removed redundant `return` statement in ErrorsList query object
  - All 132 files now pass lint checks with zero offenses

- **Test Suite Stability** - Updated tests to match new default behavior
  - Fixed 5 failing tests in errors_list_spec.rb
  - Updated expectations to reflect unresolved-only default filtering
  - Enhanced filter logic to handle boolean false, string "false", and string "0"
  - All 847 RSpec examples now passing with 0 failures

#### Dependencies
- **Missing Gem Dependencies** - Added required dependencies for dashboard features
  - Added `turbo-rails` dependency for real-time updates
  - Added `chartkick` dependency for dashboard charts
  - Dashboard now works out-of-the-box without manual dependency installation

### 🧹 Code Cleanup

- **Removed Unused Code**
  - Deleted `DeveloperInsights` query class (278 lines, unused)
  - Deleted `ApplicationRecord` model (5 lines, unused)
  - Removed build artifact `rails_error_dashboard-0.1.0.gem`
  - Cleaner, leaner codebase with zero orphaned files

- **Internal Documentation** - Moved development docs to knowledge base
  - Relocated `docs/internal/` to external knowledge base
  - Repository now contains only public-facing documentation
  - Cleaner repo structure for open source contributors

### ✨ Enhancements

- **Helper Methods** - Added missing severity_color helper
  - Returns Bootstrap color classes for error severity levels
  - Supports critical (danger), high (warning), medium (info), low (secondary)
  - Fixes 500 errors when rendering severity badges

### 🧪 Testing & CI

- **CI Reliability** - Fixed recurring CI failures
  - All RuboCop violations resolved
  - All test suite failures fixed
  - 15 CI matrix combinations now passing consistently
  - Ruby 3.2/3.3/3.4 × Rails 7.0/7.1/7.2/8.0/8.1
  - 847 examples, 0 failures, 0 pending

### 📚 Documentation

- **Installation Testing** - Verified gem installation in test app
  - Tested uninstall → reinstall → migration → dashboard workflow
  - Confirmed all features work correctly in production-like environment
  - Dashboard loads successfully with all charts and real-time updates

### 🔧 Technical Details

This patch release focuses entirely on bug fixes and stability improvements. No breaking changes or new features introduced.

**Upgrade Instructions:**
```ruby
# Gemfile
gem "rails_error_dashboard", "~> 0.1.1"
```

Then run:
```bash
bundle update rails_error_dashboard
```

No migrations or configuration changes required.

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

- **0.1.1** (2025-12-25) - Bug fixes and stability improvements
- **0.1.0** (2024-12-24) - Initial beta release with complete feature set

[Unreleased]: https://github.com/AnjanJ/rails_error_dashboard/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/AnjanJ/rails_error_dashboard/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/AnjanJ/rails_error_dashboard/releases/tag/v0.1.0
