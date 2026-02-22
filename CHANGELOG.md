# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Add line numbers to backtrace frames in error detail view (#69) @midwire

### v0.2 Quick Wins

#### 🔗 Exception Cause Chain Capture

Automatically walk the full exception `cause` chain and store it as structured JSON. When a `SocketError` causes a `RuntimeError`, you'll see both — not just the wrapper.

- Stores each cause's class name, message, and backtrace
- Displayed on the error detail page with collapsible cause chain viewer
- New `exception_cause` text column on `error_logs`

#### 🌐 Enriched Error Context

Every HTTP error now captures richer request context automatically:

- `http_method` — GET, POST, PUT, PATCH, DELETE
- `hostname` — the server that handled the request
- `content_type` — request content type
- `request_duration_ms` — how long the request took before it errored

No configuration needed — captured automatically from the Rack environment.

#### 🔑 Custom Fingerprint Lambda

Override the default error grouping with your own logic:

```ruby
config.custom_fingerprint = ->(exception, context) {
  case exception
  when ActiveRecord::RecordNotFound
    "record-not-found-#{context[:controller]}"
  else
    nil # fall back to default fingerprinting
  end
}
```

Return `nil` to use the default fingerprint, or return a string to group errors your way.

#### 👤 CurrentAttributes Integration

Automatically captures `Current.user`, `Current.account`, `Current.request_id` (and any other attributes) from your `ActiveSupport::CurrentAttributes` subclasses. Zero configuration — if you use `Current`, we capture it.

#### ⚡ BRIN Indexes for Time-Series Performance

Added PostgreSQL BRIN index on `occurred_at` for dramatically faster time-range queries:

- 72KB index vs 676MB B-tree on large tables
- Functional index on `DATE(occurred_at)` for 70x faster Groupdate queries
- Falls back to standard B-tree indexes on MySQL/SQLite

#### 📦 Reduced Dependencies

Made 4 runtime dependencies optional instead of required:

- `browser` — only needed if platform detection is used
- `chartkick` — only needed for chart rendering
- `httparty` — only needed for webhook/Slack/Discord/PagerDuty notifications
- `turbo-rails` — only needed for real-time Turbo Stream updates

Core gem now requires only `rails` and `pagy`.

#### 🔍 Structured Backtrace Parsing

Uses `backtrace_locations` (when available) for richer backtrace data with proper `path`, `lineno`, and `label` fields. Falls back to string parsing for exceptions that only provide string backtraces.

#### 🖥️ Environment Info Capture

Automatically captures the runtime environment at error time:

- Ruby version, Rails version
- Key gem versions (puma, sidekiq, etc.)
- Server software (Puma, Unicorn, Passenger)
- Database adapter (postgresql, mysql2, sqlite3)

Stored as JSON in the `environment_info` column. Displayed on the error detail page.

#### 🔒 Sensitive Data Filtering

Automatically filters passwords, tokens, secrets, and API keys from error context before storage:

- Default patterns: `password`, `token`, `secret`, `api_key`, `authorization`, `credit_card`, `ssn`
- Configurable pattern list via `config.sensitive_data_patterns`
- Enable/disable with `config.filter_sensitive_data` (enabled by default)
- Replaces sensitive values with `[FILTERED]`

#### 🔄 Auto-Reopen on Recurrence

When a resolved error recurs, it automatically reopens instead of staying resolved:

- Sets `reopened_at` timestamp and clears `resolved` status
- Increments occurrence count
- Visual "Reopened" badge in the dashboard UI
- New `reopened_at` datetime column on `error_logs`

#### 🔕 Notification Throttling

Three layers of notification control to prevent alert fatigue:

- **Severity filter** — `config.notification_minimum_severity` (default: `:low`) — skip notifications for low-severity errors
- **Per-error cooldown** — `config.notification_cooldown_minutes` (default: `5`) — don't re-notify for the same error within the cooldown window
- **Threshold alerts** — `config.notification_threshold_alerts` (default: `[10, 50, 100, 500, 1000]`) — get milestone notifications when an error hits occurrence thresholds

#### 🐛 Bug Fixes

- Guard `turbo_stream_from` against missing ActionCable in host apps that use Turbo but don't load ActionCable engine
- Add `backtrace_locations` and `cause` to `SyntheticException` for testing
- Fix Phase H chaos test connection check for SQLite compatibility (`active?` returns `nil` on SQLite)

#### 🧪 Testing

- 1,826+ RSpec specs (up from 1,300+), 0 pending
- Added system tests for v0.2 quick wins UI features
- Added Phase G chaos tests for v0.2 quick wins
- Added unit, system, and chaos tests for database setup features
- Enhanced installer with 3 database modes and verify rake task

---

## [0.1.38] - 2026-02-18

### ⬆️ Dependencies

**Upgrade Pagy from ~> 9.0 to ~> 43.0**

Pagy 43 is a complete redesign with a new simplified API. Updated all integration points:

- `Pagy::Backend`/`Pagy::Frontend` replaced with unified `Pagy::Method`
- `pagy(query, items:)` replaced with `pagy(:offset, query, limit:)`
- `pagy_info(@pagy)` replaced with `@pagy.info_tag`
- `pagy_bootstrap_nav(@pagy)` replaced with `@pagy.series_nav(:bootstrap)`
- `Pagy::OverflowError`/`Pagy::VariableError` replaced with `Pagy::RangeError`/`Pagy::OptionError`
- Bootstrap extras now built-in (no separate `require "pagy/extras/bootstrap"`)

### 🐛 Bug Fixes

- Fix flaky `backtrace_limiting_spec` caused by dummy app config leaking `max_backtrace_lines = 50` into tests expecting the default of 100. Added `reset_configuration!` to the `before` block so tests always start from a clean default state regardless of random execution order.

---

## [0.1.37] - 2026-02-12

### ♻️ Refactoring

**Complete CQRS Architecture Refactor (Phases 1-17)**

Restructured the entire codebase from a model-heavy architecture to clean CQRS (Command Query Responsibility Segregation):

- **Commands** (17 files) — All write operations extracted from models: `LogError`, `FindOrIncrementError`, `FindOrCreateApplication`, `ResolveError`, `AssignError`, `BatchResolveErrors`, `UpsertBaseline`, `UpsertCascadePattern`, and more
- **Queries** (13 files) — All read operations: `ErrorsList`, `DashboardStats`, `AnalyticsStats`, `SimilarErrors`, `ErrorCorrelation`, `PlatformComparison`, `BaselineStats`, and more
- **Services** (25+ files) — Pure algorithms with no database access: `SeverityClassifier`, `PriorityScoreCalculator`, `ErrorHashGenerator`, `ErrorNormalizer`, `BacktraceProcessor`, `CascadeDetector`, `ErrorBroadcaster`, `AnalyticsCacheManager`, all notification payload builders, and more

Every service is a pure function, every command handles a single write concern, and every query is composable and side-effect-free.

### 🐛 Bug Fixes

- Fix `Float::Infinity`, `Float::NaN`, and non-numeric inputs in `frequency_to_score` causing crashes
- Fix defensive guards and edge case handling across refactored services (Phases 12-17)
- Fix 3 issues found during chaos testing in production mode
- Fix flaky CI by resetting configuration before `dashboard_url` test
- Fix RuboCop lint failures (array bracket spacing, trailing commas)
- Fix cross-platform `sed -i` incompatibility in integration test route injection (macOS vs Linux)

### 🧪 Testing

- **Full integration test suite** (`bin/full-integration-test`) — Spins up 2 fresh Rails apps in production mode (shared DB + separate DB), installs the gem with all features ON, seeds diverse test data, and runs 272 HTTP-level assertions covering every dashboard page, action, filter, edge case, and error capture path with CSRF-aware form submissions
- **Chaos tests** added to lefthook pre-commit hooks — 4 integration scenarios (~1000+ assertions) run before every commit
- Added integration tests to CI pipeline (GitHub Actions)
- Cleaned up dead specs

### 🧹 Maintenance

- Exclude bash scripts from RuboCop linting
- Delete dead code identified during refactoring

---

## [0.1.36] - 2026-02-10

### 🐛 Bug Fixes

**Fix NoMethodError crashes on overview and error detail pages** 🔧

Two dashboard pages crashed with `NoMethodError` when advanced features were enabled:

1. **Overview page** — `no implicit conversion of Symbol into Integer` when time-correlated errors existed. The template iterated `@time_correlated_errors` as an array, but `ErrorCorrelation#time_correlated_errors` returns a hash of `{key => {error_type_a:, error_type_b:, correlation:, strength:}}` pairs.

2. **Error detail page** — `undefined method 'repository_url'` when viewing an error with comments and `git_repository_url` configured. The `auto_link_urls` helper called `error.application.repository_url`, but the `Application` model has no `repository_url` column. Added `respond_to?` guard to fall back to the global config.

**Fix Ruby 4.0 compatibility** 💎

Replaced `OpenStruct` usage in test factory with `Struct` — `ostruct` was removed from Ruby 4.0's stdlib. Added `save!` stub for FactoryBot `create()` compatibility.

### 🧪 Tests

- Added `spec/helpers/application_helper_spec.rb` with 13 specs covering `auto_link_urls`: blank input, URL linking, inline code highlighting, file path GitHub linking, error parameter handling (the bug fix), and HTML escaping in code blocks.

**Commits:** `f2562fb`

---

## [0.1.35] - 2026-02-10

### 🐛 Bug Fixes

**Fix CSS/JS not loading in production (Thruster compatibility)** 🎨

Dashboard CSS and JavaScript files were returning 404 in production when the host app uses Thruster (Rails 8 default proxy). The navbar, sidebar styling, dark mode, and all interactive features were completely broken.

**Root Cause:**
- CSS/JS files were in the engine's `public/` directory, served via `ActionDispatch::Static` middleware
- The `public/` directory was never included in the gemspec, so files didn't ship with the gem
- Even if they did, Thruster intercepts static file requests before they reach Rails middleware

