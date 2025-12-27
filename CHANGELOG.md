# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0](https://github.com/AnjanJ/rails_error_dashboard/compare/rails_error_dashboard-v0.1.1...rails_error_dashboard/v0.2.0) (2025-12-27)


### ✨ Features

* add comprehensive uninstall system with automated and manual options ([92ef650](https://github.com/AnjanJ/rails_error_dashboard/commit/92ef6506ad70206ecd403870e4b4344f23fcbcda))
* add Lefthook git hooks for pre-commit/pre-push quality checks ([492d17d](https://github.com/AnjanJ/rails_error_dashboard/commit/492d17df4e73f731e664e8fd6ee4ce34c7f7c1f3))
* add silent-by-default internal logging system ([6b60b56](https://github.com/AnjanJ/rails_error_dashboard/commit/6b60b564b58f081319acbe793e310e6e60494c21))
* add workflow management, improve documentation, and enhance error tracking ([5e2d195](https://github.com/AnjanJ/rails_error_dashboard/commit/5e2d195c3e7cd2582d4f1a9523339b7c8da21ebc))
* enhance error logging with better error handling ([5ee90ec](https://github.com/AnjanJ/rails_error_dashboard/commit/5ee90ec6b47989bc0af4ed24a689db91fb318fe8))


### 🐛 Bug Fixes

* add async_logging=false to log_error_spec.rb to prevent flaky tests ([6ec3129](https://github.com/AnjanJ/rails_error_dashboard/commit/6ec3129b0ba09e62deb7211c8a2767f657fc6a57))
* add explicit config file paths to release-please action ([c23dcd3](https://github.com/AnjanJ/rails_error_dashboard/commit/c23dcd3b9501952bd2bddd213d99b476a68e5c72))
* add missing workflow routes (assign, snooze, add_comment, etc) ([9a9595a](https://github.com/AnjanJ/rails_error_dashboard/commit/9a9595ac030037d54ab01c0aa4cb9621af09ff6d))
* change schema version from 8.0 to 7.0 for Rails 7.0 compatibility ([11595e8](https://github.com/AnjanJ/rails_error_dashboard/commit/11595e81680194df8f3db80b663a3b12b9a723c0))
* dynamic chart colors for light/dark theme compatibility ([1dd1508](https://github.com/AnjanJ/rails_error_dashboard/commit/1dd1508499f441a2266aca6d69757ec2909cef33))
* eliminate all flaky tests by disabling async_logging in synchronous specs ([bd1ea94](https://github.com/AnjanJ/rails_error_dashboard/commit/bd1ea94bdb6bb50a4e4bfa2f4ac6a1c1013f59de))
* flaky pattern detector test - freeze to weekday to avoid weekend detection ([f263aee](https://github.com/AnjanJ/rails_error_dashboard/commit/f263aee193e7bb479b04c64bd0ae947b915b6768))
* improve Chart.js visibility in dark mode ([cf79e3f](https://github.com/AnjanJ/rails_error_dashboard/commit/cf79e3f3b6b07a26d5354e9d24decbe3f04f2a12))
* improve dark mode readability for list group items ([5b681b3](https://github.com/AnjanJ/rails_error_dashboard/commit/5b681b392a6e44d6605eeb162abc9c54e6ab97fe))
* improve filter UX - preserve scroll position and checkbox state ([d030ad4](https://github.com/AnjanJ/rails_error_dashboard/commit/d030ad48f19357924e26b4e5d3486b98e7ef6263))
* improve stat card label visibility in dark mode ([41966ed](https://github.com/AnjanJ/rails_error_dashboard/commit/41966ed62bf76b155207e8961f4e9d2d45e3d821))
* improve text-muted contrast in both light and dark modes ([da4e9e5](https://github.com/AnjanJ/rails_error_dashboard/commit/da4e9e51d227cd26734884ae937ba0c4838b8503))
* populate git_sha and app_version in LogError command ([e645580](https://github.com/AnjanJ/rails_error_dashboard/commit/e645580cc4258c99d6655a3556a73d1a55443cde))
* resolve 30 test failures - logging and database issues ([45e8927](https://github.com/AnjanJ/rails_error_dashboard/commit/45e8927de94b9391416b89b4929b6115440ae032))
* resolve checkbox filter state transition issue ([a96b6a3](https://github.com/AnjanJ/rails_error_dashboard/commit/a96b6a3c1f142eb4514ecb070c5af42d1722ad3a))
* resolve final 8 generator test failures - Thor option parsing ([a87b3aa](https://github.com/AnjanJ/rails_error_dashboard/commit/a87b3aaed66a9dcbfdbce015a28f6849b428b688))
* skip interactive prompts when not running in TTY ([febd9b8](https://github.com/AnjanJ/rails_error_dashboard/commit/febd9b872a660cec917d2c964ba63d07b466a84c))


### 📚 Documentation

* add quick setup guide for automated releases ([0c777b3](https://github.com/AnjanJ/rails_error_dashboard/commit/0c777b30e90118ae2f1562c218933cff06ece4bf))
* fix README formatting and broken links across all documentation ([88b6b26](https://github.com/AnjanJ/rails_error_dashboard/commit/88b6b2621ca22afcfdf9493314f5fd3ceb3708da))


### ♻️ Refactoring

* improve helpers and view components for better theming ([83ed8a0](https://github.com/AnjanJ/rails_error_dashboard/commit/83ed8a00f6bc94497c6d384e04dd97edad6ea1d1))
* move comprehensive checks from pre-push to pre-commit ([54fdb32](https://github.com/AnjanJ/rails_error_dashboard/commit/54fdb32659cf9a49f8554d28d7b185c93efcca2c))
* optimize lefthook to run only changed specs on pre-commit ([a8e7307](https://github.com/AnjanJ/rails_error_dashboard/commit/a8e730744c69c5f8035283766995dbf077e7599c))


### 🧹 Maintenance

* add bootstrap SHA to release-please config ([fb190c9](https://github.com/AnjanJ/rails_error_dashboard/commit/fb190c95de9053ce1b1bf1b323c1cffab89d237f))
* bump version to 0.1.3 ([324ee28](https://github.com/AnjanJ/rails_error_dashboard/commit/324ee28c3f82894bb81a0315776dfe2e002537d5))
* clean up codebase - remove unused files and improve organization ([24bd974](https://github.com/AnjanJ/rails_error_dashboard/commit/24bd974b92a38afa4938d8815da1d37d4e02f46b))
* update gitignore for temporary development files ([60bc51e](https://github.com/AnjanJ/rails_error_dashboard/commit/60bc51e022ce3b845360389e845fe99cde02662b))

## [Unreleased]

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
