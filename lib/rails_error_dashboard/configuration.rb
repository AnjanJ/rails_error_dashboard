# frozen_string_literal: true

module RailsErrorDashboard
  class Configuration
    # Dashboard authentication
    attr_accessor :dashboard_username
    attr_accessor :dashboard_password
    attr_accessor :require_authentication
    attr_accessor :require_authentication_in_development

    # User model (for associations)
    attr_accessor :user_model

    # Slack notifications
    attr_accessor :slack_webhook_url

    # Separate database configuration
    attr_accessor :use_separate_database

    # Retention policy (days to keep errors)
    attr_accessor :retention_days

    # Enable/disable error catching middleware
    attr_accessor :enable_middleware

    # Enable/disable Rails.error subscriber
    attr_accessor :enable_error_subscriber

    def initialize
      # Default values
      @dashboard_username = ENV.fetch('ERROR_DASHBOARD_USER', 'admin')
      @dashboard_password = ENV.fetch('ERROR_DASHBOARD_PASSWORD', 'password')
      @require_authentication = true
      @require_authentication_in_development = false

      @user_model = 'User'

      @slack_webhook_url = ENV['SLACK_WEBHOOK_URL']

      @use_separate_database = ENV.fetch('USE_SEPARATE_ERROR_DB', 'false') == 'true'

      @retention_days = 90

      @enable_middleware = true
      @enable_error_subscriber = true
    end
  end
end
