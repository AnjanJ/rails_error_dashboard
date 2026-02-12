# frozen_string_literal: true

module RailsErrorDashboard
  class ErrorLog < ErrorLogsRecord
    self.table_name = "rails_error_dashboard_error_logs"

    # Priority level constants
    # Using industry standard: P0 = Critical (highest), P3 = Low (lowest)
    PRIORITY_LEVELS = {
      3 => { label: "Critical", short_label: "P0", color: "danger", emoji: "🔴" },
      2 => { label: "High", short_label: "P1", color: "warning", emoji: "🟠" },
      1 => { label: "Medium", short_label: "P2", color: "info", emoji: "🟡" },
      0 => { label: "Low", short_label: "P3", color: "secondary", emoji: "⚪" }
    }.freeze

    # Application association
    belongs_to :application, optional: false

    # User association - works with both single and separate database
    # When using separate database, joins are not possible, but Rails
    # will automatically fetch users in a separate query when using includes()
    # Only define association if User model exists
    if defined?(::User)
      belongs_to :user, optional: true
    end

    # Association for tracking individual error occurrences
    has_many :error_occurrences, class_name: "RailsErrorDashboard::ErrorOccurrence", dependent: :destroy

    # Association for comment threads (Phase 3: Workflow Integration)
    has_many :comments, class_name: "RailsErrorDashboard::ErrorComment", foreign_key: :error_log_id, dependent: :destroy

    # Cascade pattern associations
    # parent_cascade_patterns: patterns where this error is the CHILD (errors that cause this error)
    has_many :parent_cascade_patterns, class_name: "RailsErrorDashboard::CascadePattern",
             foreign_key: :child_error_id, dependent: :destroy
    # child_cascade_patterns: patterns where this error is the PARENT (errors this error causes)
    has_many :child_cascade_patterns, class_name: "RailsErrorDashboard::CascadePattern",
             foreign_key: :parent_error_id, dependent: :destroy
    has_many :cascade_parents, through: :parent_cascade_patterns, source: :parent_error
    has_many :cascade_children, through: :child_cascade_patterns, source: :child_error

    validates :error_type, presence: true
    validates :message, presence: true
    validates :occurred_at, presence: true

    scope :unresolved, -> { where(resolved: false) }
    scope :resolved, -> { where(resolved: true) }
    scope :recent, -> { order(occurred_at: :desc) }
    scope :by_error_type, ->(type) { where(error_type: type) }
    scope :by_type, ->(type) { where(error_type: type) }
    scope :by_platform, ->(platform) { where(platform: platform) }
    scope :last_24_hours, -> { where("occurred_at >= ?", 24.hours.ago) }
    scope :last_week, -> { where("occurred_at >= ?", 1.week.ago) }

    # Phase 3: Workflow Integration scopes
    scope :active, -> { where("snoozed_until IS NULL OR snoozed_until < ?", Time.current) }
    scope :snoozed, -> { where("snoozed_until IS NOT NULL AND snoozed_until >= ?", Time.current) }
    scope :by_status, ->(status) { where(status: status) }
    scope :assigned, -> { where.not(assigned_to: nil) }
    scope :unassigned, -> { where(assigned_to: nil) }
    scope :by_assignee, ->(name) { where(assigned_to: name) }
    scope :by_priority, ->(level) { where(priority_level: level) }

    # Set defaults and tracking
    before_validation :set_defaults, on: :create
    before_create :set_tracking_fields
    before_create :set_release_info
    before_create :set_priority_score

    # Turbo Stream broadcasting
    after_create_commit :broadcast_new_error
    after_update_commit :broadcast_error_update

    # Cache invalidation - clear analytics caches when errors are created/updated/deleted
    after_save :clear_analytics_cache
    after_destroy :clear_analytics_cache

    def set_defaults
      self.platform ||= "API"
    end

    def set_tracking_fields
      self.error_hash ||= generate_error_hash
      self.first_seen_at ||= Time.current
      self.last_seen_at ||= Time.current
      self.occurrence_count ||= 1
    end

    def set_release_info
      return unless respond_to?(:app_version=)
      self.app_version ||= fetch_app_version
      self.git_sha ||= fetch_git_sha
    end

    def set_priority_score
      return unless respond_to?(:priority_score=)
      self.priority_score = Services::PriorityScoreCalculator.compute(self)
    end

    # Generate unique hash for error grouping — delegates to ErrorHashGenerator Service
    def generate_error_hash
      Services::ErrorHashGenerator.from_attributes(
        error_type: error_type,
        message: message,
        backtrace: backtrace,
        controller_name: controller_name,
        action_name: action_name,
        application_id: application_id
      )
    end

    # Check if this is a critical error — delegates to SeverityClassifier
    def critical?
      Services::SeverityClassifier.critical?(error_type)
    end

    # Check if error is recent (< 1 hour)
    def recent?
      occurred_at >= 1.hour.ago
    end

    # Check if error is old unresolved (> 7 days)
    def stale?
      !resolved? && occurred_at < 7.days.ago
    end

    # Get severity level — delegates to SeverityClassifier
    def severity
      Services::SeverityClassifier.classify(error_type)
    end

    # Find existing error by hash or create new one — delegates to Command
    def self.find_or_increment_by_hash(error_hash, attributes = {})
      Commands::FindOrIncrementError.call(error_hash, attributes)
    end

    # Log an error with context (delegates to Command)
    def self.log_error(exception, context = {})
      Commands::LogError.call(exception, context)
    end

    # Mark error as resolved (delegates to Command)
    def resolve!(resolution_data = {})
      Commands::ResolveError.call(id, resolution_data)
    end

    # Phase 3: Workflow Integration methods

    # Assignment query
    def assigned?
      assigned_to.present?
    end

    # Snooze query
    def snoozed?
      snoozed_until.present? && snoozed_until >= Time.current
    end

    # Priority methods
    def priority_label
      priority_data = PRIORITY_LEVELS[priority_level]
      return "Unset" unless priority_data

      "#{priority_data[:label]} (#{priority_data[:short_label]})"
    end

    def priority_color
      priority_data = PRIORITY_LEVELS[priority_level]
      return "light" unless priority_data

      priority_data[:color]
    end

    def priority_emoji
      priority_data = PRIORITY_LEVELS[priority_level]
      return "" unless priority_data

      priority_data[:emoji]
    end

    # Class method to get priority options for select dropdowns
    def self.priority_options(include_emoji: false)
      PRIORITY_LEVELS.sort_by { |level, _| -level }.map do |level, data|
        label = if include_emoji
          "#{data[:emoji]} #{data[:label]} (#{data[:short_label]})"
        else
          "#{data[:label]} (#{data[:short_label]})"
        end
        [ label, level ]
      end
    end

    def calculate_priority
      # Automatic priority calculation based on severity and frequency
      severity_weight = case severity
      when :critical then 3
      when :high then 2
      when :medium then 1
      else 0
      end

      frequency_weight = if occurrence_count >= 100
        3
      elsif occurrence_count >= 10
        2
      elsif occurrence_count >= 5
        1
      else
        0
      end

      # Take the higher of severity or frequency
      [ severity_weight, frequency_weight ].max
    end

    # Status transition methods
    def status_badge_color
      case status
      when "new" then "primary"
      when "in_progress" then "info"
      when "investigating" then "warning"
      when "resolved" then "success"
      when "wont_fix" then "secondary"
      else "light"
      end
    end

    def can_transition_to?(new_status)
      # Define valid status transitions
      valid_transitions = {
        "new" => [ "in_progress", "investigating", "wont_fix" ],
        "in_progress" => [ "investigating", "resolved", "new" ],
        "investigating" => [ "resolved", "in_progress", "wont_fix" ],
        "resolved" => [ "new" ], # Can reopen if error recurs
        "wont_fix" => [ "new" ]  # Can reopen
      }

      valid_transitions[status]&.include?(new_status) || false
    end

    # Get error statistics
    def self.statistics(days = 7)
      start_date = days.days.ago

      {
        total: where("occurred_at >= ?", start_date).count,
        unresolved: where("occurred_at >= ?", start_date).unresolved.count,
        by_type: where("occurred_at >= ?", start_date)
          .group(:error_type)
          .count
          .sort_by { |_, count| -count }
          .to_h,
        by_day: where("occurred_at >= ?", start_date)
          .group("DATE(occurred_at)")
          .count
      }
    end

    # Find related errors of the same type
    def related_errors(limit: 5, application_id: nil)
      scope = self.class.where(error_type: error_type)
              .where.not(id: id)
      scope = scope.where(application_id: application_id) if application_id.present?
      scope.order(occurred_at: :desc).limit(limit)
    end

    # Extract backtrace frames for similarity comparison
    def backtrace_frames
      return [] if backtrace.blank?

      # Handle different backtrace formats
      lines = if backtrace.is_a?(Array)
        backtrace
      elsif backtrace.is_a?(String)
        # Check if it's a serialized array (starts with "[")
        if backtrace.strip.start_with?("[")
          # Try to parse as JSON array
          begin
            JSON.parse(backtrace)
          rescue JSON::ParserError
            # Fall back to newline split
            backtrace.split("\n")
          end
        else
          backtrace.split("\n")
        end
      else
        []
      end

      lines.first(20).map do |line|
        # Extract file path and method name, ignore line numbers
        if line =~ %r{([^/]+\.rb):.*?in `(.+)'$}
          "#{Regexp.last_match(1)}:#{Regexp.last_match(2)}"
        elsif line =~ %r{([^/]+\.rb)}
          Regexp.last_match(1)
        end
      end.compact.uniq
    end

    # Calculate backtrace signature — delegates to Service
    def calculate_backtrace_signature
      Services::BacktraceProcessor.calculate_signature(backtrace)
    end

    # Find similar errors using fuzzy matching
    # @param threshold [Float] Minimum similarity score (0.0-1.0), default 0.6
    # @param limit [Integer] Maximum results, default 10
    # @return [Array<Hash>] Array of {error: ErrorLog, similarity: Float}
    def similar_errors(threshold: 0.6, limit: 10)
      return [] unless persisted?
      return [] unless RailsErrorDashboard.configuration.enable_similar_errors
      Queries::SimilarErrors.call(id, threshold: threshold, limit: limit)
    end

    # Find errors that occur together in time
    # @param window_minutes [Integer] Time window in minutes (default: 5)
    # @param min_frequency [Integer] Minimum co-occurrence count (default: 2)
    # @param limit [Integer] Maximum results (default: 10)
    # @return [Array<Hash>] Array of {error: ErrorLog, frequency: Integer, avg_delay_seconds: Float}
    def co_occurring_errors(window_minutes: 5, min_frequency: 2, limit: 10)
      return [] unless persisted?
      return [] unless RailsErrorDashboard.configuration.enable_co_occurring_errors
      return [] unless defined?(Queries::CoOccurringErrors)

      Queries::CoOccurringErrors.call(
        error_log_id: id,
        window_minutes: window_minutes,
        min_frequency: min_frequency,
        limit: limit
      )
    end

    # Find cascade patterns (what causes this error, what this error causes)
    # @param min_probability [Float] Minimum cascade probability (0.0-1.0), default 0.5
    # @return [Hash] {parents: Array, children: Array} of cascade patterns
    def error_cascades(min_probability: 0.5)
      return { parents: [], children: [] } unless persisted?
      return { parents: [], children: [] } unless RailsErrorDashboard.configuration.enable_error_cascades
      return { parents: [], children: [] } unless defined?(Queries::ErrorCascades)

      Queries::ErrorCascades.call(error_id: id, min_probability: min_probability)
    end

    # Get baseline statistics for this error type
    # @return [Hash] {hourly: ErrorBaseline, daily: ErrorBaseline, weekly: ErrorBaseline}
    def baselines
      return {} unless RailsErrorDashboard.configuration.enable_baseline_alerts
      return {} unless defined?(Queries::BaselineStats)

      Queries::BaselineStats.new(error_type, platform).all_baselines
    end

    # Check if this error is anomalous compared to baseline
    # @param sensitivity [Integer] Standard deviations threshold (default: 2)
    # @return [Hash] Anomaly check result
    def baseline_anomaly(sensitivity: 2)
      return { anomaly: false, message: "Feature disabled" } unless RailsErrorDashboard.configuration.enable_baseline_alerts
      return { anomaly: false, message: "No baseline available" } unless defined?(Queries::BaselineStats)

      # Get count of this error type today
      today_count = ErrorLog.where(
        error_type: error_type,
        platform: platform
      ).where("occurred_at >= ?", Time.current.beginning_of_day).count

      Queries::BaselineStats.new(error_type, platform).check_anomaly(today_count, sensitivity: sensitivity)
    end

    # Detect cyclical occurrence patterns (daily/weekly rhythms)
    # @param days [Integer] Number of days to analyze (default: 30)
    # @return [Hash] Pattern analysis result
    def occurrence_pattern(days: 30)
      return {} unless RailsErrorDashboard.configuration.enable_occurrence_patterns
      return {} unless defined?(Services::PatternDetector)

      timestamps = self.class
        .where(error_type: error_type, platform: platform)
        .where("occurred_at >= ?", days.days.ago)
        .pluck(:occurred_at)

      Services::PatternDetector.analyze_cyclical_pattern(
        timestamps: timestamps,
        days: days
      )
    end

    # Detect error bursts (many errors in short time)
    # @param days [Integer] Number of days to analyze (default: 7)
    # @return [Array<Hash>] Array of burst metadata
    def error_bursts(days: 7)
      return [] unless RailsErrorDashboard.configuration.enable_occurrence_patterns
      return [] unless defined?(Services::PatternDetector)

      timestamps = self.class
        .where(error_type: error_type, platform: platform)
        .where("occurred_at >= ?", days.days.ago)
        .order(:occurred_at)
        .pluck(:occurred_at)

      Services::PatternDetector.detect_bursts(timestamps: timestamps)
    end

    private

    # Override user association to use configured user model
    def self.belongs_to(*args, **options)
      if args.first == :user
        user_model = RailsErrorDashboard.configuration.user_model
        options[:class_name] = user_model if user_model.present?
      end
      super
    end

    # Turbo Stream broadcasting methods
    def broadcast_new_error
      # Skip broadcasting in API-only mode or if Turbo is not available
      return unless defined?(Turbo)
      return unless broadcast_available?

      platforms = ErrorLog.distinct.pluck(:platform).compact
      show_platform = platforms.size > 1

      Turbo::StreamsChannel.broadcast_prepend_to(
        "error_list",
        target: "error_list",
        partial: "rails_error_dashboard/errors/error_row",
        locals: { error: self, show_platform: show_platform }
      )
      broadcast_replace_stats
    rescue => e
      Rails.logger.error("[RailsErrorDashboard] Failed to broadcast new error: #{e.class} - #{e.message}")
      Rails.logger.debug("[RailsErrorDashboard] Backtrace: #{e.backtrace&.first(3)&.join("\n")}")
    end

    def broadcast_error_update
      # Skip broadcasting in API-only mode or if Turbo is not available
      return unless defined?(Turbo)
      return unless broadcast_available?

      platforms = ErrorLog.distinct.pluck(:platform).compact
      show_platform = platforms.size > 1

      Turbo::StreamsChannel.broadcast_replace_to(
        "error_list",
        target: "error_#{id}",
        partial: "rails_error_dashboard/errors/error_row",
        locals: { error: self, show_platform: show_platform }
      )
      broadcast_replace_stats
    rescue => e
      Rails.logger.error("[RailsErrorDashboard] Failed to broadcast error update: #{e.class} - #{e.message}")
      Rails.logger.debug("[RailsErrorDashboard] Backtrace: #{e.backtrace&.first(3)&.join("\n")}")
    end

    def broadcast_replace_stats
      # Skip broadcasting in API-only mode or if Turbo is not available
      return unless defined?(Turbo)
      return unless broadcast_available?

      stats = Queries::DashboardStats.call
      # Safety check: ensure stats is not nil before broadcasting
      return unless stats.is_a?(Hash) && stats.present?

      Turbo::StreamsChannel.broadcast_replace_to(
        "error_list",
        target: "dashboard_stats",
        partial: "rails_error_dashboard/errors/stats",
        locals: { stats: stats }
      )
    rescue => e
      Rails.logger.error("[RailsErrorDashboard] Failed to broadcast stats update: #{e.class} - #{e.message}")
      Rails.logger.debug("[RailsErrorDashboard] Backtrace: #{e.backtrace&.first(3)&.join("\n")}")
    end

    # Check if broadcast functionality is available and properly configured
    # In API-only apps, ActionCable might not be configured or Rails.cache might not be available
    def broadcast_available?
      # Check if ActionCable is available (required for Turbo Streams)
      return false unless defined?(ActionCable)

      # Check if Rails.cache is configured and working
      # This prevents errors when cache is not available in API-only mode
      begin
        Rails.cache.write("rails_error_dashboard_broadcast_test", true, expires_in: 1.second)
        Rails.cache.delete("rails_error_dashboard_broadcast_test")
        true
      rescue => e
        Rails.logger.debug("[RailsErrorDashboard] Broadcast not available: #{e.message}")
        false
      end
    end

    # Enhanced Metrics: Release/Version Tracking
    def fetch_app_version
      RailsErrorDashboard.configuration.app_version || ENV["APP_VERSION"] || detect_version_from_file
    end

    def fetch_git_sha
      RailsErrorDashboard.configuration.git_sha || ENV["GIT_SHA"] || detect_git_sha
    end

    def detect_version_from_file
      version_file = Rails.root.join("VERSION")
      return File.read(version_file).strip if File.exist?(version_file)
      nil
    end

    def detect_git_sha
      return nil unless File.exist?(Rails.root.join(".git"))
      `git rev-parse --short HEAD 2>/dev/null`.strip.presence
    rescue => e
      Rails.logger.debug("Could not detect git SHA: #{e.message}")
      nil
    end

    # Public method: Get user impact percentage
    def user_impact_percentage
      return 0 unless user_id.present?

      affected_users = Services::PriorityScoreCalculator.unique_users_affected(error_type)
      return 0 if affected_users.zero?

      # Get total active users from config or estimate
      total_users = RailsErrorDashboard.configuration.total_users_for_impact || estimate_total_users
      return 0 if total_users.zero?

      ((affected_users.to_f / total_users) * 100).round(1)
    end

    def estimate_total_users
      # Estimate based on users who had any activity in last 30 days
      if defined?(::User)
        ::User.where("created_at >= ?", 30.days.ago).count
      else
        100 # Default fallback
      end
    end

    # Clear analytics caches when errors are created, updated, or destroyed
    # This ensures dashboard and analytics always show fresh data
    def clear_analytics_cache
      # Use delete_matched to clear all cached analytics regardless of parameters
      # Pattern matches: dashboard_stats/*, analytics_stats/*, platform_comparison/*
      # Note: SolidCache doesn't support delete_matched, so we catch NotImplementedError
      if Rails.cache.respond_to?(:delete_matched)
        Rails.cache.delete_matched("dashboard_stats/*")
        Rails.cache.delete_matched("analytics_stats/*")
        Rails.cache.delete_matched("platform_comparison/*")
      else
        # SolidCache or other stores that don't support pattern matching
        # We can't clear cache patterns, so just skip it
        Rails.logger.info("Cache store doesn't support delete_matched, skipping cache clear") if Rails.logger
      end
    rescue NotImplementedError => e
      # Some cache stores throw NotImplementedError even if respond_to? returns true
      Rails.logger.info("Cache store doesn't support delete_matched: #{e.message}") if Rails.logger
    rescue => e
      # Silently handle other cache clearing errors to prevent blocking error logging
      Rails.logger.error("Failed to clear analytics cache: #{e.message}") if Rails.logger
    end
  end
end
