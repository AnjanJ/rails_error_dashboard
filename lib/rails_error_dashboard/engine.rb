module RailsErrorDashboard
  class Engine < ::Rails::Engine
    isolate_namespace RailsErrorDashboard

    # Configure database connection for error models
    # This runs early, before middleware setup, but after database.yml is loaded
    initializer "rails_error_dashboard.database", before: :load_config_initializers do
      config.after_initialize do
        if RailsErrorDashboard.configuration&.use_separate_database
          database_name = RailsErrorDashboard.configuration&.database || :error_dashboard

          # Guard: skip connects_to if the database config doesn't exist yet in database.yml.
          # This happens during `rails generate` when the initializer was just created but
          # the user hasn't added the database.yml entry yet.
          db_configs = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env)
          unless db_configs.any? { |c| c.name == database_name.to_s }
            Rails.logger.warn "[Rails Error Dashboard] Separate database '#{database_name}' is not configured in database.yml for the '#{Rails.env}' environment. Skipping connects_to. See https://github.com/AnjanJ/rails_error_dashboard/blob/main/docs/guides/DATABASE_OPTIONS.md"
            next
          end

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

    # Validate configuration after initialization
    initializer "rails_error_dashboard.validate_config", after: :load_config_initializers do
      config.after_initialize do
        begin
          RailsErrorDashboard.configuration.validate!
        rescue ConfigurationError => e
          Rails.logger.error "[Rails Error Dashboard] #{e.message}"
          raise
        end
      end
    end

    # Subscribe to Rails error reporter
    config.after_initialize do
      if RailsErrorDashboard.configuration.enable_error_subscriber
        Rails.error.subscribe(RailsErrorDashboard::ErrorReporter.new)
      end

      # Subscribe to AS::Notifications for breadcrumb collection
      if RailsErrorDashboard.configuration.enable_breadcrumbs
        RailsErrorDashboard::Subscribers::BreadcrumbSubscriber.subscribe!
      end
    end
  end
end
