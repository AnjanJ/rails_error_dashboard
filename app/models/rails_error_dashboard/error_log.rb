# frozen_string_literal: true

module RailsErrorDashboard
  class ErrorLog < ErrorLogsRecord
    self.table_name = 'rails_error_dashboard_error_logs'

    # User association - works with both single and separate database
    # When using separate database, joins are not possible, but Rails
    # will automatically fetch users in a separate query when using includes()
    belongs_to :user, optional: true

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
    scope :last_24_hours, -> { where('occurred_at >= ?', 24.hours.ago) }
    scope :last_week, -> { where('occurred_at >= ?', 1.week.ago) }

    # Set defaults
    before_validation :set_defaults, on: :create

    def set_defaults
      self.environment ||= Rails.env.to_s
      self.platform ||= 'API'
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
        total: where('occurred_at >= ?', start_date).count,
        unresolved: where('occurred_at >= ?', start_date).unresolved.count,
        by_type: where('occurred_at >= ?', start_date)
          .group(:error_type)
          .count
          .sort_by { |_, count| -count }
          .to_h,
        by_day: where('occurred_at >= ?', start_date)
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
