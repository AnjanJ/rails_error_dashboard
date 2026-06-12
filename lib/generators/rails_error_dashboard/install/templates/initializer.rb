# frozen_string_literal: true

RailsErrorDashboard.configure do |config|
  # ============================================================================
  # AUTHENTICATION (Always Required - Cannot Be Disabled)
  # ============================================================================

  # Dashboard authentication credentials
  # ⚠️ CHANGE THESE BEFORE PRODUCTION! ⚠️
  # Authentication is ALWAYS enforced in ALL environments (production, development, test)
  config.dashboard_username = ENV.fetch("ERROR_DASHBOARD_USER", "gandalf")
  config.dashboard_password = ENV.fetch("ERROR_DASHBOARD_PASSWORD", "youshallnotpass")

  # === Custom Authentication (optional) ===
  # Use your app's existing auth instead of HTTP Basic Auth.
  # The lambda runs in controller context (via instance_exec), giving access to
  # warden, session, request, params, cookies, redirect_to, etc.
  # Return truthy to allow access, falsy to deny (403 Forbidden).
  #
  # NOTE: Devise helpers (current_user, authenticate_user!) are NOT available
  # because the engine controller inherits from ActionController::Base, not your
  # app's ApplicationController. Use `warden` directly instead.
  #
  # Devise/Warden example (recommended):
  #   config.authenticate_with = -> { warden.authenticated? }
  #
  # Warden with redirect to login:
  #   config.authenticate_with = -> {
  #     if warden.authenticated?
  #       true
  #     else
  #       redirect_to main_app.new_user_session_path, allow_other_host: true
  #     end
  #   }
  #
  # Session-based example:
  #   config.authenticate_with = -> { session[:dashboard_admin] == true }
  #
  # When nil (default), HTTP Basic Auth above is used instead.
  # config.authenticate_with = nil

  # ============================================================================
  # CORE FEATURES (Always Enabled)
  # ============================================================================

  # Error capture via middleware and Rails.error subscriber
  config.enable_middleware = true
  config.enable_error_subscriber = true

  # User model for error associations
  config.user_model = "User"

  # Error retention policy (days to keep errors before automatic deletion)
  # Set to nil to keep errors forever (not recommended for production)
  # Run cleanup manually: rails error_dashboard:retention_cleanup
  # Or schedule the job: RailsErrorDashboard::RetentionCleanupJob.perform_later
  config.retention_days = 90

  # ============================================================================
  # NOTIFICATION SETTINGS
  # ============================================================================
  # Configure which notification channels you want to use.
  # You can enable/disable any of these at any time by changing true/false.

<% if @enable_slack -%>
  # Slack Notifications - ENABLED
  config.enable_slack_notifications = true
  config.slack_webhook_url = ENV["SLACK_WEBHOOK_URL"]
  # To disable: Set config.enable_slack_notifications = false

<% else -%>
  # Slack Notifications - DISABLED
  # To enable: Set config.enable_slack_notifications = true and configure webhook URL
  config.enable_slack_notifications = false
  # config.slack_webhook_url = ENV["SLACK_WEBHOOK_URL"]

<% end -%>
<% if @enable_email -%>
  # Email Notifications - ENABLED
  config.enable_email_notifications = true
  config.notification_email_recipients = ENV.fetch("ERROR_NOTIFICATION_EMAILS", "").split(",").map(&:strip)
  config.notification_email_from = ENV.fetch("ERROR_NOTIFICATION_FROM", "errors@example.com")
  # To disable: Set config.enable_email_notifications = false

<% else -%>
  # Email Notifications - DISABLED
  # To enable: Set config.enable_email_notifications = true and configure recipients
  config.enable_email_notifications = false
  # config.notification_email_recipients = ENV.fetch("ERROR_NOTIFICATION_EMAILS", "").split(",").map(&:strip)
  # config.notification_email_from = ENV.fetch("ERROR_NOTIFICATION_FROM", "errors@example.com")

