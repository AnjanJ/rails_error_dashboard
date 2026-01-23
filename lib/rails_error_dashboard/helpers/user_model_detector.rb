# frozen_string_literal: true

module RailsErrorDashboard
  module Helpers
    # Automatically detects the User model and total users count
    # Handles both single database and separate database setups
    class UserModelDetector
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
          if model_class.respond_to?(:count)
            # Use a timeout to avoid hanging the dashboard
            Timeout.timeout(5) do
              model_class.count
            end
          end
        rescue NameError, LoadError => e
          log_error("Model not found: #{model_name} - #{e.message}")
          nil
        rescue Timeout::Error => e
          log_error("Timeout querying #{model_name}.count - #{e.message}")
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

        def log_error(message)
          return unless RailsErrorDashboard.configuration.enable_internal_logging

          Rails.logger.warn("[RailsErrorDashboard::UserModelDetector] #{message}")
        end
      end
    end
  end
end
