module RailsErrorDashboard
  class Application < ErrorLogsRecord
    self.table_name = "rails_error_dashboard_applications"

    # Associations
    has_many :error_logs, dependent: :restrict_with_error

    # Validations
    validates :name, presence: true, uniqueness: true, length: { maximum: 255 }

    # Scopes
    scope :ordered_by_name, -> { order(:name) }

    # Find or create application by name — delegates to Command
    def self.find_or_create_by_name(name)
      Commands::FindOrCreateApplication.call(name)
    end

    # Instance methods
    def error_count
      error_logs.count
    end

    def unresolved_error_count
      error_logs.unresolved.count
    end
  end
end