<% end -%>
<% if @enable_discord -%>
  # Discord Notifications - ENABLED
  config.enable_discord_notifications = true
  config.discord_webhook_url = ENV["DISCORD_WEBHOOK_URL"]
  # To disable: Set config.enable_discord_notifications = false

<% else -%>
  # Discord Notifications - DISABLED
  # To enable: Set config.enable_discord_notifications = true and configure webhook URL
  config.enable_discord_notifications = false
  # config.discord_webhook_url = ENV["DISCORD_WEBHOOK_URL"]

<% end -%>
<% if @enable_pagerduty -%>
  # PagerDuty Integration - ENABLED (critical errors only)
  config.enable_pagerduty_notifications = true
  config.pagerduty_integration_key = ENV["PAGERDUTY_INTEGRATION_KEY"]
  # To disable: Set config.enable_pagerduty_notifications = false

<% else -%>
  # PagerDuty Integration - DISABLED
  # To enable: Set config.enable_pagerduty_notifications = true and configure integration key
  config.enable_pagerduty_notifications = false
  # config.pagerduty_integration_key = ENV["PAGERDUTY_INTEGRATION_KEY"]

<% end -%>
<% if @enable_webhooks -%>
  # Generic Webhook Notifications - ENABLED
  config.enable_webhook_notifications = true
  config.webhook_urls = ENV.fetch("WEBHOOK_URLS", "").split(",").map(&:strip).reject(&:empty?)
  # To disable: Set config.enable_webhook_notifications = false

<% else -%>
  # Generic Webhook Notifications - DISABLED
  # To enable: Set config.enable_webhook_notifications = true and configure webhook URLs
  config.enable_webhook_notifications = false
  # config.webhook_urls = ENV.fetch("WEBHOOK_URLS", "").split(",").map(&:strip).reject(&:empty?)

<% end -%>
  # Dashboard base URL (used in notification links)
  config.dashboard_base_url = ENV["DASHBOARD_BASE_URL"]

  # ============================================================================
  # PERFORMANCE & SCALABILITY
  # ============================================================================

<% if @enable_async_logging -%>
  # Async Error Logging - ENABLED
  # Errors are logged in background jobs — zero impact on request response time.
  # Default adapter is :async (Rails built-in, no extra infrastructure needed).
  # Swap to :sidekiq or :solid_queue when you have a background worker running.
  config.async_logging = true
  config.async_adapter = :async  # Options: :async (built-in), :sidekiq, :solid_queue
  # To disable: Set config.async_logging = false

<% else -%>
  # Async Error Logging - DISABLED
  # Errors are logged synchronously (adds ~1-5ms to requests that trigger errors)
  # To enable: Set config.async_logging = true
  config.async_logging = false
  # config.async_adapter = :async  # Options: :async (built-in), :sidekiq, :solid_queue

<% end -%>
  # Backtrace size limiting (100 lines is industry standard: Rollbar, Airbrake, Bugsnag)
  config.max_backtrace_lines = 100

<% if @enable_error_sampling -%>
  # Error Sampling - ENABLED
  # Samples non-critical errors to reduce storage volume.
  # Critical and high severity errors are ALWAYS logged at 100% regardless of this setting.
  # 0.5 = log 50% of non-critical occurrences — halves storage while keeping
  # occurrence counts meaningful and error patterns visible.
  # Tune lower (e.g. 0.1) if one error is flooding the DB; set to 1.0 to log everything.
  config.sampling_rate = 0.5  # 50% of non-critical errors
  # To disable: Set config.sampling_rate = 1.0 (100%)

<% else -%>
  # Error Sampling - DISABLED
  # All errors are logged (100% sampling rate).
  # To enable: Set config.sampling_rate < 1.0 (e.g., 0.5 for 50%, 0.1 for 10%)
  config.sampling_rate = 1.0

<% end -%>
  # Ignored exceptions (skip logging these)
  # config.ignored_exceptions = [
  #   "ActionController::RoutingError",
  #   "ActionController::InvalidAuthenticityToken",
  #   /^ActiveRecord::RecordNotFound/
  # ]

  # ============================================================================
  # DATABASE CONFIGURATION
  # ============================================================================

