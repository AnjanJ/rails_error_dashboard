module RailsErrorDashboard
  class Application < ErrorLogsRecord
    self.table_name = "rails_error_dashboard_applications"

    # Associations
    has_many :error_logs, dependent: :restrict_with_error

    # Validations
    validates :name, presence: true, uniqueness: true, length: { maximum: 255 }

    # Scopes
    scope :ordered_by_name, -> { order(:name) }

    # Class method for finding or creating with caching
    # Caches application IDs (not objects) to avoid stale ActiveRecord references
    # This is safer with transactional fixtures and database rollbacks
    def self.find_or_create_by_name(name)
      # Try to find ID in cache
      cached_id = Rails.cache.read("error_dashboard/application_id/#{name}")
      if cached_id
        # Verify the cached ID still exists in database
        # (could have been deleted in tests with transactional rollback)
        cached_record = find_by(id: cached_id)
        return cached_record if cached_record
        # Cache was stale, clear it
        Rails.cache.delete("error_dashboard/application_id/#{name}")
      end

      # Try to find existing in database
      found = find_by(name: name)
      if found
        # Cache the ID (not the object) for future lookups
        Rails.cache.write("error_dashboard/application_id/#{name}", found.id, expires_in: 1.hour)
        return found
      end

      # Create if not found
      created = create!(name: name)
      # Cache the ID (not the object)
      Rails.cache.write("error_dashboard/application_id/#{name}", created.id, expires_in: 1.hour)
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
