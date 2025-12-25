# frozen_string_literal: true

module RailsErrorDashboard
  class ErrorLog < ErrorLogsRecord
    self.table_name = "rails_error_dashboard_error_logs"

    # User association - works with both single and separate database
    # When using separate database, joins are not possible, but Rails
    # will automatically fetch users in a separate query when using includes()
    # Only define association if User model exists
    if defined?(::User)
      belongs_to :user, optional: true
    end

    # Phase 4.1.2: Association for error occurrences
    has_many :error_occurrences, class_name: "RailsErrorDashboard::ErrorOccurrence", dependent: :destroy

    # Phase 4.1.3: Associations for cascade patterns
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

    # Set defaults and tracking
    before_validation :set_defaults, on: :create
    before_create :set_tracking_fields
    before_create :set_release_info
    after_create :calculate_priority_score

    # Turbo Stream broadcasting
    after_create_commit :broadcast_new_error
    after_update_commit :broadcast_error_update

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

    def calculate_priority_score
      return unless respond_to?(:priority_score=)
      self.priority_score = compute_priority_score
      save if persisted?
    end

    # Generate unique hash for error grouping
    # Includes controller/action for better context-aware grouping
    def generate_error_hash
      # Hash based on error class, normalized message, first stack frame, controller, and action
      digest_input = [
        error_type,
        message&.gsub(/\d+/, "N")&.gsub(/"[^"]*"/, '""'), # Normalize numbers and strings
        backtrace&.lines&.first&.split(":")&.first, # Just the file, not line number
        controller_name, # Controller context
        action_name      # Action context
      ].compact.join("|")

      Digest::SHA256.hexdigest(digest_input)[0..15]
    end

    # Check if this is a critical error
    def critical?
      CRITICAL_ERROR_TYPES.include?(error_type)
    end

    # Check if error is recent (< 1 hour)
    def recent?
      occurred_at >= 1.hour.ago
    end

    # Check if error is old unresolved (> 7 days)
    def stale?
      !resolved? && occurred_at < 7.days.ago
    end

    # Get severity level
    # Checks custom severity rules first, then falls back to default classification
    def severity
      # Check custom severity rules first
      custom_severity = RailsErrorDashboard.configuration.custom_severity_rules[error_type]
      return custom_severity.to_sym if custom_severity.present?

      # Fall back to default classification
      return :critical if CRITICAL_ERROR_TYPES.include?(error_type)
      return :high if HIGH_SEVERITY_ERROR_TYPES.include?(error_type)
      return :medium if MEDIUM_SEVERITY_ERROR_TYPES.include?(error_type)
      :low
    end

    CRITICAL_ERROR_TYPES = %w[
      SecurityError
      NoMemoryError
      SystemStackError
      SignalException
      ActiveRecord::StatementInvalid
    ].freeze

    HIGH_SEVERITY_ERROR_TYPES = %w[
      ActiveRecord::RecordNotFound
      ArgumentError
      TypeError
      NoMethodError
      NameError
    ].freeze

    MEDIUM_SEVERITY_ERROR_TYPES = %w[
      ActiveRecord::RecordInvalid
      Timeout::Error
      Net::ReadTimeout
      Net::OpenTimeout
    ].freeze

    # Find existing error by hash or create new one
    # This is CRITICAL for accurate occurrence tracking
    def self.find_or_increment_by_hash(error_hash, attributes = {})
      # Look for unresolved error with same hash in last 24 hours
      # (resolved errors are considered "fixed" so new occurrence = new issue)
      existing = unresolved
                  .where(error_hash: error_hash)
                  .where("occurred_at >= ?", 24.hours.ago)
                  .order(last_seen_at: :desc)
                  .first

      if existing
        # Increment existing error
        existing.update!(
          occurrence_count: existing.occurrence_count + 1,
          last_seen_at: Time.current,
          # Update context from latest occurrence
          user_id: attributes[:user_id] || existing.user_id,
          request_url: attributes[:request_url] || existing.request_url,
          request_params: attributes[:request_params] || existing.request_params,
          user_agent: attributes[:user_agent] || existing.user_agent,
          ip_address: attributes[:ip_address] || existing.ip_address
        )
        existing
      else
        # Create new error record
        # Ensure resolved has a value (default to false)
        create!(attributes.reverse_merge(resolved: false))
      end
    end

    # Log an error with context (delegates to Command)
    def self.log_error(exception, context = {})
      Commands::LogError.call(exception, context)
    end

    # Mark error as resolved (delegates to Command)
    def resolve!(resolution_data = {})
      Commands::ResolveError.call(id, resolution_data)
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
    def related_errors(limit: 5)
      self.class.where(error_type: error_type)
          .where.not(id: id)
          .order(occurred_at: :desc)
          .limit(limit)
    end

    # Phase 4.1: Fuzzy Error Matching
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

    # Calculate backtrace signature for fast similarity matching
    # Signature is a hash of the unique file paths in the backtrace
    def calculate_backtrace_signature
      frames = backtrace_frames
      return nil if frames.empty?

      # Create signature from sorted file paths (order-independent)
      file_paths = frames.map { |frame| frame.split(":").first }.sort
      Digest::SHA256.hexdigest(file_paths.join("|"))[0..15]
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

    # Phase 4.1.2: Find errors that occur together in time
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

    # Phase 4.1.3: Find cascade patterns (what causes this error, what this error causes)
    # @param min_probability [Float] Minimum cascade probability (0.0-1.0), default 0.5
    # @return [Hash] {parents: Array, children: Array} of cascade patterns
    def error_cascades(min_probability: 0.5)
      return { parents: [], children: [] } unless persisted?
      return { parents: [], children: [] } unless RailsErrorDashboard.configuration.enable_error_cascades
      return { parents: [], children: [] } unless defined?(Queries::ErrorCascades)

      Queries::ErrorCascades.call(error_id: id, min_probability: min_probability)
    end

    # Phase 4.2: Get baseline statistics for this error type
    # @return [Hash] {hourly: ErrorBaseline, daily: ErrorBaseline, weekly: ErrorBaseline}
    def baselines
      return {} unless RailsErrorDashboard.configuration.enable_baseline_alerts
      return {} unless defined?(Queries::BaselineStats)

      Queries::BaselineStats.new(error_type, platform).all_baselines
    end

    # Phase 4.2: Check if this error is anomalous compared to baseline
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

    # Phase 4.5: Detect cyclical occurrence patterns (daily/weekly rhythms)
    # @param days [Integer] Number of days to analyze (default: 30)
    # @return [Hash] Pattern analysis result
    def occurrence_pattern(days: 30)
      return {} unless RailsErrorDashboard.configuration.enable_occurrence_patterns
      return {} unless defined?(Services::PatternDetector)

      Services::PatternDetector.analyze_cyclical_pattern(
        error_type: error_type,
        platform: platform,
        days: days
      )
    end

    # Phase 4.5: Detect error bursts (many errors in short time)
    # @param days [Integer] Number of days to analyze (default: 7)
    # @return [Array<Hash>] Array of burst metadata
    def error_bursts(days: 7)
      return [] unless RailsErrorDashboard.configuration.enable_occurrence_patterns
      return [] unless defined?(Services::PatternDetector)

      Services::PatternDetector.detect_bursts(
        error_type: error_type,
        platform: platform,
        days: days
      )
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
      return unless defined?(Turbo)

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
      Rails.logger.error("Failed to broadcast new error: #{e.message}")
    end

    def broadcast_error_update
      return unless defined?(Turbo)

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
      Rails.logger.error("Failed to broadcast error update: #{e.message}")
    end

    def broadcast_replace_stats
      return unless defined?(Turbo)

      stats = Queries::DashboardStats.call
      Turbo::StreamsChannel.broadcast_replace_to(
        "error_list",
        target: "dashboard_stats",
        partial: "rails_error_dashboard/errors/stats",
        locals: { stats: stats }
      )
    rescue => e
      Rails.logger.error("Failed to broadcast stats update: #{e.message}")
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

    # Enhanced Metrics: Smart Priority Scoring
    # Score: 0-100 based on severity, frequency, recency, and user impact
    def compute_priority_score
      severity_score = severity_to_score(severity)
      frequency_score = frequency_to_score(occurrence_count)
      recency_score = recency_to_score(occurred_at)
      user_impact_score = user_impact_to_score

      # Weighted average
      (severity_score * 0.4 + frequency_score * 0.25 + recency_score * 0.2 + user_impact_score * 0.15).round
    end

    def severity_to_score(sev)
      case sev
      when :critical then 100
      when :high then 75
      when :medium then 50
      when :low then 25
      else 10
      end
    end

    def frequency_to_score(count)
      # Logarithmic scale: 1 occurrence = 10, 10 = 50, 100 = 90, 1000+ = 100
      return 10 if count <= 1
      return 100 if count >= 1000

      (10 + (Math.log10(count) * 30)).clamp(10, 100).round
    end

    def recency_to_score(time)
      hours_ago = ((Time.current - time) / 1.hour).to_i
      return 100 if hours_ago < 1      # Last hour = 100
      return 80 if hours_ago < 24      # Last 24h = 80
      return 50 if hours_ago < 168     # Last week = 50
      return 20 if hours_ago < 720     # Last month = 20
      10                                # Older = 10
    end

    def user_impact_to_score
      return 0 unless user_id.present?

      # Calculate what % of users are affected by this error type
      total_users = unique_users_affected
      return 0 if total_users.zero?

      # Scale: 1 user = 10, 10 users = 50, 100+ users = 100
      (10 + (Math.log10(total_users + 1) * 30)).clamp(0, 100).round
    end

    def unique_users_affected
      ErrorLog.where(error_type: error_type, resolved: false)
              .where.not(user_id: nil)
              .distinct
              .count(:user_id)
    end

    # Public method: Get user impact percentage
    def user_impact_percentage
      return 0 unless user_id.present?

      affected_users = unique_users_affected
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
  end
end