<% if @enable_separate_database -%>
  # Separate Error Database - ENABLED
  # Errors are stored in a dedicated database for isolation and scalability.
  # See https://github.com/AnjanJ/rails_error_dashboard/blob/main/docs/guides/DATABASE_OPTIONS.md
  config.use_separate_database = true
  config.database = :<%= @database_name || "error_dashboard" %>
<% if @enable_multi_app -%>

  # Multi-app mode: multiple Rails apps share this error database.
  # Each app is identified by its application_name.
  # Auto-detected from Rails.application.class.module_parent_name if not set.
  config.application_name = "<%= @application_name %>"
<% end -%>
  # To disable: Set config.use_separate_database = false

<% else -%>
  # Separate Error Database - DISABLED
  # Errors are stored in your main application database.
  # To enable: Set config.use_separate_database = true and configure database.yml
  # See https://github.com/AnjanJ/rails_error_dashboard/blob/main/docs/guides/DATABASE_OPTIONS.md
  config.use_separate_database = false
  # config.database = :error_dashboard

<% end -%>
  # ============================================================================
  # ADVANCED ANALYTICS
  # ============================================================================

<% if @enable_baseline_alerts -%>
  # Baseline Anomaly Alerts - ENABLED
  # Automatically detect when error rates exceed normal patterns
  config.enable_baseline_alerts = true
  config.baseline_alert_threshold_std_devs = 2.0  # Alert when > 2 std devs above baseline
  config.baseline_alert_severities = [ :critical, :high ]
  config.baseline_alert_cooldown_minutes = 120  # 2 hours between alerts
  # To disable: Set config.enable_baseline_alerts = false

<% else -%>
  # Baseline Anomaly Alerts - DISABLED
  # To enable: Set config.enable_baseline_alerts = true
  config.enable_baseline_alerts = false
  # config.baseline_alert_threshold_std_devs = 2.0
  # config.baseline_alert_severities = [ :critical, :high ]
  # config.baseline_alert_cooldown_minutes = 120

<% end -%>
<% if @enable_similar_errors -%>
  # Fuzzy Error Matching - ENABLED
  # Find similar errors even with different error_hashes
  config.enable_similar_errors = true
  # To disable: Set config.enable_similar_errors = false

<% else -%>
  # Fuzzy Error Matching - DISABLED
  # To enable: Set config.enable_similar_errors = true
  config.enable_similar_errors = false

<% end -%>
<% if @enable_co_occurring_errors -%>
  # Co-occurring Errors - ENABLED
  # Detect errors that happen together in time
  config.enable_co_occurring_errors = true
  # To disable: Set config.enable_co_occurring_errors = false

<% else -%>
  # Co-occurring Errors - DISABLED
  # To enable: Set config.enable_co_occurring_errors = true
  config.enable_co_occurring_errors = false

<% end -%>
<% if @enable_error_cascades -%>
  # Error Cascade Detection - ENABLED
  # Identify error chains (A causes B causes C)
  config.enable_error_cascades = true
  # To disable: Set config.enable_error_cascades = false

<% else -%>
  # Error Cascade Detection - DISABLED
  # To enable: Set config.enable_error_cascades = true
  config.enable_error_cascades = false

<% end -%>
<% if @enable_error_correlation -%>
  # Error Correlation Analysis - ENABLED
  # Correlate errors with versions, users, and time
  config.enable_error_correlation = true
  # To disable: Set config.enable_error_correlation = false

<% else -%>
  # Error Correlation Analysis - DISABLED
  # To enable: Set config.enable_error_correlation = true
  config.enable_error_correlation = false

<% end -%>
<% if @enable_platform_comparison -%>
  # Platform Comparison - ENABLED
  # Compare iOS vs Android vs Web health metrics
  config.enable_platform_comparison = true
  # To disable: Set config.enable_platform_comparison = false

