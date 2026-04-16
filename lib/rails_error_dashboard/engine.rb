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
      # Skip all runtime features during Docker asset precompilation.
      # SECRET_KEY_BASE_DUMMY=1 signals a build environment — no database,
      # no credentials, no external services are available. Activating
      # TracePoint hooks, error subscribers, or background jobs here causes
      # infinite retry loops and connection failures (issues #1-5).
      if ENV["SECRET_KEY_BASE_DUMMY"].present?
        Rails.logger.info "[Rails Error Dashboard] Build environment detected (SECRET_KEY_BASE_DUMMY) — skipping runtime features."
        next
      end

      if RailsErrorDashboard.configuration.enable_error_subscriber
        Rails.error.subscribe(RailsErrorDashboard::ErrorReporter.new)
      end

      # Subscribe to AS::Notifications for breadcrumb collection
      if RailsErrorDashboard.configuration.enable_breadcrumbs
        RailsErrorDashboard::Subscribers::BreadcrumbSubscriber.subscribe!
      end

      # Subscribe to Rack Attack AS::Notifications events (requires breadcrumbs + Rack::Attack)
      if RailsErrorDashboard.configuration.enable_rack_attack_tracking &&
         RailsErrorDashboard.configuration.enable_breadcrumbs &&
         defined?(Rack::Attack)
        RailsErrorDashboard::Subscribers::RackAttackSubscriber.subscribe!
      end

      # Subscribe to ActionCable AS::Notifications events (requires breadcrumbs + ActionCable)
      if RailsErrorDashboard.configuration.enable_actioncable_tracking &&
         RailsErrorDashboard.configuration.enable_breadcrumbs &&
         defined?(ActionCable)
        RailsErrorDashboard::Subscribers::ActionCableSubscriber.subscribe!
      end

      # Subscribe to ActiveStorage AS::Notifications events (requires breadcrumbs + ActiveStorage)
      if RailsErrorDashboard.configuration.enable_activestorage_tracking &&
         RailsErrorDashboard.configuration.enable_breadcrumbs &&
         defined?(ActiveStorage)
        RailsErrorDashboard::Subscribers::ActiveStorageSubscriber.subscribe!
      end

      # Enable TracePoint(:raise) for local variable and/or instance variable capture
      if RailsErrorDashboard.configuration.enable_local_variables ||
         RailsErrorDashboard.configuration.enable_instance_variables
        RailsErrorDashboard::Services::LocalVariableCapturer.enable!
      end

      # Enable TracePoint(:raise) + TracePoint(:rescue) for swallowed exception detection
      if RailsErrorDashboard.configuration.detect_swallowed_exceptions
        RailsErrorDashboard::Services::SwallowedExceptionTracker.enable!
      end

      # Import crash files from previous process death, then register at_exit hook
      if RailsErrorDashboard.configuration.enable_crash_capture
        RailsErrorDashboard::Services::CrashCapture.import!
        RailsErrorDashboard::Services::CrashCapture.enable!
      end

      # Wire issue tracker lifecycle hooks (auto-create, close on resolve, reopen on recur)
      if RailsErrorDashboard.configuration.enable_issue_tracking
        config = RailsErrorDashboard.configuration
        config.notification_callbacks[:error_logged] ||= []
        config.notification_callbacks[:error_resolved] ||= []

        # Ensure notification_callbacks entries are arrays (may be lambda from user config)
        unless config.notification_callbacks[:error_logged].is_a?(Array)
          existing = config.notification_callbacks[:error_logged]
          config.notification_callbacks[:error_logged] = [ existing ].compact
        end
        unless config.notification_callbacks[:error_resolved].is_a?(Array)
          existing = config.notification_callbacks[:error_resolved]
          config.notification_callbacks[:error_resolved] = [ existing ].compact
        end

        config.notification_callbacks[:error_logged] << ->(error_log) {
          # Dispatch to appropriate handler based on error state
          if error_log.occurrence_count == 1
            RailsErrorDashboard::Subscribers::IssueTrackerSubscriber.on_error_logged(error_log)
          elsif error_log.respond_to?(:just_reopened) && error_log.just_reopened
            RailsErrorDashboard::Subscribers::IssueTrackerSubscriber.on_error_reopened(error_log)
          else
            RailsErrorDashboard::Subscribers::IssueTrackerSubscriber.on_error_recurred(error_log)
          end
        }

        config.notification_callbacks[:error_resolved] << ->(error_log) {
          RailsErrorDashboard::Subscribers::IssueTrackerSubscriber.on_error_resolved(error_log)
        }
      end
    end
  end
end