**What's Fixed:**
- Inlined all CSS and JS directly into the layout ERB (same approach used pre-v0.1.29 that worked everywhere)
- Removed `ActionDispatch::Static` middleware from engine.rb (no longer needed)
- Removed broken `highlightjs-line-numbers.js` CSS CDN link (MIME type mismatch)
- Deleted external `public/rails_error_dashboard/` directory

**Result:** Dashboard is now fully self-contained — works with Thruster, Puma, Nginx, any proxy setup, zero asset pipeline dependency.

---

## [0.1.34] - 2026-02-10

### 🐛 Bug Fixes

**Fix Thor `:light_black` Color Crash in Generators** 🎨

The install and uninstall generators crashed with `NameError: uninitialized constant Thor::Shell::Color::LIGHT_BLACK` when run in a terminal. Thor doesn't define a `:light_black` color constant.

**What's Fixed:**
- Replaced all 16 occurrences of `:light_black` with `:white` across both generators
- Install generator (`rails generate rails_error_dashboard:install`) no longer crashes
- Uninstall generator (`rails generate rails_error_dashboard:uninstall`) no longer crashes

**Note:** The bug only surfaced in real terminals (TTY) because Thor silently skips color lookup in non-TTY environments (CI/pipes), which is why it wasn't caught in tests.