<% else -%>
  # Platform Comparison - DISABLED
  # To enable: Set config.enable_platform_comparison = true
  config.enable_platform_comparison = false

<% end -%>
<% if @enable_occurrence_patterns -%>
  # Occurrence Pattern Detection - ENABLED
  # Detect cyclical patterns and error bursts
  config.enable_occurrence_patterns = true
  # To disable: Set config.enable_occurrence_patterns = false

<% else -%>
  # Occurrence Pattern Detection - DISABLED
  # To enable: Set config.enable_occurrence_patterns = true
  config.enable_occurrence_patterns = false

<% end -%>
  # ============================================================================
  # DEVELOPER TOOLS (NEW!)
  # ============================================================================

<% if @enable_source_code_integration -%>
  # Source Code Integration - ENABLED (NEW!)
  # View source code directly in error details with inline viewer
  config.enable_source_code_integration = true
  # To disable: Set config.enable_source_code_integration = false

<% else -%>
  # Source Code Integration - DISABLED (NEW!)
  # To enable: Set config.enable_source_code_integration = true
  config.enable_source_code_integration = false

<% end -%>
<% if @enable_git_blame -%>
  # Git Blame Integration - ENABLED (NEW!)
  # Show git blame info (author, commit, timestamp) for each source line
  config.enable_git_blame = true
  # To disable: Set config.enable_git_blame = false

<% else -%>
  # Git Blame Integration - DISABLED (NEW!)
  # To enable: Set config.enable_git_blame = true (requires Git installed)
  config.enable_git_blame = false

<% end -%>
<% if @enable_breadcrumbs -%>
  # Breadcrumbs - ENABLED
  # Capture a trail of events (SQL, controller, cache, etc.) leading up to each error
  config.enable_breadcrumbs = true
  config.breadcrumb_buffer_size = 40  # Max events per request
  # To disable: Set config.enable_breadcrumbs = false

<% else -%>
  # Breadcrumbs - DISABLED
  # To enable: Set config.enable_breadcrumbs = true
  config.enable_breadcrumbs = false
  # config.breadcrumb_buffer_size = 40

<% end -%>
  # N+1 Query Detection (analyzes SQL breadcrumbs at display time)
  # Flags repeated query patterns that suggest missing eager loading
  config.enable_n_plus_one_detection = true
  config.n_plus_one_threshold = 3  # Min repetitions to flag (min: 2)

<% if @enable_system_health -%>
  # System Health Snapshot - ENABLED (NEW!)
  # Capture GC stats, memory, threads, and connection pool state at error time
  config.enable_system_health = true
  # To disable: Set config.enable_system_health = false

<% else -%>
  # System Health Snapshot - DISABLED (NEW!)
  # To enable: Set config.enable_system_health = true
  config.enable_system_health = false

<% end -%>
<% if @enable_swallowed_exceptions -%>
  # Swallowed Exception Detection - ENABLED
  # Requires Ruby 3.3+ — detects exceptions that are raised then silently rescued
  # Uses TracePoint(:rescue), which was added in Ruby 3.3 (Feature #19572)
  config.detect_swallowed_exceptions = true
  config.swallowed_exception_threshold = 0.95       # Rescue ratio to flag (95%+)
  # config.swallowed_exception_flush_interval = 60   # Seconds between DB flushes
  # config.swallowed_exception_max_cache_size = 1000  # Max entries per thread
  # config.swallowed_exception_ignore_classes = []    # App-specific exceptions to skip
  # To disable: Set config.detect_swallowed_exceptions = false

<% else -%>
  # Swallowed Exception Detection - DISABLED
  # Requires Ruby 3.3+ (TracePoint(:rescue) not available before 3.3)
  # To enable: Set config.detect_swallowed_exceptions = true
  config.detect_swallowed_exceptions = false
  # config.swallowed_exception_threshold = 0.95

