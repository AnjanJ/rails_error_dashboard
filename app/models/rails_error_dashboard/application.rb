module RailsErrorDashboard
  class Application < ActiveRecord::Base
    self.table_name = 'rails_error_dashboard_applications'

    # Associations
    has_many :error_logs, dependent: :restrict_with_error

    # Validations
    validates :name, presence: true, uniqueness: true, length: { maximum: 255 }

    # Scopes
    scope :ordered_by_name, -> { order(:name) }

    # Class method for finding or creating with caching
    def self.find_or_create_by_name(name)
      Rails.cache.fetch("error_dashboard/application/#{name}", expires_in: 1.hour) do
        find_or_create_by!(name: name)
      end
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
