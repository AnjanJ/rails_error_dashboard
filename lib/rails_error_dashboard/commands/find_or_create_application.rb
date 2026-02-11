# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Find an existing application by name or create a new one
    # Caches application IDs (not objects) to avoid stale ActiveRecord references.
    class FindOrCreateApplication
      CACHE_PREFIX = "error_dashboard/application_id"
      CACHE_EXPIRY = 1.hour

      def self.call(name)
        new(name).call
      end

      def initialize(name)
        @name = name
      end

      def call
        find_from_cache || find_from_database || create_new
      end

      private

      def cache_key
        "#{CACHE_PREFIX}/#{@name}"
      end

      def find_from_cache
        cached_id = Rails.cache.read(cache_key)
        return nil unless cached_id

        record = Application.find_by(id: cached_id)
        if record
          record
        else
          Rails.cache.delete(cache_key)
          nil
        end
      end

      def find_from_database
        found = Application.find_by(name: @name)
        return nil unless found

        Rails.cache.write(cache_key, found.id, expires_in: CACHE_EXPIRY)
        found
      end

      def create_new
        created = Application.create!(name: @name)
        Rails.cache.write(cache_key, created.id, expires_in: CACHE_EXPIRY)
        created
      end
    end
  end
end
