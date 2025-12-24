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

    validates :error_type, presence: true
    validates :message, presence: true
    validates :environment, presence: true
    validates :occurred_at, presence: true

    scope :unresolved, -> { where(resolved: false) }
    scope :resolved, -> { where(resolved: true) }
    scope :recent, -> { order(occurred_at: :desc) }
    scope :by_environment, ->(env) { where(environment: env) }
    scope :by_error_type, ->(type) { where(error_type: type) }
    scope :by_type, ->(type) { where(error_type: type) }
    scope :by_platform, ->(platform) { where(platform: platform) }
    scope :last_24_hours, -> { where("occurred_at >= ?", 24.hours.ago) }
    scope :last_week, -> { where("occurred_at >= ?", 1.week.ago) }

    # Set defaults and tracking
    before_validation :set_defaults, on: :create
    before_create :set_tracking_fields

    def set_defaults
      self.environment ||= Rails.env.to_s
      self.platform ||= "API"
    end

    def set_tracking_fields
      self.error_hash ||= generate_error_hash
      self.first_seen_at ||= Time.current
      self.last_seen_at ||= Time.current
      self.occurrence_count ||= 1
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
    def severity
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

    private

    # Override user association to use configured user model
    def self.belongs_to(*args, **options)
      if args.first == :user
        user_model = RailsErrorDashboard.configuration.user_model
        options[:class_name] = user_model if user_model.present?
      end
      super
    end
  end
end
