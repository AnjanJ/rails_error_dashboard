# frozen_string_literal: true

RailsErrorDashboard.configure do |config|
  # Dashboard authentication credentials
  # Change these in production or use environment variables
  config.dashboard_username = ENV.fetch('ERROR_DASHBOARD_USER', 'admin')
  config.dashboard_password = ENV.fetch('ERROR_DASHBOARD_PASSWORD', 'password')

  # Require authentication for dashboard access
  # Set to false to disable authentication (not recommended in production)
  config.require_authentication = true

  # Require authentication even in development mode
  # Set to true if you want to test authentication in development
  config.require_authentication_in_development = false

  # User model for associations (defaults to 'User')
  # Change this if your user model has a different name
  config.user_model = 'User'

  # === NOTIFICATION SETTINGS ===

  # Slack notifications
  config.enable_slack_notifications = true
  config.slack_webhook_url = ENV['SLACK_WEBHOOK_URL']

  # Email notifications
  config.enable_email_notifications = true
  config.notification_email_recipients = ENV.fetch('ERROR_NOTIFICATION_EMAILS', '').split(',').map(&:strip)
  config.notification_email_from = ENV.fetch('ERROR_NOTIFICATION_FROM', 'errors@example.com')

  # Dashboard base URL (used in notification links)
  # Example: 'https://myapp.com' or 'http://localhost:3000'
  config.dashboard_base_url = ENV['DASHBOARD_BASE_URL']

  # Use a separate database for error logs (optional)
  # See documentation for setup instructions: docs/SEPARATE_ERROR_DATABASE.md
  config.use_separate_database = ENV.fetch('USE_SEPARATE_ERROR_DB', 'false') == 'true'

  # Retention policy - number of days to keep error logs
  # Old errors will be automatically deleted after this many days
  config.retention_days = 90

  # Enable/disable error catching middleware
  # Set to false if you want to handle errors differently
  config.enable_middleware = true

  # Enable/disable Rails.error subscriber
  # Set to false if you don't want to use Rails error reporting
  config.enable_error_subscriber = true
end