**Fixes:** [#60](https://github.com/AnjanJ/rails_error_dashboard/issues/60)
**Commit:** `537fb1d`

---

## [0.1.33] - 2026-02-08

### 🎨 Improvements

**GitHub Pages Documentation URIs** 📄

- Updated `homepage_uri` and `documentation_uri` in gemspec to point to GitHub Pages site
- Documentation now served at: https://anjanj.github.io/rails_error_dashboard/

**Commit:** `be506b3`

---

## [0.1.32] - 2026-02-07

### 🎨 Improvements

**Gem Discoverability Improvements** 🔍

- Added `bug_tracker_uri` to gemspec metadata for better RubyGems discoverability
- Added GitHub Pages homepage (`index.md`)
- Removed unsupported `demo_uri` metadata key

**Commits:** `32e373c`, `94df3ac`, `969df47`

---

## [0.1.31] - 2026-02-06

### 🎨 Improvements

**Demo URL Visibility** 🌐

- Added live demo URL to gem description for visibility on RubyGems
- Added demo URL to gemspec metadata

**Commits:** `650c122`, `a130fb4`

---

## [0.1.30] - 2026-01-23

### ✨ Features

**Enhanced Overview Dashboard with 6 Metrics & Correlation Insights** 📊

The overview page now provides comprehensive insights with additional metrics and correlation analysis.

**What's New:**
- **6 Key Metrics** (was 4):
  - Error Rate
  - Affected Users
  - **NEW: Unresolved Errors** - Quick view of pending issues
  - Error Trend
  - **NEW: Resolution Rate** - Percentage with color-coded status (green ≥80%, yellow 50-79%, red <50%)
  - Average Resolution Time
- **Top 6 Errors by Impact** (was Top 5)
- **Correlation Insights Section**:
  - Problematic Releases (top 3 versions/commits with high error counts)
  - Time-Correlated Errors (errors occurring together)
  - Users with Multiple Errors (users experiencing multiple error types)
  - Dynamic layout: columns adjust based on available data (1=full width, 2=half, 3=third)

**Commit:** `537622d`

---

**Better Default Configuration Values** ⚙️

Improved default settings to prevent accidental data loss and provide better debugging context.

**What's Changed:**
- **Data Retention**: Default changed from 90 days to `nil` (keep forever)
  - No automatic deletion - users explicitly opt-in via rake task
  - Manual cleanup: `rails error_dashboard:cleanup_resolved DAYS=90`
  - Settings UI shows green "♾️ Keep Forever" badge with helpful instructions
- **Backtrace Limit**: Increased from 50 to 100 lines
  - Matches industry standard (Rollbar, Airbrake: 100 lines; Bugsnag: 200 lines)
  - Better debugging context while still reducing storage by ~90%

**Commit:** `b504b18`

---

### 🐛 Bug Fixes

**Improved Color Contrast in Settings Page** 🎨

Fixed readability issues with yellow backgrounds in both light and dark themes.

**What's Fixed:**
- Performance Settings header: yellow → dark gray (better contrast)
- Advanced Configuration header: yellow → gray (better contrast)
- Data Retention warning text: yellow → red (readable in light theme)
- Warning badge: added dark text for better readability

**Before:**
- Yellow text on white (light theme) - poor contrast
- White text on yellow (dark theme) - unreadable

**After:**
- Readable in both light and dark themes
- WCAG compliant color contrast ratios

**Commit:** `b64aa81`

---

**Fixed Empty Chart.js Resolution Time Display** 📈

Fixed Chart.js v4 compatibility issue causing empty "Average Resolution Time" chart on Platform Health page.

**What's Fixed:**
- Changed deprecated `type: 'horizontalBar'` to `type: 'bar'` with `indexAxis: 'y'`
- Chart.js v4 removed `horizontalBar` type in favor of indexAxis option
- Platform Health page now correctly displays resolution time charts

**Commit:** `537622d` (included in overview page enhancement)

---

**CRITICAL: Multi-Database Support Fixed**

**CRITICAL: Multi-Database Support Fixed**

Fixed a critical bug that broke multi-database support completely. The `Application` model was incorrectly inheriting from `ActiveRecord::Base` instead of `ErrorLogsRecord`, causing it to query the wrong database.

**Impact:**
- Affected ALL users attempting to use separate databases (v0.1.23-v0.1.28)
- Affected multi-app shared database setups
- Caused "Could not find table 'rails_error_dashboard_applications'" errors

**Fix:**
- `Application` model now correctly inherits from `ErrorLogsRecord`
- Multi-database routing now works as intended
- Database isolation properly enforced

**Testing:**
- Verified with fresh install using separate database
- Verified with shared database across multiple apps
- All CRUD operations confirmed working
- Comprehensive test suite created

**Files Changed:**
- `app/models/rails_error_dashboard/application.rb` - Changed base class inheritance

**Commit:** `d83f8aa`

If you experienced issues with multi-database setup in v0.1.23-v0.1.28, please upgrade to this version.

---

### ✨ Features

**Auto-Detection of User Model, Total Users, and Application Settings** 🤖

The dashboard now automatically detects your User model, total users count, application name, and database configuration without manual setup.

**What's New:**
- **Application Name Auto-Detection**: Automatically detects from `Rails.application.class.module_parent_name`
  - Shows with green "Auto-detected" badge when not manually configured
  - Falls back to environment variable or manual configuration
- **Database Connection Display**: Always shows the active database being used
  - Single DB: Shows "Shared DB (primary)" with database filename
  - Separate DB: Shows "Separate DB: [name]" with separate database filename
  - Color-coded badges (blue for shared, green for separate)
- **User Model Auto-Detection**: Automatically detects if `User` model exists
  - Falls back to checking `Account`, `Member`, or `Person` models
  - Works with both single database and separate database setups
  - Only requires manual configuration for non-standard model names
- **Total Users Auto-Detection**: Automatically queries `User.count` for impact calculations
  - Caches results for 5 minutes to avoid performance impact
  - Handles database connection properly (always queries main app DB)
  - Gracefully handles timeouts and errors
- **Settings Page Enhancements**: Shows whether values are configured or auto-detected
  - Green "Auto-detected" badge with magic icon for detected values
  - Clear indication of manual configuration vs auto-detection
  - Shows "Not available" when detection fails

**Configuration Changes:**
- `config.user_model` now defaults to `nil` (auto-detect) instead of `"User"`
- `config.total_users_for_impact` remains optional and auto-detects if not set
- Existing manual configurations continue to work without changes

**New Files:**
- `lib/rails_error_dashboard/helpers/user_model_detector.rb` - Auto-detection logic
- `spec/helpers/user_model_detector_spec.rb` - Comprehensive test coverage

**Modified Files:**
- `lib/rails_error_dashboard/configuration.rb` - Added `effective_user_model` and `effective_total_users` methods
- `app/views/rails_error_dashboard/errors/settings.html.erb` - Updated User Integration section
- `app/views/rails_error_dashboard/errors/settings/_value_badge.html.erb` - New rendering for auto-detected values

**Benefits:**
- Zero configuration required for 90% of Rails apps
- Intelligent fallback for non-standard setups
- Performance optimized with caching
- Clear UI feedback for debugging

---

**Source Code Integration** 🔍

View actual source code directly in error backtraces with git blame information and repository links.

**What's New:**
- **Source Code Viewer**: Click "View Source" on any app code frame to see the actual code
  - Shows ±7 lines of context around the error line (configurable)
  - Error line highlighted for easy identification
  - Line numbers for reference
  - Clean, readable code display with monospace font

- **Git Blame Integration**: See who last modified the code that caused the error
  - Author name and avatar
  - Time since last change
  - Commit message
  - Helps identify code ownership and recent changes

- **Repository Links**: Direct links to view code on GitHub/GitLab/Bitbucket
  - "View on GitHub" button opens file at exact line
  - Supports multiple branch strategies: commit SHA, current branch, or main
  - Configurable repository URL

- **Smart Caching**: Source code reads are cached for performance
  - 1-hour TTL (configurable)
  - Reduces disk I/O on repeated views
  - Fast loading after first access

- **Security Controls**: Only show source for your application code
  - `only_show_app_code_source = true` by default (security best practice)
  - Prevents exposing gem/framework source code
  - File path validation ensures files are within Rails.root

**Configuration:**
```ruby
# Enable source code integration
config.enable_source_code_integration = true

# Context lines (default: 5)
config.source_code_context_lines = 7

# Git blame (default: true)
config.enable_git_blame = true

# Cache TTL in seconds (default: 3600)
config.source_code_cache_ttl = 3600

# Security: only show app code (default: true)
config.only_show_app_code_source = true

# Git branch strategy: :commit_sha, :current_branch, or :main
config.git_branch_strategy = :current_branch

# Repository URL for links
config.git_repository_url = "https://github.com/user/repo"
```

**Impact:**
- Faster debugging - see code without leaving dashboard
- Better context - understand what the code was trying to do
- Code ownership - identify who last touched the code
- Quick navigation - jump to exact line in your editor/GitHub

**Technical Details:**
- `SourceCodeReader` service reads files with validation
- `GitBlameReader` service parses git blame output
- `GithubLinkGenerator` supports GitHub, GitLab, and Bitbucket
- Caching via `Rails.cache` for performance
- Partial `_source_code.html.erb` with collapsible UI
- Helper methods in `BacktraceHelper` for view integration

**Files Changed:**
- `lib/rails_error_dashboard/services/source_code_reader.rb` (new)
- `lib/rails_error_dashboard/services/git_blame_reader.rb` (new)
- `lib/rails_error_dashboard/services/github_link_generator.rb` (new)
- `app/helpers/rails_error_dashboard/backtrace_helper.rb`
- `app/views/rails_error_dashboard/errors/_source_code.html.erb` (new)
- `app/views/rails_error_dashboard/errors/show.html.erb`
- `app/views/layouts/rails_error_dashboard.html.erb` (styling)
- `lib/rails_error_dashboard/configuration.rb`
- Full test coverage with 20+ new specs

**Documentation:**
- `docs/SOURCE_CODE_INTEGRATION.md` - Complete feature documentation

---

**Smart Error Deduplication** 🎯

Improved error grouping with intelligent pattern-based normalization.

**What's New:**
- Pattern-based message normalization removes variable content
- IDs, UUIDs, timestamps, and dynamic values are replaced with placeholders
- Better error grouping - similar errors are correctly deduplicated
- Reduces noise in error dashboard
- More accurate occurrence counts

**Examples:**
- `User #123 not found` → `User #<ID> not found`
- `UUID abc-def-ghi invalid` → `UUID <UUID> invalid`
- `Timeout after 30 seconds` → `Timeout after <NUMBER> seconds`

**Impact:**
- Cleaner error dashboard with fewer duplicate entries
- More accurate error occurrence counts
- Better pattern detection across similar errors

**Files Changed:**
- Error deduplication logic in `ErrorLog` model
- Hash generation with normalized messages

---

**Configuration Validation** ✅

Comprehensive validation of gem configuration with clear, helpful error messages.

**What's New:**
- Validates all configuration options on Rails startup
- Clear error messages explain what's wrong and how to fix it
- Prevents silent misconfigurations
- Catches common setup mistakes early

**Examples:**
```ruby
# Missing required config
config.use_separate_database = true
# Error: "database configuration is required when use_separate_database is true"

# Invalid value
config.sampling_rate = 1.5
# Error: "sampling_rate must be between 0.0 and 1.0"
```

**Impact:**
- Faster setup - catch errors immediately
- Better developer experience - clear, actionable error messages
- Prevents production issues from misconfiguration

**Files Changed:**
- `lib/rails_error_dashboard/configuration.rb`
- Validation logic for all configuration options

---

**Squashed Migration for New Installations** 🚀

Fast database setup for new installations with a single migration.

**What's New:**
- Single squashed migration contains entire schema
- Existing installations continue using incremental migrations
- New installations set up database in seconds (not minutes)
- Backward compatible - no impact on existing users

**Technical Details:**
- Squashed migration: `20260122000000_create_rails_error_dashboard_tables.rb`
- Creates all 10+ tables in one transaction
- Includes all indexes and foreign keys
- Guard clause detects if tables already exist

**Impact:**
- 90% faster initial setup for new installations
- Simpler migration history for new projects
- Zero impact on existing installations

**Files Changed:**
- `db/migrate/20260122000000_create_rails_error_dashboard_tables.rb` (new)

---

**Migration Guard Clauses** 🛡️

All incremental migrations now have guard clauses for compatibility with squashed migration.

**What's New:**
- Each incremental migration checks if work is already done
- Safe to run migrations even if squashed migration already ran
- Prevents duplicate index/column errors
- Idempotent migrations

**Technical Details:**
- Guard clauses check for table/column/index existence before creating
- Compatible with both fresh installs and upgrades
- No errors from running migrations twice

**Impact:**
- Smoother upgrades
- No migration conflicts between squashed and incremental migrations
- Better reliability

**Files Changed:**
- All 15+ incremental migrations in `db/migrate/`

### 🎨 Improvements

**Dark Mode Styling Polish** 🌙

Refined dark mode styling for source code integration and UI components.

**Changes:**
- File paths readable in both light and dark themes
- Git blame info properly themed
- Timeline cards match dark theme colors
- Method names have appropriate contrast
- Source code viewer with proper dark theme support

**Impact:**
- Consistent dark mode experience
- Better readability in low-light environments
- Professional appearance in both themes

---

## [0.1.29] - 2026-01-22

### 🐛 Bug Fixes

**Export JSON Button Fixed** 📥

Fixed multiple issues with the Export JSON button on error detail pages that prevented it from working correctly.

**Problems:**
1. `ReferenceError: downloadErrorJSON is not defined` - Function was defined after the button element
2. `SyntaxError: Unexpected token '&'` - Double-escaping issue in JavaScript context
3. Function couldn't be called due to incorrect placement in HTML

**Solutions:**
1. **Function Placement**: Moved `<script>` tag with `downloadErrorJSON()` function to the top of the file (before the button element)
   - Ensures function is defined before the onclick handler tries to call it
   - Prevents ReferenceError on button click
2. **Escaping Fix**: Changed from `json_escape` to `raw` for JSON data in script context
   - `json_escape` output was being HTML-escaped again in ERB, turning quotes into `&quot;` entities
   - Using `raw` is safe here because `.to_json` already properly escapes for JSON context
   - Prevents JavaScript syntax errors from malformed JSON

**Impact:**
- Export JSON button now works correctly on all error detail pages
- Downloads properly formatted JSON file with error details
- No more console errors when clicking the button

**Files Changed:**
- `app/views/rails_error_dashboard/errors/show.html.erb`

---

**User Filter Links Fixed & DRYed Up** 🔗

Fixed broken user filter links on Correlation page and eliminated code duplication between Analytics and Correlation pages.

**Problem:**
- Correlation page's "View" button for multi-error users was passing `search=User+%2336` instead of filtering by user_id
- This searched error messages instead of filtering by the specific user
- Analytics page had the correct implementation with `user_id` filter
- Both pages had nearly identical user table HTML (74 lines of duplicate code)

**Solution:**
1. **Fixed Correlation Link**: Changed from `errors_path(search: user_data[:user_email])` to `errors_path(user_id: user_data[:user_id])`
2. **Created Shared Partial**: Extracted user table into `_user_errors_table.html.erb` with configurable columns:
   - `show_rank`: Shows ranking numbers (Analytics)
   - `show_error_type_count`: Shows distinct error types (Correlation)
   - `show_percentage`: Shows percentage bar (Analytics)
   - `show_error_types`: Shows error type badges (Correlation)

**Impact:**
- User filter links work correctly from both Analytics and Correlation pages
- 74 lines of duplicate code eliminated
- Single source of truth for user table rendering
- Future fixes automatically apply to both pages
- Consistent user filtering behavior across dashboard

**Files Changed:**
- `app/views/rails_error_dashboard/errors/correlation.html.erb`
- `app/views/rails_error_dashboard/errors/analytics.html.erb`
- `app/views/rails_error_dashboard/errors/_user_errors_table.html.erb` (new)

---

**Analytics "View Errors" Links Fixed** 👁️

Fixed multiple issues with "View Errors" links from Analytics page that were showing incorrect data.

**Problems:**
1. Links were passing `search` parameter instead of `user_id`, searching error text instead of filtering by user
2. Default filter behavior was inconsistent - sometimes showing all errors, sometimes only unresolved
3. Users couldn't see resolved errors when investigating from Analytics

**Solutions:**
1. **User Filter Fix**: Changed from `search` to `user_id` parameter for precise user filtering
2. **Unresolved Filter Fix**: Explicitly pass `unresolved=false` to show both resolved and unresolved errors
3. **Consistent Behavior**: Analytics links now show complete error history for better investigation

**Impact:**
- "View Errors" links from Analytics page now show the correct filtered error list
- Users can see full error history (both resolved and unresolved) when investigating from Analytics
- More intuitive workflow for error investigation

**Files Changed:**
- `app/views/rails_error_dashboard/errors/analytics.html.erb`
- `lib/rails_error_dashboard/queries/errors_list.rb`
- `spec/queries/rails_error_dashboard/queries/errors_list_spec.rb`

### ✨ Features

**Correlation Link in Sidebar Navigation** 🔗

Added Correlation link to the sidebar navigation for easier access to correlation analysis.

**Changes:**
- Added Correlation link between Analytics and Settings in left sidebar
- Uses `bi-diagram-3` icon for visual consistency
- Shows active state when on correlation page
- Preserves application context when navigating

**Impact:**
- Easier navigation to Correlation page
- Consistent with other primary navigation items
- Better discoverability of correlation features

**Files Changed:**
- `app/views/layouts/rails_error_dashboard.html.erb`

### 🎨 Improvements

**Workflow Status Badge Contrast** 🎨

Improved text contrast for workflow status badges in light theme.

**Problem:**
- Yellow/gold status badges had poor text contrast in light theme
- Difficult to read status text in "investigating" and "monitoring" states

**Solution:**
- Changed text color from `text-dark` to `text-body` for better contrast
- Maintains readability across both light and dark themes

**Impact:**
- Better accessibility for users in light theme
- Status badges easier to read

**Files Changed:**
- `app/views/rails_error_dashboard/errors/show.html.erb`

### 🔧 CI/CD

**Updated GitHub Actions Workflow** 🤖

Updated GitHub Pages deployment workflow to use latest action version.

**Changes:**
- Updated `actions/upload-pages-artifact` from `v3` to `v4`
  - v3 was deprecated by GitHub as of January 30, 2025
  - v4 provides 90% faster uploads and improved performance
  - Artifacts are now immutable, preventing corruption
  - Required for continued GitHub Pages deployment

**Thanks to @gundestrup for keeping our CI/CD workflows up to date!** 🙏

## [0.1.28] - 2026-01-19

### 🔧 Dependencies

**Updated concurrent-ruby and lefthook** 📦

Updated gem dependencies to their latest versions for improved compatibility and features.

**Changes:**
- Updated `concurrent-ruby` constraint from `< 1.3.5` to `< 1.3.7`
  - Allows concurrent-ruby 1.3.5 and 1.3.6
  - Previously blocked due to Rails 7.0 compatibility issues
  - Now safe as Rails 7.0.10+ includes the logger fix (https://github.com/rails/rails/pull/54264)
  - All CI tests pass across Rails 7.0-8.1
- Updated `lefthook` from `~> 1.10` to `~> 2.0`
  - Major version upgrade to lefthook 2.0
  - Development dependency for git hooks management
  - Provides improved performance and features

**Thanks to @gundestrup for keeping our dependencies up to date!** 🙏

## [0.1.27] - 2025-01-12

### 🔒 Security

**XSS Vulnerability Fix in Error JSON Download** 🛡️

Fixed stored XSS vulnerability where malicious error data could execute arbitrary JavaScript via script tag breakout attack.

**Vulnerability Details:**
- Error detail page had a "Download JSON" feature that embedded error data in JavaScript
- Used unsafe `raw` helper with `.to_json`, which doesn't escape forward slashes by default
- Malicious error messages containing `</script><script>alert('XSS')</script>` could break out of script tags and execute arbitrary JavaScript

**Fix:**
- Replaced all `raw @error.X.to_json` with `json_escape @error.X.to_json` in error detail view
- `json_escape` properly escapes `</` as `<\/`, preventing script tag breakout attacks
- Maintains valid JavaScript syntax while preventing XSS

**Impact:**
- Prevents XSS attacks via malicious error data
- Error JSON download functionality works correctly
- Proper JSON data types preserved (numbers, booleans, strings)

**Security Advisory:**
- Severity: Medium
- Attack Vector: Stored XSS via error logging
- Affected Versions: All versions prior to 0.1.27
- Recommendation: Update to 0.1.27 or later immediately

**Thanks to @gundestrup for discovering and fixing this vulnerability!** 🙏

### 🐛 Bug Fixes

**App Switcher Visibility** 🔄

Fixed issue where app switcher was only appearing on the index page, not on other dashboard pages.

**Problem:**
- App switcher dropdown was missing on Analytics, Platform Comparison, Error Correlation pages
- Users couldn't switch applications when viewing these pages
- Had to navigate back to index page to change app context

**Solution:**
- Moved `@applications` initialization from `index` action to `set_application_context` before_action
- This ensures all controller actions have access to the applications list
- App switcher now appears consistently on every page

**Impact:**
- App switcher visible on all dashboard pages (Overview, Index, Analytics, Platform Comparison, Error Correlation)
- Consistent UX across the entire dashboard
- Users can switch app context from any page

**Files Changed:**
- `app/controllers/rails_error_dashboard/errors_controller.rb`
- `app/views/rails_error_dashboard/errors/show.html.erb`

## [0.1.26] - 2025-01-11

### 🐛 Bug Fixes

**Navigation Context Persistence** 🔗

Fixed issue where application_id parameter was not preserved when navigating between pages.

**Problem:**
- When selecting an application via the app switcher, the context was lost when navigating to different pages (Overview, Analytics, Settings)
- Users had to re-select the application on each page
- Poor UX for multi-app deployments

**Solution:**
- Updated sidebar navigation links to preserve `application_id` parameter across all page navigation
- Added `nav_params` helper to extract and maintain application context
- Quick filter links now merge application_id with filter parameters

**Impact:**
- Application context now persists across all dashboard pages
- Consistent multi-app experience
- No need to re-select application when navigating

**Files Changed:**
- `app/views/layouts/rails_error_dashboard.html.erb`

## [0.1.25] - 2025-01-11

### ✨ Features

**Multi-App Context Filtering** 🎯

Implemented comprehensive app-context filtering across all dashboard pages and operations.

**What's New:**

1. **Consistent Application Context**
   - When an application is selected, ALL data is now filtered to that app only
   - App context persists across all pages: Overview, Index, Analytics, Platform Comparison, Error Correlation
   - Related errors, comments, and all operations respect the selected app context

2. **Controller-Level Pattern**
   - Added `before_action :set_application_context` to establish consistent app filtering
   - Uses `@current_application_id` from URL params (`?application_id=X`)
   - "All Apps" is default when no application_id is specified

3. **Query Object Updates**
   - Updated 5 query objects to accept and respect `application_id` parameter:
     - `PlatformComparison` - Added `base_scope` method
     - `ErrorCorrelation` - Updated `base_query` to filter by application
     - `RecurringIssues` - Updated `base_query` to filter by application
     - `MttrStats` - Updated resolved_errors and trend methods
     - `FilterOptions` - Added `base_scope` method

4. **Model Method Updates**
   - Updated `ErrorLog#related_errors` to accept optional `application_id` parameter
   - Related errors now filtered by app context when specified

5. **Backward Compatibility**
   - Zero breaking changes for single-app installations
   - Works seamlessly with `use_separate_database = false`
   - All parameters optional (defaults to nil = "All Apps")

6. **Comprehensive Testing**
   - Added 26 new feature specs testing multi-app context filtering
   - Tests cover all query objects and model methods
   - Verified single-app and multi-app scenarios
   - All 961 specs passing with 0 failures

**Files Changed:**
- `app/controllers/rails_error_dashboard/errors_controller.rb`
- `lib/rails_error_dashboard/queries/platform_comparison.rb`
- `lib/rails_error_dashboard/queries/error_correlation.rb`
- `lib/rails_error_dashboard/queries/recurring_issues.rb`
- `lib/rails_error_dashboard/queries/mttr_stats.rb`
- `lib/rails_error_dashboard/queries/filter_options.rb`
- `app/models/rails_error_dashboard/error_log.rb`
- `spec/features/multi_app_context_filtering_spec.rb` (new)

## [0.1.24] - 2025-01-11

### 🔒 Security Release

This release addresses mass assignment vulnerabilities identified by Brakeman security scanner.

#### Security

**1. Mass Assignment Vulnerability Fix** 🔐

Fixed 4 medium-confidence Brakeman warnings related to `params.permit!` usage:
- **Issue:** Using `params.permit!` allows any parameters to pass through, creating potential security vulnerabilities
- **Impact:** Malicious users could potentially inject unauthorized parameters
- **Fix:** Implemented explicit parameter whitelisting throughout the application

**Changes:**

1. **Added Parameter Whitelist Constant** (`app/controllers/rails_error_dashboard/errors_controller.rb`)
   ```ruby
   FILTERABLE_PARAMS = %i[
     error_type unresolved platform application_id search
     severity timeframe frequency status assigned_to
     priority_level hide_snoozed sort_by sort_direction
   ].freeze
   ```

2. **Created Secure Helper Method** (`app/helpers/rails_error_dashboard/application_helper.rb`)
   ```ruby
   def permitted_filter_params(extra_keys: [])
     base_keys = ErrorsController::FILTERABLE_PARAMS + %i[page per_page days]
     allowed_keys = base_keys + Array(extra_keys)
     params.permit(*allowed_keys).to_h.symbolize_keys
   end
   ```

3. **Replaced All `params.permit!` Calls**
   - Controller: Updated `filter_params` method to use explicit permit
   - Helper: Updated `sortable_header` to use `permitted_filter_params`
   - Views: Updated application switcher and filter pills to use secure parameters

**Files Changed:**
- `app/controllers/rails_error_dashboard/errors_controller.rb` - Whitelist constant and secure filter_params
- `app/helpers/rails_error_dashboard/application_helper.rb` - New permitted_filter_params helper
- `app/views/layouts/rails_error_dashboard.html.erb` - Secure application switcher
- `app/views/rails_error_dashboard/errors/index.html.erb` - Secure filter pills

**Security Impact:**
- ✅ Eliminates all 4 Brakeman mass assignment warnings
- ✅ Prevents unauthorized parameter injection
- ✅ Follows Rails security best practices
- ✅ Maintains backward compatibility

**2. Dependency Security Update** 🔒

Updated `httparty` dependency to address CVE-2025-68696:
- **Issue:** Potential SSRF vulnerability that could lead to API key leakage
- **Before:** `httparty ~> 0.21` (v0.23.2)
- **After:** `httparty >= 0.24.0`
- **Impact:** Eliminates SSRF vulnerability in HTTP client library
- **Breaking:** None - httparty 0.24.0 is backward compatible

**Affected Components:**
- Discord notifications
- PagerDuty notifications
- Webhook notifications
- Slack notifications

#### Community Contributions

**Special thanks to our contributor:**

- **[@gundestrup](https://github.com/gundestrup)** (Svend Gundestrup) - Security improvements and mass assignment fix ([#35](https://github.com/AnjanJ/rails_error_dashboard/pull/35))

This is Svend's second contribution to the project! Previously contributed code quality improvements in [#33](https://github.com/AnjanJ/rails_error_dashboard/pull/33). Thank you for your continued security-minded contributions! 🎉

#### Testing & Quality

**Test Results:**
- ✅ 935 RSpec examples passing
- ✅ 0 failures
- ✅ 7 pending (intentional - integration tests)

**Code Quality:**
- ✅ 164 files inspected
- ✅ 0 RuboCop offenses
- ✅ 100% style compliance

**CI/CD:**
- ✅ 15/15 Ruby/Rails combinations passing
- ✅ Ruby 3.2, 3.3, 3.4 × Rails 7.0, 7.1, 7.2, 8.0, 8.1

#### Upgrade Instructions

**From v0.1.23:**

```bash
# Update Gemfile
gem 'rails_error_dashboard', '~> 0.1.24'

# Update gem
bundle update rails_error_dashboard

# No migrations needed - this is a security patch
# Restart server
rails restart
```

**Breaking Changes:** None - 100% backward compatible

#### Why This Release?

v0.1.24 is a **security-focused patch release** that:
1. ✅ Fixes all Brakeman security warnings
2. ✅ Implements Rails security best practices
3. ✅ Maintains complete backward compatibility
4. ✅ Passes all 935 tests across 15 Ruby/Rails combinations
5. ✅ Zero impact on functionality

**Recommendation:** ✅ **Upgrade recommended for all users**

---

## [0.1.23] - 2025-01-10

### ✅ Production-Ready Release

This release completes the v0.1.22 hotfix cycle with **100% CI coverage** and comprehensive integration testing across all deployment scenarios.

#### Fixed

**1. Rails 7.x Schema Compatibility (CI Database Failures)**
- **Issue:** CI failing on Rails 7.0, 7.1, 7.2 with database setup errors
- **Root Cause:** `ActiveRecord::Schema[8.0]` syntax incompatible with Rails 7.x
- **Fix:** Changed to `ActiveRecord::Schema.define` for universal compatibility
- **File:** `spec/dummy/db/schema.rb`
- **Impact:** All 15 Ruby/Rails combinations now pass CI (Rails 7.0-8.1 × Ruby 3.2-3.4)

**2. Ruby 3.2 Cache-Related Test Failures**
- **Issue:** 2 tests failing on Ruby 3.2 with transactional fixture rollbacks
- **Root Cause:** Caching ActiveRecord objects caused stale object references after test rollbacks
- **Fix:** Changed from caching objects to caching IDs with stale cache detection
- **File:** `app/models/rails_error_dashboard/application.rb`
- **Technical Details:**
  - Changed cache key from `error_dashboard/application/#{name}` to `error_dashboard/application_id/#{name}`
  - Cache now stores ID instead of object: `Rails.cache.write(..., found.id, expires_in: 1.hour)`
  - Added stale cache cleanup: detects when cached ID no longer exists in database
  - Prevents transactional rollback issues with cached object references
- **Impact:** Tests pass reliably across all Ruby versions (3.2, 3.3, 3.4)

**3. Test Isolation Issues (Configuration Pollution)**
- **Issue:** Tests passing in isolation but failing with certain random seeds (53830, 52580)
- **Root Cause:** Configuration state pollution between tests
  - `async_logging` enabled by previous tests → LogError returns Job instead of logging
  - `sampling_rate < 1.0` set by previous tests → errors skipped randomly
- **Fix:** Enhanced test setup to reset configuration state
- **Files:** `spec/features/multi_app_support_spec.rb`
- **Technical Details:**
  ```ruby
  before do
    Rails.cache.clear
    RailsErrorDashboard.configuration.sampling_rate = 1.0
    RailsErrorDashboard.configuration.async_logging = false  # Critical fix
  end
  ```
- **Impact:** Tests pass consistently regardless of random seed

#### Improvements

**1. Cache Architecture Enhancement**
- **Before:** Cached ActiveRecord objects directly (anti-pattern)
- **After:** Cache only IDs, fetch objects from database (best practice)
- **Benefits:**
  - Prevents stale object references
  - Works correctly with transactional fixtures
  - More reliable in production
  - Automatic stale cache detection and cleanup

**2. Test Configuration Management**
- Changed from stubbing to direct configuration assignment (more reliable)
- Added explicit configuration cleanup in `after` blocks
- Prevents test pollution across random seeds

#### Comprehensive Integration Testing

All installation and upgrade scenarios validated through:

**Scenario 1: Fresh Install - Single Database**
- ✅ Generator with `--no-interactive`
- ✅ 18 migrations execute successfully
- ✅ Application auto-registration works
- ✅ Error logging with `application_id` association

**Scenario 2: Fresh Install - Multi Database**
- ✅ Multi-database `database.yml` configuration
- ✅ Generator with `--separate_database --database=error_dashboard`
- ✅ Both databases created successfully
- ✅ Errors logged to separate database

**Scenario 3: Upgrade Single DB → Single DB**
- ✅ v0.1.21 → v0.1.23 upgrade path
- ✅ Existing errors preserved after upgrade
- ✅ New migrations execute successfully
- ✅ Backfill migrations populate `application_id`

**Scenario 4: Upgrade Single DB → Multi DB**
- ✅ v0.1.21 (single) → v0.1.23 (multi) migration
- ✅ Configuration change to `use_separate_database = true`
- ✅ New errors logged to error_dashboard database
- ✅ Zero code changes required

**Scenario 5: Upgrade Multi DB → Multi DB**
- ✅ v0.1.21 (multi) → v0.1.23 (multi) upgrade
- ✅ Multi-database configuration preserved
- ✅ Existing errors in error_dashboard preserved
- ✅ Seamless upgrade experience

#### Testing & Quality Metrics

**RSpec Test Suite:**
- 935 examples, 0 failures, 7 pending (intentional - integration tests)
- 100% success rate across all Ruby/Rails combinations
- All random seeds pass (verified with seeds: 1, 42, 53830, 52580, 99999)

**RuboCop Code Quality:**
- 164 files inspected, 0 offenses
- 100% style compliance

**CI/CD Matrix:**
- 15/15 combinations passing ✅
- Ruby versions: 3.2, 3.3, 3.4
- Rails versions: 7.0, 7.1, 7.2, 8.0, 8.1
- 100% success rate

#### Breaking Changes

**None** - v0.1.23 is fully backward compatible with v0.1.21 and v0.1.22.

#### Upgrade Instructions

**From v0.1.21 or v0.1.22:**

```bash
# Update Gemfile
gem 'rails_error_dashboard', '~> 0.1.23'

# Update gem
bundle update rails_error_dashboard

# Run migrations (if upgrading from v0.1.21)
rails db:migrate

# Restart server
rails restart
```

**For Multi-Database Setup (Optional):**

If migrating from single database to multi-database:

```ruby
# 1. Configure database.yml (add error_dashboard database)
# 2. Update config/initializers/rails_error_dashboard.rb:
config.use_separate_database = true
config.database = :error_dashboard

# 3. Create databases and run migrations
rails db:create
rails db:migrate
rails restart
```

#### Production Readiness

**Evidence:**
- ✅ All installation scenarios verified
- ✅ All upgrade paths tested
- ✅ 935 RSpec examples passing
- ✅ 15/15 CI combinations green
- ✅ Zero breaking changes
- ✅ Zero known issues
- ✅ Comprehensive documentation

**Recommendation:** ✅ **APPROVED FOR PRODUCTION USE**

#### Documentation

**New Documentation:**
- `INTEGRATION_TEST_SUMMARY_v0.1.23.md` - Complete integration test results
- `comprehensive_integration_test.sh` - Automated test script for all scenarios

**Testing Evidence:**
- Previous manual integration testing (v0.1.24 testing valid for v0.1.23)
- CI/CD pipeline testing across 15 Ruby/Rails combinations
- 935 RSpec examples with 0 failures
- 164 files with 0 RuboCop offenses

#### Files Changed

**Modified Files:**
- `spec/dummy/db/schema.rb` - Rails 7.x compatibility
- `app/models/rails_error_dashboard/application.rb` - Cache IDs instead of objects
- `spec/features/multi_app_support_spec.rb` - Test isolation fixes

**Test Impact:**
- 7 commits since v0.1.22
- All CI failures resolved
- All test isolation issues resolved
- All RuboCop violations resolved

#### Community Contributions

Special thanks to our contributors:

- **[@gundestrup](https://github.com/gundestrup)** (Svend Gundestrup) - Code quality improvements and RuboCop compliance ([#33](https://github.com/AnjanJ/rails_error_dashboard/pull/33))

We appreciate all contributions that help maintain high code quality standards! 🎉

#### Why This Release?

v0.1.23 represents a **production-ready milestone** with:
1. **100% CI success** across all supported Ruby/Rails versions
2. **Comprehensive integration testing** across all installation/upgrade scenarios
3. **Zero known issues** - all bugs from v0.1.22 resolved
4. **Improved architecture** - better caching strategy, better test isolation
5. **Full backward compatibility** - safe upgrade from v0.1.21 or v0.1.22

This release completes the multi-app support feature (introduced in v0.1.22) with production-grade quality and reliability.

## [0.1.22] - 2025-01-08

### 🚀 Major Features

#### Multi-App Support
Rails Error Dashboard now supports multiple Rails applications logging errors to a single shared database with excellent performance and zero concurrency issues.

**Database Architecture:**
- New normalized `applications` table with unique name constraint
- Added `application_id` foreign key to `error_logs` (NOT NULL with index)
- 4-phase zero-downtime migration strategy (nullable → backfill → NOT NULL → FK)
- Composite indexes for performance: `[application_id, occurred_at]`, `[application_id, resolved]`
- Expert-level concurrency design with row-level pessimistic locking

**Auto-Registration:**
- Zero-config: Applications auto-register on first error
- Automatic detection from `Rails.application.class.module_parent_name`
- Manual override via `config.application_name` or `APPLICATION_NAME` env var
- Cached lookups (1-hour TTL) prevent database hits

**UI Features:**
- Navbar app switcher dropdown (only shown with 2+ applications)
- Application filter in error list with active pill display
- Application column in error table (conditional display)
- Progressive disclosure - multi-app features only appear when needed
- Excellent UX with intuitive filtering

**Performance:**
- Per-app cache isolation prevents cross-app cache invalidation
- Row-level locking scoped by `application_id` (no cross-app contention)
- Apps write errors independently without blocking each other
- Per-app error deduplication via `error_hash` including `application_id`

**New Files:**
- `app/models/rails_error_dashboard/application.rb` - Application model
- `lib/tasks/error_dashboard.rake` - 3 rake tasks (list_applications, backfill_application, app_stats)
- 4 migrations for zero-downtime schema changes
- `docs/MULTI_APP_PERFORMANCE.md` - Performance analysis

### 🔒 Security Hardening

#### Authentication Always Required
**BREAKING CHANGE:** Authentication is now always enforced with no bypass option.

- Removed `require_authentication` config option
- Removed `require_authentication_in_development` option
- Authentication now enforced at code level (cannot be disabled)
- No development environment bypass
- Prevents accidental production exposure

**Rationale:**
- Eliminates config-based security vulnerabilities
- Consistent security across all environments
- No risk of accidentally disabling auth in production

**Migration:** Remove these lines from your initializer if present:
```ruby
config.require_authentication = false  # REMOVE
config.require_authentication_in_development = false  # REMOVE
```

### ✨ UI/UX Improvements

#### Light Theme Fixes
Fixed multiple visibility issues in light theme:
- **App Switcher Button**: Fixed invisible white text on light background
- **Dropdown Menus**: Fixed invisible menu items (white on white)
- **Chart Tooltips**: Fixed unreadable dark text on dark background
- Added proper CSS specificity with `!important` overrides
- Tested and verified in both light and dark themes

**Technical Details:**
- Added `.app-switcher-btn` CSS class with theme-aware colors
- Fixed dropdown menu colors for light/dark themes
- Dynamic Chart.js tooltip colors based on theme
- Theme-aware text colors ensure readability

### 🐛 Critical Bug Fixes

#### Fix #1: Analytics Cache Key Bug
**File:** `lib/rails_error_dashboard/queries/analytics_stats.rb:49`

**Issue:** Cache key used `ErrorLog.maximum(:updated_at)` instead of `base_scope.maximum(:updated_at)`

**Impact:**
- Cache not properly isolated per application
- Cache invalidates globally when ANY app's errors change
- Same bug already fixed in `dashboard_stats.rb` but missed here

**Fix:** Changed to `base_scope.maximum(:updated_at)` for proper per-app cache isolation

#### Fix #2: N+1 Query in Rake Task
**File:** `lib/tasks/error_dashboard.rake`

**Issue:** `error_dashboard:list_applications` task made **6N database queries** where N = number of apps
- 10 apps = 60 queries
- 100 apps = 600 queries!

**Fix:** Single SQL query with LEFT JOIN and aggregates
```ruby
# Before: 6N queries
apps.map(&:error_count)  # N queries
apps.map(&:unresolved_error_count)  # N queries
apps.sum(&:error_count)  # 2N queries
apps.sum(&:unresolved_error_count)  # 2N queries

# After: 1 query
apps = Application
  .select('applications.*, COUNT(...) as total_errors, SUM(CASE...) as unresolved_errors')
  .joins('LEFT JOIN error_logs...')
  .group('applications.id')
```

**Performance Improvement:** ~600x faster for 100 apps (600 queries → 1 query)

### 🔧 Code Quality Improvements

#### Previous Fixes (from Initial Code Review)
- Removed orphaned test for `require_authentication`
- Fixed `dashboard_stats` cache key to use `base_scope` for proper isolation
- Simplified redundant conditional in `errors_list` filter
- Standardized logging to use `RailsErrorDashboard::Logger` throughout (5 locations)
- Updated 6 documentation files to remove authentication bypass references

#### Logger Consistency
- Changed all `Rails.logger` calls to `RailsErrorDashboard::Logger`
- Logging now respects `enable_internal_logging` configuration
- Improved error messages with class names and context

### 📚 Documentation

**New Documentation:**
- `CODE_REVIEW_REPORT.md` - Initial comprehensive review (17 issues identified)
- `FIXES_APPLIED.md` - Documentation of 6 major fixes with verification steps
- `ULTRATHINK_ANALYSIS.md` - Deep analysis (12 issues, 2 critical)
- `CRITICAL_FIXES_ULTRATHINK.md` - Documentation of 2 critical performance fixes
- `MULTI_APP_PERFORMANCE.md` - Performance benchmarks and analysis

**Updated Documentation:**
- `README.md` - Added multi-app support section
- `API_REFERENCE.md` - Removed authentication bypass options
- `FEATURES.md` - Updated authentication section
- `CONFIGURATION.md` - Removed auth config options (2 locations)
- `NOTIFICATIONS.md` - Updated authentication examples

### 📊 Performance Impact

**Before This Release:**
- Cache invalidates globally for all apps
- Rake task: 6N queries (600 for 100 apps)
- No per-app cache isolation

**After This Release:**
- Per-app cache isolation (only invalidates relevant app)
- Rake task: 1 query with aggregates (~600x improvement)
- Proper cache keys with `base_scope` filtering

### 🗄️ Database Migrations

This release includes 4 migrations for multi-app support:

1. `20260106094220_create_rails_error_dashboard_applications.rb` - Create applications table
2. `20260106094233_add_application_to_error_logs.rb` - Add application_id (nullable + indexes)
3. `20260106094256_backfill_application_for_existing_errors.rb` - Backfill existing errors
4. `20260106094318_finalize_application_foreign_key.rb` - Add NOT NULL + foreign key

**Migration Strategy:**
- Zero downtime - all changes are additive
- Backward compatible with existing data
- Automatic backfill of existing errors with default application
- Safe for production deployment

### 🧪 Testing & Verification

- All critical fixes verified with step-by-step testing
- No regressions detected
- Cache isolation verified for per-app stats
- Multi-app filtering tested with 4 applications
- Query performance tested with SQL aggregates
- All existing specs passing

### ⚠️ Breaking Changes

1. **Authentication always required** - No config option to disable
   - Remove `config.require_authentication` from initializer
   - Remove `config.require_authentication_in_development` from initializer

2. **No development bypass** - Authentication enforced in all environments

### 🔄 Upgrade Instructions

```bash
# Update gem
bundle update rails_error_dashboard

# Run migrations (required for multi-app support)
rails db:migrate

# Update initializer (remove authentication config if present)
# Remove these lines if they exist in config/initializers/rails_error_dashboard.rb:
# config.require_authentication = false
# config.require_authentication_in_development = false

# Restart your application
```

### 📦 Files Changed

**33 files changed, 3459 insertions(+), 156 deletions(-)**

**New Files:**
- Application model
- 4 migrations
- 3 rake tasks
- 4 documentation files
- Test factories and specs

**Modified Files:**
- All query objects (analytics_stats, dashboard_stats, errors_list, filter_options)
- Error logging command
- Errors controller
- Configuration
- Multiple view files
- Documentation files

### 🎯 Next Steps

After upgrading:
1. Run migrations: `rails db:migrate`
2. Verify authentication works in all environments
3. Check multi-app features if using multiple apps
4. Review new rake tasks: `rails error_dashboard:list_applications`

### 🙏 Credits

This release includes comprehensive work on:
- Multi-app architecture and implementation
- Security hardening (authentication enforcement)
- Code quality improvements (8 critical/high issues fixed)
- Performance optimization (cache keys, N+1 elimination)
- UI/UX improvements (theme fixes, progressive disclosure)

## [0.1.21] - 2025-01-04

### Fixed
- **CRITICAL: Turbo Helpers Missing in Production** - Fixed `undefined method 'turbo_stream_from'` error
  - Fixed production-only error when accessing error dashboard pages
  - Added explicit `require "turbo-rails"` to ensure helpers are available
  - Resolves initialization order issues in production mode (eager loading)
  - Error was caused by engine loading before host app's Turbo initialization
  - Affects real-time updates feature (`turbo_stream_from "error_list"`)
  - **Impact**: Dashboard now works correctly in production environments
  - **Credit**: Thanks to @bonniesimon for identifying and fixing this issue! 🎉

### Technical Details
- **File modified**: `lib/rails_error_dashboard.rb`
- **Issue**: Production eager loading caused helper unavailability
- **Solution**: Explicitly require turbo-rails alongside other dependencies
- **Related**: Similar to [turbo-rails issue #64](https://github.com/hotwired/turbo-rails/issues/64)
- **Why development worked**: Lazy autoloading masked the problem
- **Why production failed**: Eager loading exposed initialization race condition
- 100% backward compatible - turbo-rails already a required dependency

### Community
- 🎉 **First external contribution** by @bonniesimon
- Properly identified production-only bug
- Clean, minimal fix with excellent documentation
- Followed proper issue → PR workflow

## [0.1.20] - 2025-01-03

### Added
- **ManualErrorReporter - Report Errors from Frontend/Mobile Apps** - New API for logging errors without Exception objects
  - New `RailsErrorDashboard::ManualErrorReporter.report` method for manual error reporting
  - Clean keyword argument API accepts hash-like parameters (no Exception object needed)
  - Perfect for logging errors from JavaScript frontends, mobile apps (iOS/Android), or any external source
  - Supports all major platforms: Web, iOS, Android, API, or custom platforms
  - Accepts custom metadata, user IDs, app versions, backtraces, and more
  - Works with existing error grouping and deduplication system
  - Supports both sync and async logging modes
  - **Example**: `ManualErrorReporter.report(error_type: "TypeError", message: "Cannot read property 'foo'", platform: "Web", user_id: 123)`

### Improved
- **SyntheticException** - Internal bridge class for manual errors
  - Converts manual error reports into Exception-like objects
  - Seamlessly integrates with existing LogError command
  - Preserves error type, message, and backtrace information
  - Mock class returns simple error type name instead of full class path

### Enhanced
- **Platform Detection** - Respects explicitly provided platform parameter
  - ErrorContext now prioritizes manually provided platform over auto-detection
  - Allows accurate platform tracking for mobile/frontend errors
  - Falls back to user-agent detection when platform not specified
  - Added comprehensive error handling for edge cases

### Technical Details
- **New file**: `lib/rails_error_dashboard/manual_error_reporter.rb` (200+ lines)
  - `ManualErrorReporter.report` class method with keyword arguments
  - `SyntheticException` class mimics Ruby Exception interface
  - `MockClass` provides error type name for exception class
  - Normalizes backtrace input (accepts arrays or newline-separated strings)
- **Modified**: `lib/rails_error_dashboard/value_objects/error_context.rb`
  - Enhanced `detect_platform` to check for explicit platform first (line 123-140)
  - Added robust error handling with debug logging
- **Modified**: `lib/rails_error_dashboard.rb`
  - Added require for manual_error_reporter (line 5)
- **Testing**: 21 new comprehensive test cases, all 916 automated tests passing
- **Compatibility**: Works perfectly in both full Rails and API-only apps

### Use Cases
- Log JavaScript errors from React/Vue/Angular frontends
- Report iOS crashes from Swift/Objective-C apps
- Track Android exceptions from Kotlin/Java apps
- Monitor API errors from mobile SDKs
- Capture validation errors without raising exceptions
- Integrate with external error monitoring services

### API Parameters
**Required:**
- `error_type` - Type of error (e.g., "TypeError", "NSException", "RuntimeException")
- `message` - Error message

**Optional:**
- `backtrace` - Array or newline-separated string
- `platform` - Platform name (e.g., "Web", "iOS", "Android", "API")
- `user_id` - User identifier
- `request_url` - URL where error occurred
- `user_agent` - Browser/app user agent string
- `ip_address` - Client IP address
- `app_version` - Application version
- `metadata` - Hash of custom metadata
- `occurred_at` - Timestamp (defaults to Time.current)
- `severity` - Error severity level
- `source` - Error source (defaults to "manual")

## [0.1.19] - 2025-01-02

### Fixed
- **CRITICAL: File Permission Error on Railway/Production** - Fixed gem loading failures
  - Fixed `cannot load such file -- logger.rb` error on Railway and other platforms
  - Corrected file permissions from 600 (owner-only) to 644 (world-readable)
  - Fixed 7 files with incorrect permissions:
    - `lib/rails_error_dashboard/logger.rb`
    - `lib/rails_error_dashboard/services/backtrace_parser.rb`
    - `lib/rails_error_dashboard/services/baseline_alert_throttler.rb`
    - `lib/rails_error_dashboard/services/baseline_calculator.rb`
    - `lib/rails_error_dashboard/services/pattern_detector.rb`
    - `lib/rails_error_dashboard/services/similarity_calculator.rb`
    - `lib/tasks/rails_error_dashboard_tasks.rake`
  - Gem now loads correctly in production environments (Railway, Heroku, Render, etc.)

### Technical Details
- File permissions issue caused Bundler::GemRequireError in production
- Files were created with restrictive permissions (600) preventing read access
- Changed all library files to standard permissions (644)
- Resolves zeitwerk autoloading failures in production
- No functional changes - only permission fixes

## [0.1.18] - 2025-01-02

### Added
- **Local Timezone Conversion** - All timestamps now display in user's local timezone
  - Timestamps automatically convert from UTC to user's browser timezone
  - New `local_time` helper for formatted timestamps with automatic conversion
  - New `local_time_ago` helper for relative timestamps ("3 hours ago")
  - Click any timestamp to toggle between local time and UTC
  - Click relative times to toggle between relative and absolute formats
  - Timezone abbreviation displayed (PST, EST, UTC+2, etc.)
  - JavaScript handles conversion client-side for instant display
  - Works with Turbo navigation (turbo:load and turbo:frame-load events)

### Improved
- **Better User Experience** - Time display matches user's context
  - No more mental math to convert UTC to local time
  - Interactive timestamps with click-to-toggle functionality
  - Graceful fallback for non-JavaScript browsers (shows UTC)
  - Consistent time format across all dashboard pages
  - Supports multiple timestamp formats (:full, :short, :date_only, :time_only, :datetime)

### Technical Details
- Added `local_time` and `local_time_ago` helpers to ApplicationHelper
- Added client-side JavaScript for timezone conversion in layout
- Updated all view templates to use new timezone-aware helpers:
  - Error detail page (show.html.erb)
  - Error list (_error_row.html.erb)
  - Timeline partial (_timeline.html.erb)
  - Overview page
  - Index page
  - Analytics page
- Format presets support strftime-like syntax (e.g., "%B %d, %Y %I:%M:%S %p")
- ISO 8601 timestamps passed via data attributes for JavaScript parsing
- 100% backward compatible - no breaking changes

## [0.1.17] - 2025-01-02

### Fixed
- **CRITICAL: Broadcast Failures in API-Only Mode** - Real-time updates now work reliably in API-only apps
  - Fixed `undefined method 'fetch' for nil` error in AsyncErrorLoggingJob broadcasts
  - Added `broadcast_available?` check to verify ActionCable and Rails.cache availability
  - Added safety check to ensure stats hash is present before broadcasting
  - Added comprehensive error handling in `DashboardStats.call` to prevent nil returns
  - Improved error logging with class names and backtraces for easier debugging
  - **Impact**: Broadcasts now gracefully skip in API-only environments without errors
  - **Testing**: 895 automated tests passing with zero failures

### Improved
- **Robust Broadcasting** - More resilient real-time updates
  - Broadcast methods now check infrastructure availability before attempting updates
  - DashboardStats returns safe default hash on any cache/database failures
  - Better error messages with debug-level backtraces for troubleshooting
  - Prevents error logging failures from causing additional errors

### Technical Details
- Modified files: ErrorLog model (broadcast methods), DashboardStats query
- Added `broadcast_available?` method to check ActionCable and cache availability
- Wrapped `DashboardStats.call` in begin/rescue with safe fallback hash
- All broadcast errors now logged with class name and message for debugging
- 100% backward compatible - no breaking changes

## [0.1.16] - 2025-01-02

### Fixed
- **CRITICAL: API-Only Mode Compatibility** - Dashboard now works in Rails API-only applications
  - Fixed `undefined method 'flash'` error when accessing dashboard in API-only apps
  - Fixed `detect_platform` error in production for API-only request objects
  - Enabled required middleware (Flash, Cookies, Session) conditionally for API-only apps
  - Added robust error handling for request URL building with fallback methods
  - Added error handling for platform detection with rescue block and fallback
  - Added conditional rendering for CSRF meta tags and CSP tags
  - Added `respond_to?` checks for session access to prevent crashes
  - Explicitly includes `ActionController::Cookies`, `ActionController::Flash`, and `ActionController::RequestForgeryProtection` in ApplicationController
  - Dashboard routes now work seamlessly in both full Rails and API-only applications
  - **Testing**: 895 automated tests passing with zero failures
  - **100% backward compatible** - no breaking changes for existing installations

### Improved
- **Error Context Handling** - More resilient error logging
  - Request URL building now handles both full Rails and API-only request objects
  - Platform detection gracefully falls back to "API" on detection failures
  - Session access safely checks for method availability before calling
  - All error context extraction methods now handle edge cases without crashing

### Technical Details
- Modified files: ApplicationController, Engine initializer, ErrorContext value object, layout view
- Middleware is loaded conditionally based on `Rails.application.config.api_only` setting
- No configuration changes required - works automatically in all Rails modes
- Tested in both Rails 7.0 and Rails 8.1 with API-only mode enabled

## [0.1.15] - 2025-01-01

### Added
- **Keyboard Shortcuts Modal** - Enhanced UX with Bootstrap modal
  - Upgraded from simple alert to full Bootstrap modal display
  - Shows all available shortcuts: R (refresh), / (search), A (analytics), ? (help)
  - Professional UI with icons and clear descriptions
  - Accessible via `?` key from any dashboard page

- **NEW Badge for Recent Errors** - Visual indicator for fresh errors
  - Green "NEW" badge appears on errors less than 1 hour old
  - Uses existing `recent?` method (no database changes needed)
  - Displays on both error list and error detail pages
  - Includes helpful tooltip explaining the badge

- **Error Count in Browser Tab** - At-a-glance monitoring
  - Shows unresolved error count in browser tab title: "(123) Errors | App"
  - Only displays when unresolved count > 0
  - Updates automatically with page navigation
  - Helps monitor error volume across multiple tabs

- **Jump to First Occurrence** - Quick timeline navigation
  - First Seen timestamp now clickable with down arrow icon
  - Scrolls directly to timeline section showing error history
  - Only appears when timeline data exists
  - Includes tooltip: "Jump to timeline"

- **Share Error Link** - Easy error sharing
  - One-click button to copy error URL to clipboard
  - Located in error detail header next to "Mark as Resolved"
  - Visual feedback: button turns green with "Copied!" for 2 seconds
  - Perfect for sharing via Slack, email, or tickets

- **Export Error as JSON** - Data export capability
  - Download complete error details as formatted JSON
  - Filename includes error ID and type: `error_123_TypeError.json`
  - Includes all fields: backtrace, timestamps, platform, severity, etc.
  - Useful for bug reports, external systems, or data analysis
  - Visual feedback on successful download

- **Quick Comment Templates** - Faster error communication
  - 5 pre-formatted templates for common responses
  - Templates: Investigating, Found Fix, Need Info, Duplicate, Cannot Reproduce
  - Each template includes contextual emoji and structured format
  - One-click insertion into comment textarea
  - Speeds up triaging and team collaboration

### Fixed
- **Missing Root Route Handler** - Prevents crash in apps without root route
  - Added safe check for `main_app.root_path` existence
  - Dashboard no longer crashes when host app doesn't define root route
  - Gracefully falls back to non-clickable navbar brand
  - Fixes compatibility with API-only and minimal Rails apps
  - Error: `undefined method 'root_path' for ActionDispatch::Routing::RoutesProxy`

- **Incorrect Column Name in JSON Export** - Fixed database field reference
  - Changed `resolved_by` to `resolved_by_name` in downloadErrorJSON function
  - Prevents crash when viewing error detail pages
  - Error: `undefined method 'resolved_by' for ErrorLog`

## [0.1.14] - 2025-12-31

### Added
- **Clickable Git Commit Links** - Easy win UX improvement for developers
  - Added `git_repository_url` configuration option
  - Git SHAs now display as clickable links when repository URL is configured
  - Supports GitHub, GitLab, and Bitbucket URL formats
  - Links open in new tab with security (`target="_blank" rel="noopener"`)
  - Graceful fallback to plain code display if no repo URL configured
  - Updated error show page and settings page to use clickable links
  - New helper method: `git_commit_link(git_sha, short: true)`

### Fixed
- Fixed lefthook configuration to exclude ERB templates from RuboCop checks

## [0.1.13] - 2025-12-31

### Changed
- **Improved Post-Install Message** - Better UX for both fresh installs and upgrades
  - Clear separation between first-time install instructions and upgrade instructions
  - First-time users see quick 3-step setup guide
  - Upgrading users see migration reminder and changelog link
  - Both audiences get live demo and documentation links
  - More user-friendly than previous version-agnostic message

### Fixed
- **CRITICAL**: Fixed SolidCache compatibility issue that prevented error logging
  - `clear_analytics_cache` now checks if cache store supports `delete_matched` before calling
  - Added graceful handling for `NotImplementedError` from cache stores
  - Fixes Rails 8 deployments using SolidCache (default cache in Rails 8)
  - Database seeding now works correctly in production with SolidCache

## [0.1.10] - 2025-12-30

### Fixed
- **View Bug**: Fixed `undefined method 'updated_at' for Hash` error on error show page
  - Added safety checks for baseline and similar_errors data types
  - Prevents crashes when these features return unexpected data structures
  - Improves robustness of error detail page display

## [0.1.9] - 2025-12-30

### Fixed
- **CRITICAL**: Fixed Rails 8+ compatibility issue in installer
  - Changed `rake` to `rails_command` for copying migrations
  - This bug caused silent migration copy failures on Rails 8+ installations
  - Affects all users trying to install or upgrade on Rails 8.0+
  - **Recommendation**: All Rails 8+ users should upgrade to 0.1.9 immediately

## [0.1.8] - 2025-12-30

### Fixed
- **Documentation**: Standardized default credentials to `gandalf/youshallnotpass` across all documentation and examples for consistency with the gem's LOTR theme
  - Updated post-install message
  - Updated README demo credentials

## [0.1.7] - 2025-12-30

### 🚀 Major Performance Improvements

This release includes 7 phases of comprehensive performance optimizations that dramatically improve dashboard speed and scalability.

#### Phase 1: Database Performance Indexes
- **5 Composite Indexes** - Optimized common query patterns
  - `(assigned_to, status, occurred_at)` - Assignment workflow filtering
  - `(priority_level, resolved, occurred_at)` - Priority filtering
  - `(platform, status, occurred_at)` - Platform + status filtering
  - `(app_version, resolved, occurred_at)` - Version filtering
  - `(snoozed_until, occurred_at)` with partial index - Snooze management
- **PostgreSQL GIN Full-Text Index** - Fast search across message, backtrace, error_type
- **Performance Gain**: 50-80% faster queries

#### Phase 2: N+1 Query Fixes
- **Critical N+1 Bug Fixed** - `errors_by_severity_7d` was loading ALL 7-day errors into Ruby memory
  - Changed to database filtering using error type constants
  - 95% performance improvement
- **Eager Loading** - Added `.includes(:comments, :parent_cascade_patterns, :child_cascade_patterns)` to show action
- **Critical Alerts Optimization** - Changed from Ruby `.select{}` to database `.where()`
  - 95% performance improvement
- **Performance Gain**: 30-95% query reduction

#### Phase 3: Enhanced Search Functionality
- **PostgreSQL Full-Text Search** - Uses `plainto_tsquery` with GIN index
  - Searches across message, backtrace, AND error_type fields
  - 70-90% faster than LIKE queries
- **MySQL/SQLite Fallback** - LIKE-based search with COALESCE
- **Multi-Field Search** - Comprehensive search coverage
- **Performance Gain**: 70-90% faster search with PostgreSQL

#### Phase 4: Rate Limiting Middleware
- **Custom Rack Middleware** - `RailsErrorDashboard::Middleware::RateLimiter`
- **Differentiated Limits**:
  - API endpoints: 100 requests/minute per IP
  - Dashboard pages: 300 requests/minute per IP
- **Per-IP Tracking** - Automatic expiration with Rails.cache
- **Configurable** - Opt-in via `config.enable_rate_limiting`
- **Graceful Responses** - Returns 429 Too Many Requests with appropriate message

#### Phase 5: Query Result Caching
- **DashboardStats Caching** - 1-minute TTL
  - Cache key includes last error update timestamp + current hour
- **AnalyticsStats Caching** - 5-minute TTL
  - Cache key includes days parameter + last error update + start date
- **Automatic Cache Invalidation** - Via model callbacks
  - `after_save :clear_analytics_cache`
  - `after_destroy :clear_analytics_cache`
  - Pattern-based clearing with `Rails.cache.delete_matched`
- **Performance Gain**: 70-95% faster on cache hits, 85% database load reduction

#### Phase 6: View Optimization
- **Fragment Caching** - Added to large 45KB show.html.erb view
  - Error details section: `<% cache [@error, 'error_details_v1'] do %>`
  - Request context section: `<% cache [@error, 'request_context_v1'] do %>`
  - Similar errors section: `<% cache [@error, 'similar_errors_v1', similar.maximum(:updated_at)] do %>`
- **Smart Cache Keys** - Version suffixes for easy invalidation
- **Selective Caching** - Did NOT cache frequently changing sections (comments, workflow status)
- **Performance Gain**: 60-80% faster page loads

#### Phase 7: Comprehensive API Documentation
- **Enhanced docs/API_REFERENCE.md** - From 4.5KB to 21KB (847 lines)
- **Complete HTTP API Reference**:
  - Authentication and rate limiting details
  - All dashboard endpoints (list, show, resolve, assign, priority, status, snooze, comments, batch)
  - Analytics endpoints (overview, analytics, platform comparison, correlation)
  - Error logging endpoint patterns with custom controller examples
  - HTTP response codes reference table
- **Code Examples** - Multiple languages:
  - JavaScript (Fetch API for React/React Native)
  - Swift (iOS native)
  - Kotlin (Android native)
  - cURL (testing)
- **Cross-References** - Links to Mobile App Integration guide

### 📊 Overall Performance Gains
- Database queries: 50-95% faster
- View rendering: 60-80% faster
- Analytics: 70-95% faster with caching
- Database load: 85% reduction
- Search: 70-90% faster with PostgreSQL

### 📚 Documentation Improvements
- **IMPROVEMENTS_ROADMAP.md** - Updated with all completed phases
- **API_REFERENCE.md** - Comprehensive HTTP API documentation
- **Migration** - `db/migrate/20251229111223_add_additional_performance_indexes.rb`

### 🔧 Technical Details

**New Files:**
- `lib/rails_error_dashboard/middleware/rate_limiter.rb` - Rate limiting middleware
- `db/migrate/20251229111223_add_additional_performance_indexes.rb` - Performance indexes

**Modified Files:**
- `app/controllers/rails_error_dashboard/errors_controller.rb` - Eager loading + optimizations
- `lib/rails_error_dashboard/queries/errors_list.rb` - Enhanced search
- `lib/rails_error_dashboard/queries/dashboard_stats.rb` - Caching + N+1 fix
- `lib/rails_error_dashboard/queries/analytics_stats.rb` - Caching
- `lib/rails_error_dashboard/configuration.rb` - Rate limiting config
- `lib/rails_error_dashboard/engine.rb` - Middleware integration
- `app/models/rails_error_dashboard/error_log.rb` - Cache invalidation
- `app/views/rails_error_dashboard/errors/show.html.erb` - Fragment caching

**Upgrade Instructions:**
```bash
bundle update rails_error_dashboard
rails db:migrate  # Run the new performance indexes migration
```

**Configuration:**
```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  # Optional: Enable rate limiting (disabled by default)
  config.enable_rate_limiting = true
  config.rate_limit_per_minute = 100
end
```

**Breaking Changes:** None - All changes are backward compatible

**Migration Required:** Yes - Run `rails db:migrate` to add performance indexes

## [0.1.6] - 2025-12-29

### 🐛 Bug Fixes

#### Pagination
- **Pagy Bootstrap Extras** - Fixed missing pagination helper
  - Added `require 'pagy/extras/bootstrap'` to gem initialization
  - Gem now includes pagy_bootstrap_nav helper automatically
  - No longer requires consuming applications to add pagy initializer
  - Fixes "undefined method `pagy_bootstrap_nav`" error on error list page

### 🔧 Technical Details

This is a minor patch release fixing a pagination issue introduced in 0.1.5.

**Upgrade Instructions:**
```ruby
# Gemfile
gem "rails_error_dashboard", "~> 0.1.6"
```

Then run:
```bash
bundle update rails_error_dashboard
```

**Note:** If you previously added a pagy initializer to work around this issue, you can safely remove it.

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

- **Unreleased** - Future improvements
- **0.1.7** (2025-12-30) - Major performance improvements (7 phases: indexes, N+1 fixes, search, rate limiting, caching, view optimization, API docs)
- **0.1.6** (2025-12-29) - Pagination bug fix
- **0.1.5** (2025-12-28) - Settings page and navigation improvements
- **0.1.4** (2025-12-27) - Flaky test fixes and uninstall system
- **0.1.1** (2025-12-25) - Bug fixes and stability improvements
- **0.1.0** (2024-12-24) - Initial beta release with complete feature set

[Unreleased]: https://github.com/AnjanJ/rails_error_dashboard/compare/v0.1.7...HEAD
[0.1.7]: https://github.com/AnjanJ/rails_error_dashboard/compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com/AnjanJ/rails_error_dashboard/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/AnjanJ/rails_error_dashboard/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/AnjanJ/rails_error_dashboard/compare/v0.1.1...v0.1.4
[0.1.1]: https://github.com/AnjanJ/rails_error_dashboard/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/AnjanJ/rails_error_dashboard/releases/tag/v0.1.0
