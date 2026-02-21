# frozen_string_literal: true

module RailsErrorDashboard
  class Configuration
    # Dashboard authentication (always required)
    attr_accessor :dashboard_username
    attr_accessor :dashboard_password

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

    # Notification callbacks (managed via helper methods, not set directly)
    attr_reader :notification_callbacks

    # Internal logging configuration
    attr_accessor :enable_internal_logging
    attr_accessor :log_level

    def initialize
      # Default values - Authentication is ALWAYS required
      @dashboard_username = ENV.fetch("ERROR_DASHBOARD_USER", "gandalf")
      @dashboard_password = ENV.fetch("ERROR_DASHBOARD_PASSWORD", "youshallnotpass")

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

      # Retention policy - nil means keep forever (no automatic deletion)
      # Users can run 'rails error_dashboard:cleanup_resolved DAYS=90' to manually clean up
      @retention_days = nil

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
    #
    # @raise [ConfigurationError] if configuration is invalid
    # @return [true] if configuration is valid
    def validate!
      errors = []

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

      # Raise exception if any errors found
      raise ConfigurationError, errors if errors.any?

      true
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
