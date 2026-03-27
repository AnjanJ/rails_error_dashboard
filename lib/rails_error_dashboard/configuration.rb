# frozen_string_literal: true

module RailsErrorDashboard
  class Configuration
    # Dashboard authentication (always required)
    attr_accessor :dashboard_username
    attr_accessor :dashboard_password
    attr_accessor :authenticate_with

    # User model (for associations)
    attr_accessor :user_model

    # Multi-app support - Application name
    attr_accessor :application_name
    attr_accessor :database  # Database connection name for shared error dashboard DB

    # Notifications
    attr_accessor :slack_webhook_url
    attr_accessor :notification_email_recipients
    attr_accessor :notification_email_from
    attr_accessor :dashboard_base_url
    attr_accessor :enable_slack_notifications
    attr_accessor :enable_email_notifications

    # Discord notifications
    attr_accessor :discord_webhook_url
    attr_accessor :enable_discord_notifications

    # PagerDuty notifications (critical errors only)
    attr_accessor :pagerduty_integration_key
    attr_accessor :enable_pagerduty_notifications

    # Generic webhook notifications
    attr_accessor :webhook_urls
    attr_accessor :enable_webhook_notifications

    # Separate database configuration
    attr_accessor :use_separate_database

    # Retention policy (days to keep errors)
    attr_accessor :retention_days

    # Enable/disable error catching middleware
    attr_accessor :enable_middleware

    # Enable/disable Rails.error subscriber
    attr_accessor :enable_error_subscriber

    # Advanced configuration options
    # Custom severity classification rules (hash of error_type => severity)
    attr_accessor :custom_severity_rules

    # Exceptions to ignore (array of strings, regexes, or classes)
    attr_accessor :ignored_exceptions

    # Custom fingerprint lambda for error deduplication
    # When set, overrides the default ErrorHashGenerator logic.
    # Receives (exception, context) and must return a String.
    # Example: ->(exception, context) { "#{exception.class.name}:#{context[:controller_name]}" }
    attr_accessor :custom_fingerprint

    # Sampling rate for non-critical errors (0.0 to 1.0, default 1.0 = 100%)
    attr_accessor :sampling_rate

    # Async logging configuration
    attr_accessor :async_logging
    attr_accessor :async_adapter # :sidekiq, :solid_queue, or :async

    # Backtrace configuration
    attr_accessor :max_backtrace_lines

    # Rate limiting configuration
    attr_accessor :enable_rate_limiting
    attr_accessor :rate_limit_per_minute

    # Enhanced metrics
    attr_accessor :app_version
    attr_accessor :git_sha
    attr_accessor :total_users_for_impact # For user impact % calculation

    # Git repository URL for linking commits (e.g., "https://github.com/user/repo")
    attr_accessor :git_repository_url

    # Issue tracker integration (GitHub, GitLab, Codeberg/Gitea/Forgejo)
    attr_accessor :enable_issue_tracking         # Master switch (default: false)
    attr_accessor :issue_tracker_provider         # :github, :gitlab, :codeberg (auto-detected from git_repository_url)
    attr_accessor :issue_tracker_token            # String or lambda/proc for Rails credentials
    attr_accessor :issue_tracker_repo             # "owner/repo" (auto-extracted from git_repository_url)
    attr_accessor :issue_tracker_labels           # Array of label strings (default: ["bug"])
    attr_accessor :issue_tracker_api_url          # Custom API base URL for self-hosted instances
    attr_accessor :auto_create_issues              # Boolean (default: false) — auto-create issues for new errors
    attr_accessor :auto_create_issues_on_first_occurrence  # Boolean (default: true) — create on first occurrence
    attr_accessor :auto_create_issues_for_severities       # Array of symbols (default: [:critical, :high])
    attr_accessor :enable_issue_webhooks            # Boolean (default: false) — receive webhooks for two-way sync
    attr_accessor :issue_webhook_secret             # String — HMAC secret for webhook signature verification

    # Advanced error analysis features
    attr_accessor :enable_similar_errors          # Fuzzy error matching
    attr_accessor :enable_co_occurring_errors     # Detect errors happening together
    attr_accessor :enable_error_cascades          # Parent→child error relationships
    attr_accessor :enable_error_correlation       # Version/user/time correlation
    attr_accessor :enable_platform_comparison     # iOS vs Android analytics
    attr_accessor :enable_occurrence_patterns     # Cyclical/burst pattern detection

    # Baseline alert configuration
    attr_accessor :enable_baseline_alerts
    attr_accessor :baseline_alert_threshold_std_devs # Number of std devs to trigger alert (default: 2.0)
    attr_accessor :baseline_alert_severities # Array of severities to alert on (default: [:critical, :high])
    attr_accessor :baseline_alert_cooldown_minutes # Minutes between alerts for same error type (default: 120)

    # Source code integration (show code in backtrace)
    attr_accessor :enable_source_code_integration  # Master switch (default: false)
    attr_accessor :source_code_context_lines       # Lines before/after (default: 5)
    attr_accessor :enable_git_blame                # Show git blame (default: false)
    attr_accessor :source_code_cache_ttl           # Cache TTL in seconds (default: 3600)
    attr_accessor :only_show_app_code_source       # Hide gems/stdlib (default: true)
    attr_accessor :git_branch_strategy             # :commit_sha, :current_branch, :main (default: :commit_sha)

    # Sensitive data filtering (on by default)
    # Redacts passwords, tokens, credit cards, SSNs, etc. before storage.
    # Uses built-in defaults + Rails' filter_parameters + custom patterns.
    # Set to false if you want raw data stored (you own your database).
    attr_accessor :filter_sensitive_data
    attr_accessor :sensitive_data_patterns # Additional patterns beyond Rails' filter_parameters

    # Notification throttling (prevents alert fatigue)
    attr_accessor :notification_minimum_severity   # Minimum severity to notify (default: :low = notify all)
    attr_accessor :notification_cooldown_minutes    # Per-error cooldown in minutes (default: 5, 0 = disabled)
    attr_accessor :notification_threshold_alerts    # Occurrence milestones that trigger notification (default: [10, 50, 100, 500, 1000])

    # Breadcrumbs (request activity trail)
    attr_accessor :enable_breadcrumbs              # Master switch (default: false)
    attr_accessor :breadcrumb_buffer_size          # Max breadcrumbs per request (default: 40)
    attr_accessor :breadcrumb_categories           # Which categories to capture (default: nil = all)

    # N+1 query detection (display-time analysis of SQL breadcrumbs)
    attr_accessor :enable_n_plus_one_detection     # Master switch (default: true)
    attr_accessor :n_plus_one_threshold            # Min repetitions to flag (default: 3, min: 2)

    # System health snapshot (GC, memory, threads, connection pool at error time)
    attr_accessor :enable_system_health            # Master switch (default: false)

    # Local variable capture via TracePoint(:raise)
    attr_accessor :enable_local_variables            # Master switch (default: false)
    attr_accessor :local_variable_max_count           # Max variables to capture (default: 15)
    attr_accessor :local_variable_max_depth           # Max object nesting depth (default: 3)
    attr_accessor :local_variable_max_string_length   # Max string value length (default: 200)
    attr_accessor :local_variable_max_array_items     # Max array items to serialize (default: 10)
    attr_accessor :local_variable_max_hash_items      # Max hash entries to serialize (default: 20)
    attr_accessor :local_variable_filter_patterns     # Additional sensitive name patterns (default: [])

    # Instance variable capture from tp.self (receiver object at raise time)
    attr_accessor :enable_instance_variables           # Master switch (default: false)
    attr_accessor :instance_variable_max_count          # Max ivars to capture (default: 20)
    attr_accessor :instance_variable_filter_patterns    # Additional sensitive ivar patterns (default: [])

    # Swallowed exception detection via TracePoint(:raise) + TracePoint(:rescue) (Ruby 3.3+ only)
    attr_accessor :detect_swallowed_exceptions          # Master switch (default: false)
    attr_accessor :swallowed_exception_max_cache_size   # Max entries per thread (default: 1000)
    attr_accessor :swallowed_exception_flush_interval   # Seconds between flushes (default: 60)
    attr_accessor :swallowed_exception_threshold        # Rescue ratio to flag (default: 0.95)
    attr_accessor :swallowed_exception_ignore_classes   # Additional exception classes to skip (default: [])

    # Process crash capture via at_exit hook
    attr_accessor :enable_crash_capture                 # Master switch (default: false)
    attr_accessor :crash_capture_path                   # Directory for crash files (default: Dir.tmpdir)

    # On-demand diagnostic dump (rake task + dashboard endpoint)
    attr_accessor :enable_diagnostic_dump               # Master switch (default: false)

    # Rack Attack event tracking (requires enable_breadcrumbs = true)
    attr_accessor :enable_rack_attack_tracking          # Master switch (default: false)

    # ActionCable event tracking (requires enable_breadcrumbs = true)
    attr_accessor :enable_actioncable_tracking          # Master switch (default: false)
    # ActiveStorage event tracking (requires enable_breadcrumbs = true)
    attr_accessor :enable_activestorage_tracking        # Master switch (default: false)

    # Notification callbacks (managed via helper methods, not set directly)
    attr_reader :notification_callbacks

    # Internal logging configuration
    attr_accessor :enable_internal_logging
    attr_accessor :log_level

    def initialize
      # Default values - Authentication is ALWAYS required
      @dashboard_username = ENV.fetch("ERROR_DASHBOARD_USER", "gandalf")
      @dashboard_password = ENV.fetch("ERROR_DASHBOARD_PASSWORD", "youshallnotpass")
      @authenticate_with = nil

      @user_model = nil  # Auto-detect if not set

      # Multi-app support defaults
      @application_name = ENV["APPLICATION_NAME"]  # Auto-detected if not set
      @database = nil  # Use primary database by default

      # Notification settings (disabled by default - enable during installation or in initializer)
      @slack_webhook_url = ENV["SLACK_WEBHOOK_URL"]
      @notification_email_recipients = ENV.fetch("ERROR_NOTIFICATION_EMAILS", "").split(",").map(&:strip)
      @notification_email_from = ENV.fetch("ERROR_NOTIFICATION_FROM", "errors@example.com")
      @dashboard_base_url = ENV["DASHBOARD_BASE_URL"]
      @enable_slack_notifications = false
      @enable_email_notifications = false

      # Discord notification settings
      @discord_webhook_url = ENV["DISCORD_WEBHOOK_URL"]
      @enable_discord_notifications = false

      # PagerDuty notification settings (critical errors only)
      @pagerduty_integration_key = ENV["PAGERDUTY_INTEGRATION_KEY"]
      @enable_pagerduty_notifications = false

      # Generic webhook settings (array of URLs)
      @webhook_urls = ENV.fetch("WEBHOOK_URLS", "").split(",").map(&:strip).reject(&:empty?)
      @enable_webhook_notifications = false

      @use_separate_database = ENV.fetch("USE_SEPARATE_ERROR_DB", "false") == "true"

      # Retention policy - days to keep errors before automatic deletion (default: 90)
      # Set to nil to keep errors forever (not recommended for production)
      # Schedule cleanup: RailsErrorDashboard::RetentionCleanupJob.perform_later
      @retention_days = 90

      @enable_middleware = true
      @enable_error_subscriber = true

      # Advanced configuration defaults
      @custom_severity_rules = {}
      @ignored_exceptions = []
      @custom_fingerprint = nil # Lambda: ->(exception, context) { "custom_key" }
      @sampling_rate = 1.0 # 100% by default
      @async_logging = false
      @async_adapter = :sidekiq # Battle-tested default
      @max_backtrace_lines = 100 # Matches industry standard (Rollbar, Airbrake)

      # Rate limiting defaults
      @enable_rate_limiting = false # OFF by default (opt-in)
      @rate_limit_per_minute = 100  # Requests per minute per IP for API endpoints

      # Enhanced metrics defaults
      @app_version = ENV["APP_VERSION"]
      @git_sha = ENV["GIT_SHA"]
      @total_users_for_impact = nil # Auto-detect if not set
      @git_repository_url = ENV["GIT_REPOSITORY_URL"]

      # Issue tracker integration defaults — OFF by default
      @enable_issue_tracking = false
      @issue_tracker_provider = nil    # Auto-detect from git_repository_url
      @issue_tracker_token = ENV["ISSUE_TRACKER_TOKEN"]
      @issue_tracker_repo = nil        # Auto-extract from git_repository_url
      @issue_tracker_labels = [ "bug" ]
      @issue_tracker_api_url = nil     # For self-hosted instances
      @auto_create_issues = false
      @auto_create_issues_on_first_occurrence = true
      @auto_create_issues_for_severities = [ :critical, :high ]
      @enable_issue_webhooks = false
      @issue_webhook_secret = ENV["ISSUE_WEBHOOK_SECRET"]

      # Advanced error analysis features (all OFF by default - opt-in)
      @enable_similar_errors = false        # Fuzzy error matching
      @enable_co_occurring_errors = false   # Co-occurring error detection
      @enable_error_cascades = false        # Error cascade detection
      @enable_error_correlation = false     # Version/user/time correlation
      @enable_platform_comparison = false   # Platform health comparison
      @enable_occurrence_patterns = false   # Pattern detection

      # Baseline alert defaults
      @enable_baseline_alerts = false  # OFF by default (opt-in)
      @baseline_alert_threshold_std_devs = ENV.fetch("BASELINE_ALERT_THRESHOLD", "2.0").to_f
      @baseline_alert_severities = [ :critical, :high ] # Alert on critical and high severity anomalies
      @baseline_alert_cooldown_minutes = ENV.fetch("BASELINE_ALERT_COOLDOWN", "120").to_i

      # Source code integration defaults - OFF by default (opt-in)
      @enable_source_code_integration = false  # Master switch
      @source_code_context_lines = 5  # Show ±5 lines around target line
      @enable_git_blame = false  # Show git blame info
      @source_code_cache_ttl = 3600  # 1 hour cache
      @only_show_app_code_source = true  # Hide gem/vendor code for security
      @git_branch_strategy = :commit_sha  # Use error's git_sha (most accurate)

      # Sensitive data filtering defaults - ON by default (filters passwords, tokens, credit cards, etc.)
      @filter_sensitive_data = true
      @sensitive_data_patterns = []

      # Notification throttling defaults
      @notification_minimum_severity = :low  # Notify on all severities (current behavior)
      @notification_cooldown_minutes = 5     # 5 min cooldown per error_hash (0 = disabled)
      @notification_threshold_alerts = [ 10, 50, 100, 500, 1000 ] # Occurrence milestones

      # Breadcrumbs defaults - OFF by default (opt-in)
      @enable_breadcrumbs = false         # Master switch
      @breadcrumb_buffer_size = 40        # Max events per request (Sentry uses 100, we're conservative)
      @breadcrumb_categories = nil        # nil = all; or [:sql, :controller, :cache, :job, :mailer, :custom, :deprecation]

      # N+1 query detection defaults - ON by default (lightweight display-time analysis)
      @enable_n_plus_one_detection = true  # Analyze SQL breadcrumbs for repeated patterns
      @n_plus_one_threshold = 3            # Flag when same query shape appears 3+ times

      # System health snapshot defaults - OFF by default (opt-in)
      @enable_system_health = false  # Capture GC, memory, threads, connection pool at error time

      # Local variable capture defaults - OFF by default (opt-in)
      @enable_local_variables = false           # TracePoint(:raise) for local var capture
      @local_variable_max_count = 15            # Max variables per exception
      @local_variable_max_depth = 3             # Max nesting depth for objects
      @local_variable_max_string_length = 200   # Truncate strings beyond this
      @local_variable_max_array_items = 10      # Max array items to serialize
      @local_variable_max_hash_items = 20       # Max hash entries to serialize
      @local_variable_filter_patterns = []      # Additional sensitive variable name patterns

      # Instance variable capture defaults - OFF by default (opt-in)
      @enable_instance_variables = false         # Capture ivars from tp.self at raise time
      @instance_variable_max_count = 20          # Max ivars per exception
      @instance_variable_filter_patterns = []    # Additional sensitive ivar name patterns

      # Swallowed exception detection defaults - OFF by default (Ruby 3.3+ opt-in)
      @detect_swallowed_exceptions = false       # TracePoint(:raise) + TracePoint(:rescue)
      @swallowed_exception_max_cache_size = 1000 # Max entries per thread-local hash
      @swallowed_exception_flush_interval = 60   # Seconds between DB flushes
      @swallowed_exception_threshold = 0.95      # Rescue ratio to flag as swallowed
      @swallowed_exception_ignore_classes = []   # Additional exception classes to skip

      # Process crash capture defaults - OFF by default (opt-in)
      @enable_crash_capture = false     # at_exit hook for fatal crash capture
      @crash_capture_path = nil         # nil = Dir.tmpdir

      # Diagnostic dump defaults - OFF by default (opt-in)
      @enable_diagnostic_dump = false   # On-demand system state snapshot

      # Rack Attack event tracking defaults - OFF by default (opt-in, requires breadcrumbs)
      @enable_rack_attack_tracking = false

      # ActionCable event tracking defaults - OFF by default (opt-in, requires breadcrumbs)
      @enable_actioncable_tracking = false
      # ActiveStorage event tracking defaults - OFF by default (opt-in, requires breadcrumbs)
      @enable_activestorage_tracking = false

      # Internal logging defaults - SILENT by default
      @enable_internal_logging = false  # Opt-in for debugging
      @log_level = :silent  # Silent by default, use :debug, :info, :warn, :error, or :silent

      @notification_callbacks = {
        error_logged: [],
        critical_error: [],
        error_resolved: []
      }
    end

    # Reset configuration to defaults
    def reset!
      initialize
    end

    # Validate configuration values
    # Raises ConfigurationError if any validation fails
    # Logs warnings for non-fatal issues (e.g., Ruby version incompatibilities)
    #
    # @raise [ConfigurationError] if configuration is invalid
    # @return [true] if configuration is valid
    def validate!
      errors = []
      warnings = []

      # Block boot with default or blank credentials in production
      # Skip during asset precompilation (SECRET_KEY_BASE_DUMMY=1) — ENV vars aren't available at build time
      if default_credentials? &&
         defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production? &&
         ENV["SECRET_KEY_BASE_DUMMY"].blank?
        errors << "Default or blank credentials cannot be used in production. Set ERROR_DASHBOARD_USER and ERROR_DASHBOARD_PASSWORD environment variables, or use authenticate_with for custom auth."
      end

      # Validate sampling_rate (must be between 0.0 and 1.0)
      if sampling_rate && (sampling_rate < 0.0 || sampling_rate > 1.0)
        errors << "sampling_rate must be between 0.0 and 1.0 (got: #{sampling_rate})"
      end

      # Validate retention_days (must be positive)
      if retention_days && retention_days < 1
        errors << "retention_days must be at least 1 day (got: #{retention_days})"
      end

      # Validate max_backtrace_lines (must be positive)
      if max_backtrace_lines && max_backtrace_lines < 1
        errors << "max_backtrace_lines must be at least 1 (got: #{max_backtrace_lines})"
      end

      # Validate rate_limit_per_minute (must be positive if rate limiting enabled)
      if enable_rate_limiting && rate_limit_per_minute && rate_limit_per_minute < 1
        errors << "rate_limit_per_minute must be at least 1 (got: #{rate_limit_per_minute})"
      end

      # Validate baseline alert threshold (must be positive)
      if enable_baseline_alerts && baseline_alert_threshold_std_devs && baseline_alert_threshold_std_devs <= 0
        errors << "baseline_alert_threshold_std_devs must be positive (got: #{baseline_alert_threshold_std_devs})"
      end

      # Validate baseline alert cooldown (must be positive)
      if enable_baseline_alerts && baseline_alert_cooldown_minutes && baseline_alert_cooldown_minutes < 1
        errors << "baseline_alert_cooldown_minutes must be at least 1 (got: #{baseline_alert_cooldown_minutes})"
      end

      # Validate baseline alert severities (must be valid symbols)
      if enable_baseline_alerts && baseline_alert_severities
        valid_severities = %i[critical high medium low]
        invalid_severities = baseline_alert_severities - valid_severities
        if invalid_severities.any?
          errors << "baseline_alert_severities contains invalid values: #{invalid_severities.inspect}. " \
                    "Valid options: #{valid_severities.inspect}"
        end
      end

      # Validate async_adapter (must be valid adapter)
      if async_logging && async_adapter
        valid_adapters = %i[sidekiq solid_queue async]
        unless valid_adapters.include?(async_adapter)
          errors << "async_adapter must be one of #{valid_adapters.inspect} (got: #{async_adapter.inspect})"
        end
      end

      # Validate custom_fingerprint (must respond to .call if set)
      if custom_fingerprint && !custom_fingerprint.respond_to?(:call)
        errors << "custom_fingerprint must respond to .call (lambda, proc, or object with .call method)"
      end

      # Validate authenticate_with (must respond to .call if set)
      if authenticate_with && !authenticate_with.respond_to?(:call)
        errors << "authenticate_with must respond to .call (lambda, proc, or object with .call method)"
      end

      # Validate breadcrumb_buffer_size (must be positive if breadcrumbs enabled)
      if enable_breadcrumbs && breadcrumb_buffer_size && breadcrumb_buffer_size < 1
        errors << "breadcrumb_buffer_size must be at least 1 (got: #{breadcrumb_buffer_size})"
      end

      # Validate n_plus_one_threshold (must be at least 2 if detection enabled)
      if enable_n_plus_one_detection && n_plus_one_threshold && n_plus_one_threshold < 2
        errors << "n_plus_one_threshold must be at least 2 (got: #{n_plus_one_threshold})"
      end

      # Validate local variable capture settings
      if enable_local_variables
        if local_variable_max_count && local_variable_max_count < 1
          errors << "local_variable_max_count must be at least 1 (got: #{local_variable_max_count})"
        end
        if local_variable_max_depth && local_variable_max_depth < 1
          errors << "local_variable_max_depth must be at least 1 (got: #{local_variable_max_depth})"
        end
        if local_variable_max_string_length && local_variable_max_string_length < 1
          errors << "local_variable_max_string_length must be at least 1 (got: #{local_variable_max_string_length})"
        end
      end

      # Validate instance variable capture settings
      if enable_instance_variables && instance_variable_max_count && instance_variable_max_count < 1
        errors << "instance_variable_max_count must be at least 1 (got: #{instance_variable_max_count})"
      end

      # Validate swallowed exception detection settings
      # Auto-disable on Ruby < 3.3 (warn, don't crash)
      if detect_swallowed_exceptions && RUBY_VERSION < "3.3"
        warnings << "detect_swallowed_exceptions requires Ruby 3.3+ (current: #{RUBY_VERSION}). " \
                    "TracePoint(:rescue) was added in Ruby 3.3 (Feature #19572). " \
                    "Feature has been auto-disabled. Upgrade Ruby to use this feature."
        @detect_swallowed_exceptions = false
      end
      # Validate sub-settings only if feature is still active after version check
      if detect_swallowed_exceptions
        if swallowed_exception_max_cache_size && swallowed_exception_max_cache_size < 1
          errors << "swallowed_exception_max_cache_size must be at least 1 (got: #{swallowed_exception_max_cache_size})"
        end
        if swallowed_exception_flush_interval && swallowed_exception_flush_interval < 1
          errors << "swallowed_exception_flush_interval must be at least 1 (got: #{swallowed_exception_flush_interval})"
        end
        if swallowed_exception_threshold && (swallowed_exception_threshold < 0.0 || swallowed_exception_threshold > 1.0)
          errors << "swallowed_exception_threshold must be between 0.0 and 1.0 (got: #{swallowed_exception_threshold})"
        end
      end

      # Validate rack_attack tracking requires breadcrumbs
      if enable_rack_attack_tracking && !enable_breadcrumbs
        warnings << "enable_rack_attack_tracking requires enable_breadcrumbs = true. " \
                    "Rack Attack tracking has been auto-disabled."
        @enable_rack_attack_tracking = false
      end

      # Validate actioncable tracking requires breadcrumbs
      if enable_actioncable_tracking && !enable_breadcrumbs
        warnings << "enable_actioncable_tracking requires enable_breadcrumbs = true. " \
                    "ActionCable tracking has been auto-disabled."
        @enable_actioncable_tracking = false
      end

      # Validate activestorage tracking requires breadcrumbs
      if enable_activestorage_tracking && !enable_breadcrumbs
        warnings << "enable_activestorage_tracking requires enable_breadcrumbs = true. " \
                    "ActiveStorage tracking has been auto-disabled."
        @enable_activestorage_tracking = false
      end

      # Validate issue tracking configuration
      if enable_issue_tracking && effective_issue_tracker_token.blank?
        warnings << "enable_issue_tracking is true but no token configured. " \
                    "Set issue_tracker_token or RED_BOT_TOKEN env var. " \
                    "Tip: Create a dedicated RED (Rails Error Dashboard) bot account on your platform."
      end

      if enable_issue_tracking && effective_issue_tracker_provider.nil?
        warnings << "enable_issue_tracking is true but provider could not be detected. " \
                    "Set issue_tracker_provider or git_repository_url."
      end

      # Validate crash capture path (must exist if custom path specified)
      if enable_crash_capture && crash_capture_path
        unless Dir.exist?(crash_capture_path)
          errors << "crash_capture_path '#{crash_capture_path}' does not exist"
        end
      end

      # Validate notification dependencies
      if enable_slack_notifications && (slack_webhook_url.nil? || slack_webhook_url.strip.empty?)
        errors << "slack_webhook_url is required when enable_slack_notifications is true"
      end

      if enable_email_notifications && notification_email_recipients.empty?
        errors << "notification_email_recipients is required when enable_email_notifications is true"
      end

      if enable_discord_notifications && (discord_webhook_url.nil? || discord_webhook_url.strip.empty?)
        errors << "discord_webhook_url is required when enable_discord_notifications is true"
      end

      if enable_pagerduty_notifications && (pagerduty_integration_key.nil? || pagerduty_integration_key.strip.empty?)
        errors << "pagerduty_integration_key is required when enable_pagerduty_notifications is true"
      end

      if enable_webhook_notifications && webhook_urls.empty?
        errors << "webhook_urls is required when enable_webhook_notifications is true"
      end

      # Validate separate database configuration
      if use_separate_database && (database.nil? || database.to_s.strip.empty?)
        errors << "database configuration is required when use_separate_database is true"
      end

      # Validate log level (must be valid symbol)
      if log_level
        valid_log_levels = %i[debug info warn error fatal silent]
        unless valid_log_levels.include?(log_level)
          errors << "log_level must be one of #{valid_log_levels.inspect} (got: #{log_level.inspect})"
        end
      end

      # Validate total_users_for_impact (must be positive if set)
      if total_users_for_impact && total_users_for_impact < 1
        errors << "total_users_for_impact must be at least 1 (got: #{total_users_for_impact})"
      end

      # Validate notification_minimum_severity (must be valid symbol)
      if notification_minimum_severity
        valid_notification_severities = %i[critical high medium low]
        unless valid_notification_severities.include?(notification_minimum_severity)
          errors << "notification_minimum_severity must be one of #{valid_notification_severities.inspect} " \
                    "(got: #{notification_minimum_severity.inspect})"
        end
      end

      # Validate notification_cooldown_minutes (must be non-negative if set)
      if notification_cooldown_minutes && notification_cooldown_minutes < 0
        errors << "notification_cooldown_minutes must be 0 or greater (got: #{notification_cooldown_minutes})"
      end

      # Validate notification_threshold_alerts (must be array of positive integers if set)
      if notification_threshold_alerts && !notification_threshold_alerts.is_a?(Array)
        errors << "notification_threshold_alerts must be an Array (got: #{notification_threshold_alerts.class})"
      end

      # Log warnings (non-fatal issues)
      warnings.each do |warning|
        Rails.logger.warn "[Rails Error Dashboard] #{warning}" if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
      end

      # Raise exception if any errors found
      raise ConfigurationError, errors if errors.any?

      true
    end

    # Check if using default or blank demo credentials with basic auth
    #
    # Returns false if the user explicitly set ENV vars (even to the same default values),
    # because that's a deliberate choice. Only blocks when credentials are untouched defaults
    # or blank.
    #
    # @return [Boolean] true if basic auth is active with untouched default or blank credentials
    def default_credentials?
      return false unless authenticate_with.nil?

      # If user explicitly set ENV vars, respect their choice
      return false if ENV.key?("ERROR_DASHBOARD_USER") || ENV.key?("ERROR_DASHBOARD_PASSWORD")

      default = dashboard_username == "gandalf" && dashboard_password == "youshallnotpass"
      blank = dashboard_username.to_s.strip.empty? || dashboard_password.to_s.strip.empty?

      default || blank
    end

    # Resolve the effective issue tracker provider (auto-detect from git_repository_url)
    #
    # @return [Symbol, nil] :github, :gitlab, :codeberg, or nil
    def effective_issue_tracker_provider
      return issue_tracker_provider&.to_sym if issue_tracker_provider.present?
      return nil if git_repository_url.blank?

      case git_repository_url
      when /github\.com/i then :github
      when /gitlab\.com/i then :gitlab
      when /codeberg\.org/i then :codeberg
      when /gitea\./i, /forgejo\./i then :codeberg # Gitea/Forgejo instances use same API
      end
    end

    # Resolve the effective issue tracker repository ("owner/repo")
    #
    # @return [String, nil] "owner/repo" or nil
    def effective_issue_tracker_repo
      return issue_tracker_repo if issue_tracker_repo.present?
      return nil if git_repository_url.blank?

      # Extract owner/repo from URL: https://github.com/owner/repo(.git)
      match = git_repository_url.match(%r{[:/]([^/]+/[^/]+?)(?:\.git)?$})
      match&.[](1)
    end

    # Resolve the issue tracker API token (supports string or lambda)
    #
    # @return [String, nil] The resolved token value
    def effective_issue_tracker_token
      return nil if issue_tracker_token.nil?
      issue_tracker_token.respond_to?(:call) ? issue_tracker_token.call : issue_tracker_token
    rescue => e
      nil
    end

    # Resolve the effective API base URL for the issue tracker
    #
    # @return [String] API base URL
    def effective_issue_tracker_api_url
      return issue_tracker_api_url if issue_tracker_api_url.present?

      case effective_issue_tracker_provider
      when :github then "https://api.github.com"
      when :gitlab then "https://gitlab.com/api/v4"
      when :codeberg then "https://codeberg.org/api/v1"
      end
    end

    # Get the effective user model (auto-detected if not configured)
    #
    # @return [String, nil] User model class name
    def effective_user_model
      return @user_model if @user_model.present?

      RailsErrorDashboard::Helpers::UserModelDetector.detect_user_model
    end

    # Get the effective total users count (auto-detected if not configured)
    # Caches the result for 5 minutes to avoid repeated queries
    #
    # @return [Integer, nil] Total users count
    def effective_total_users
      return @total_users_for_impact if @total_users_for_impact.present?

      # Cache auto-detected value for 5 minutes
      @total_users_cache ||= {}
      cache_key = :auto_detected_count
      cached_at = @total_users_cache[:cached_at]

      if cached_at && (Time.current - cached_at) < 300 # 5 minutes
        return @total_users_cache[cache_key]
      end

      count = RailsErrorDashboard::Helpers::UserModelDetector.detect_total_users

      @total_users_cache[cache_key] = count
      @total_users_cache[:cached_at] = Time.current

      count
    end

    # Clear the total users cache
    def clear_total_users_cache!
      @total_users_cache = {}
    end
  end
end