<% end -%>
<% if @enable_diagnostic_dump -%>
  # Diagnostic Dump - ENABLED
  # On-demand system state snapshot via rake task or dashboard button
  config.enable_diagnostic_dump = true
  # To disable: Set config.enable_diagnostic_dump = false

<% else -%>
  # Diagnostic Dump - DISABLED
  # On-demand system state snapshot (rake task + dashboard page)
  # To enable: Set config.enable_diagnostic_dump = true
  config.enable_diagnostic_dump = false

<% end -%>
<% if @enable_crash_capture -%>
  # Process Crash Capture - ENABLED
  # Captures fatal crashes via at_exit hook. Crash data is written to disk as JSON
  # and imported into the database on next boot. Zero runtime overhead.
  config.enable_crash_capture = true
  # config.crash_capture_path = "/tmp/my_app_crashes"  # Default: Dir.tmpdir
  # To disable: Set config.enable_crash_capture = false

<% else -%>
  # Process Crash Capture - DISABLED
  # Captures fatal crashes via at_exit hook (written to disk, imported on next boot)
  # To enable: Set config.enable_crash_capture = true
  config.enable_crash_capture = false
  # config.crash_capture_path = "/tmp/my_app_crashes"

<% end -%>
  # Repository settings (auto-detected from git remote, optional override)
  # config.repository_url = ENV["REPOSITORY_URL"]  # e.g., "https://github.com/user/repo"
  # config.repository_branch = ENV.fetch("REPOSITORY_BRANCH", "main")  # Default branch

  # ============================================================================
  # INTERNAL LOGGING (Silent by Default)
  # ============================================================================
  # Rails Error Dashboard logging is SILENT by default to keep your logs clean.
  # Enable only for debugging gem issues or troubleshooting setup.

  # Enable internal logging (default: false - silent)
  config.enable_internal_logging = false

  # Log level (default: :silent)
  # Options: :debug, :info, :warn, :error, :silent
  config.log_level = :silent

  # Example: Enable verbose logging for debugging
  # config.enable_internal_logging = true
  # config.log_level = :debug

  # Example: Log only errors (troubleshooting)
  # config.enable_internal_logging = true
  # config.log_level = :error

  # ============================================================================
  # ADDITIONAL CONFIGURATION
  # ============================================================================

  # Custom severity rules (override automatic severity classification)
  # config.custom_severity_rules = {
  #   "PaymentError" => :critical,
  #   "ValidationError" => :low
  # }

  # Enhanced metrics (optional)
  config.app_version = ENV["APP_VERSION"]
  config.git_sha = ENV["GIT_SHA"]
  # config.total_users_for_impact = 10000  # For user impact % calculation

  # Git repository URL for clickable commit links and issue tracking
  # Examples:
  #   GitHub: "https://github.com/username/repo"
  #   GitLab: "https://gitlab.com/username/repo"
  #   Codeberg: "https://codeberg.org/username/repo"
  # config.git_repository_url = ENV["GIT_REPOSITORY_URL"]

  # ============================================================================
  # AI HELP (OpenAI / Anthropic)
  # ============================================================================
  #
  # When provider and API key are configured, error detail pages show an
  # "AI Help" drawer where dashboard users can ask questions about the current
  # error. Error details, backtrace, and related dashboard context are sent to
  # the configured provider.
  #
  # OpenAI uses the Responses API by default and supports GPT-5 and GPT-4 family
  # models such as "gpt-5" and "gpt-4.1". Set llm_openai_endpoint to
  # :chat_completions only if you need the older Chat Completions endpoint.
  #
  # config.llm_provider = :openai
  # config.llm_api_key = -> { Rails.application.credentials.dig(:openai, :api_key) }
  # config.llm_model = "gpt-5"
  # config.llm_openai_endpoint = :auto # :auto, :responses, or :chat_completions
  #
  # config.llm_provider = :anthropic
  # config.llm_api_key = -> { Rails.application.credentials.dig(:anthropic, :api_key) }
  # config.llm_model = "claude-sonnet-4-20250514"
  #
  # Shared options:
  # config.llm_timeout_seconds = 30
  # config.llm_max_output_tokens = 900
  # config.llm_system_prompt = "Prefer concise answers with file-level next steps."

  # ============================================================================
  # OPENTELEMETRY EXPORT (OUTBOUND)
  # ============================================================================
  #
  # Emit gem operations as OpenTelemetry spans so the host's existing
  # Datadog / Honeycomb / Jaeger / Grafana Tempo pipeline gets a trace
  # of every error capture. Useful for:
  #   - Auditing "when did this error get captured?" against deploy events
  #   - Measuring how much time the gem spends in the capture path
  #   - Proving the <5ms host-safety budget from operator dashboards
  #
  # Emits four spans per error capture:
  #   rails_error_dashboard.capture_error           — parent, wraps everything
  #   rails_error_dashboard.breadcrumb_collection   — buffer drain (~µs)
  #   rails_error_dashboard.system_health_snapshot  — GC.stat etc. (<1ms)
  #   rails_error_dashboard.notification_dispatch   — Slack/email enqueue
  #
  # Disabled by default. Requires the host app to already run OpenTelemetry
  # (the gem does NOT add an opentelemetry-* runtime dependency). When OTel
  # is absent, every span call is a zero-overhead no-op.
  #
  # config.enable_otel_export = true
  # config.otel_service_name = "my-app"  # Falls back to application_name when nil
  #
  # Per-span opt-out: pass any subset to disable individual span kinds
  # without code changes. Useful when e.g. notification dispatch is slow due
  # to outbound HTTP and you don't want it polluting your trace dashboards.
  #
  # config.otel_spans = [:capture, :breadcrumbs, :health, :notifications]  # all (default)
  # config.otel_spans = [:capture]                                          # parent only
  # config.otel_spans = [:capture, :health]                                 # parent + health
  #
  # No PII or request bodies in span attributes — just metadata + timing.
  # Safe to enable on production OTel pipelines.

  # ============================================================================
  # ISSUE TRACKING (GitHub / GitLab / Codeberg / Linear)
  # ============================================================================
  #
  # One switch enables everything: issue creation, auto-create on first
  # occurrence, lifecycle sync (resolve → close, reopen → reopen), platform
  # state mirroring (status, assignees, labels), and comment display.
  #
  # IMPORTANT: When enabled, the dashboard shows platform state instead of
  # internal workflow controls:
  #   - "Mark as Resolved" → replaced by issue open/closed from platform
  #   - Workflow Status → issue state from platform
  #   - Assigned To → assignees from platform (with avatars)
  #   - Priority → labels from platform (with colors)
  #   - Snooze and Mute remain (no platform equivalent)
  #
  # Setup (GitHub/GitLab/Codeberg):
  #   1. Create a RED bot account on GitHub/GitLab/Codeberg
  #   2. Generate a token and set RED_BOT_TOKEN env var
  #   3. Set git_repository_url above (already used for source code linking)
  #   4. Enable:
  #
  # config.enable_issue_tracking = true
  # config.issue_tracker_token = ENV["RED_BOT_TOKEN"]
  #
  # Setup (Linear):
  #   Linear is not a git forge, so it cannot be auto-detected from
  #   git_repository_url — set provider and team key explicitly. Issues are
  #   created in the team matching the key (e.g. "ENG" for ENG-123 issues).
  #   Generate a personal API key under Settings > Security & access.
  #
  # config.enable_issue_tracking = true
  # config.issue_tracker_provider = :linear
  # config.issue_tracker_repo = "ENG"                              # Linear team key
  # config.issue_tracker_token = ENV["RED_BOT_TOKEN"]              # lin_api_... key
  #
  # Optional overrides:
  # config.issue_tracker_labels = ["bug"]                          # Labels added to new issues
  # config.issue_tracker_auto_create_severities = [:critical, :high]  # Auto-create threshold
  # config.issue_webhook_secret = ENV["ISSUE_WEBHOOK_SECRET"]      # Enables two-way webhook sync
end
