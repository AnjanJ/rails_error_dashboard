module RailsErrorDashboard
  class Engine < ::Rails::Engine
    isolate_namespace RailsErrorDashboard

    # Initialize the engine
    initializer "rails_error_dashboard.middleware" do |app|
      # Add error catching middleware if enabled
      if RailsErrorDashboard.configuration.enable_middleware
        app.config.middleware.insert_before 0, RailsErrorDashboard::Middleware::ErrorCatcher
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
