# frozen_string_literal: true

module RailsErrorDashboard
  module Helpers
    # Automatically detects the User model and total users count
    # Handles both single database and separate database setups
    class UserModelDetector
      COUNT_TIMEOUT_MS = 5_000

      class << self
        # Auto-detect the user model name
        # Returns the configured model if set, otherwise tries to detect User model
        #
        # @return [String, nil] The user model class name or nil if not found
        def detect_user_model
          # Return configured model if explicitly set
          configured_model = RailsErrorDashboard.configuration.user_model
          return configured_model if configured_model.present? && configured_model != "User"

          # Try to detect User model
          return "User" if user_model_exists?

          # Check for common alternatives
          %w[Account Member Person].each do |model_name|
            return model_name if model_exists?(model_name)
          end

          nil
        end

        # Auto-detect total users count
        # Returns the configured value if set, otherwise queries the user model
        #
        # @return [Integer, nil] Total users count or nil if unavailable
        def detect_total_users
          # Return configured value if explicitly set
          configured_count = RailsErrorDashboard.configuration.total_users_for_impact
          return configured_count if configured_count.present?

          # Try to query user model count
          user_model_name = detect_user_model
          return nil unless user_model_name

          query_user_count(user_model_name)
        rescue StandardError => e
          # Silently return nil if query fails (DB not accessible, model doesn't have count, etc.)
          log_error("Failed to query user count: #{e.message}")
          nil
        end

        # Check if User model exists and is loaded
        #
        # @return [Boolean]
        def user_model_exists?
          model_exists?("User")
        end

        # Check if a specific model exists and is loaded
        #
        # @param [String] model_name The model class name to check
        # @return [Boolean]
        def model_exists?(model_name)
          # Check if model file exists
          return false unless model_file_exists?(model_name)

          # Try to constantize the model
          begin
            model_class = model_name.constantize
            model_class.is_a?(Class) && model_class < ActiveRecord::Base
          rescue NameError, LoadError
            false
          end
        end

        # Check if model file exists in app/models
        #
        # @param [String] model_name The model class name to check
        # @return [Boolean]
        def model_file_exists?(model_name)
          return false unless defined?(Rails)

          # Convert to snake_case filename (e.g., "User" -> "user.rb")
          filename = model_name.underscore + ".rb"
          model_path = Rails.root.join("app", "models", filename)

          File.exist?(model_path)
        end

        # Query the user count from the model
        # Handles connection to main database even if error dashboard uses separate DB
        #
        # @param [String] model_name The model class name to query
        # @return [Integer, nil] User count or nil if query fails
        def query_user_count(model_name)
          model_class = model_name.constantize

          # Ensure we're querying the main database, not the error dashboard database
          # User models always connect to the primary/main database
          bounded_count(model_class) if model_class.respond_to?(:count)
        rescue NameError, LoadError => e
          log_error("Model not found: #{model_name} - #{e.message}")
          nil
        rescue StandardError => e
          log_error("Error querying #{model_name}.count: #{e.message}")
          nil
        end

        # Get user impact percentage for an error
        # Calculates percentage of users affected based on unique_users_count
        #
        # @param [Integer] unique_users_count Number of unique users affected
        # @return [Float, nil] Percentage or nil if total users unavailable
        def calculate_user_impact(unique_users_count)
          return nil unless unique_users_count.present? && unique_users_count.positive?

          total_users = detect_total_users
          return nil unless total_users.present? && total_users.positive?

          ((unique_users_count.to_f / total_users) * 100).round(2)
        end

        private

        # The database ends a slow count itself and tells the driver cleanly.
        # Timeout would interrupt this thread wherever it was, inside the driver
        # included, and could leave the host's connection mid-protocol in its
        # pool. SQLite's database is a local file; any other adapter gets a plain
        # count, unbounded but never interrupted.
        def bounded_count(model_class)
          return model_class.count unless model_class.respond_to?(:connection_pool)

          model_class.connection_pool.with_connection do |connection|
            case connection.adapter_name.downcase
            when /postgres|postgis/
              postgresql_count(model_class, connection)
            when /mysql|trilogy/
              model_class.optimizer_hints("MAX_EXECUTION_TIME(#{COUNT_TIMEOUT_MS})").count
            else
              model_class.count
            end
          end
        end

        # The savepoint keeps a cancelled count from aborting a transaction the
        # host already has open. Rolling it back every time undoes SET LOCAL,
        # which would otherwise last to the end of that transaction.
        def postgresql_count(model_class, connection)
          count = nil
          model_class.transaction(requires_new: true) do
            connection.execute("SET LOCAL statement_timeout = #{COUNT_TIMEOUT_MS}")
            count = model_class.count
            raise ActiveRecord::Rollback
          end
          count
        end

        def log_error(message)
          return unless RailsErrorDashboard.configuration.enable_internal_logging

          Rails.logger.warn("[RailsErrorDashboard::UserModelDetector] #{message}")
        end
      end
    end
  end
end
