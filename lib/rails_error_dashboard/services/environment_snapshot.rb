# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Capture runtime environment info at boot time
    #
    # Snapshots Ruby version, Rails version, loaded gem versions, web server,
    # and database adapter. Memoized — computed once per process lifetime.
    # Stored as JSON on each error so historical errors show the environment
    # that was running when they occurred (not the current environment).
    class EnvironmentSnapshot
      TRACKED_GEMS = %w[
        activerecord actionpack sidekiq solid_queue puma unicorn
        passenger redis pg mysql2 sqlite3 good_job
      ].freeze

      # Return cached environment snapshot (frozen hash)
      # @return [Hash] Environment info
      def self.snapshot
        @cached_snapshot ||= new.capture.freeze
      end

      # Clear cached snapshot (for testing)
      def self.reset!
        @cached_snapshot = nil
      end

      # Capture current environment info
      # @return [Hash] Environment snapshot
      def capture
        {
          ruby_version: RUBY_VERSION,
          ruby_engine: RUBY_ENGINE,
          ruby_platform: RUBY_PLATFORM,
          rails_version: rails_version,
          rails_env: rails_env,
          gem_versions: detect_gem_versions,
          server: detect_server,
          database_adapter: detect_database_adapter
        }
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] EnvironmentSnapshot.capture failed: #{e.message}")
        { ruby_version: RUBY_VERSION, ruby_engine: RUBY_ENGINE }
      end

      private

      def rails_version
        Rails.version
      rescue
        "unknown"
      end

      def rails_env
        Rails.env.to_s
      rescue
        "unknown"
      end

      def detect_gem_versions
        TRACKED_GEMS.each_with_object({}) do |gem_name, hash|
          spec = Gem.loaded_specs[gem_name]
          hash[gem_name] = spec.version.to_s if spec
        end
      rescue
        {}
      end

      def detect_server
        return "puma" if defined?(Puma)
        return "unicorn" if defined?(Unicorn)
        return "passenger" if defined?(PhusionPassenger)
        "unknown"
      rescue
        "unknown"
      end

      def detect_database_adapter
        ActiveRecord::Base.connection_db_config.adapter
      rescue
        "unknown"
      end
    end
  end
end
