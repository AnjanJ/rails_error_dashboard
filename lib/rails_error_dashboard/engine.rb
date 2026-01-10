module RailsErrorDashboard
  class Engine < ::Rails::Engine
    isolate_namespace RailsErrorDashboard

    # Configure database connection for error models
    # This runs early, before middleware setup, but after database.yml is loaded
    initializer "rails_error_dashboard.database", before: :load_config_initializers do
      config.after_initialize do
        if RailsErrorDashboard.configuration&.use_separate_database
          database_name = RailsErrorDashboard.configuration&.database || :error_dashboard

          RailsErrorDashboard::ErrorLogsRecord.connects_to(
            database: { writing: database_name, reading: database_name }
          )
        end
      end
    end

    # Initialize the engine
    initializer "rails_error_dashboard.middleware" do |app|
      # Enable Flash middleware for Error Dashboard routes in API-only apps
      # This ensures flash messages work even when config.api_only = true
      if app.config.api_only
        # Insert Flash middleware ONLY for Error Dashboard routes
        app.middleware.use ActionDispatch::Flash
        app.middleware.use ActionDispatch::Cookies
        app.middleware.use ActionDispatch::Session::CookieStore
      end

      # Add error catching middleware if enabled
      if RailsErrorDashboard.configuration.enable_middleware
        app.config.middleware.insert_before 0, RailsErrorDashboard::Middleware::ErrorCatcher
      end

      # Add rate limiting middleware if enabled
      if RailsErrorDashboard.configuration.enable_rate_limiting
        app.config.middleware.use RailsErrorDashboard::Middleware::RateLimiter
      end
    end

    # Subscribe to Rails error reporter
    config.after_initialize do
      if RailsErrorDashboard.configuration.enable_error_subscriber
        Rails.error.subscribe(RailsErrorDashboard::ErrorReporter.new)
      end
    end
  end
end
