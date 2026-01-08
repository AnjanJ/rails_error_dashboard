module RailsErrorDashboard
  class Application < ActiveRecord::Base
    self.table_name = "rails_error_dashboard_applications"

    # Associations
    has_many :error_logs, dependent: :restrict_with_error

    # Validations
    validates :name, presence: true, uniqueness: true, length: { maximum: 255 }

    # Scopes
    scope :ordered_by_name, -> { order(:name) }

    # Class method for finding or creating with caching
    # Only caches successful finds, not creates (to avoid caching nil on creation failures)
    def self.find_or_create_by_name(name)
      # Try to find in cache or database first
      cached = Rails.cache.read("error_dashboard/application/#{name}")
      return cached if cached

      # Try to find existing
      found = find_by(name: name)
      if found
        Rails.cache.write("error_dashboard/application/#{name}", found, expires_in: 1.hour)
        return found
      end

      # Create if not found (don't cache until successful)
      created = create!(name: name)
      Rails.cache.write("error_dashboard/application/#{name}", created, expires_in: 1.hour)
      created
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
