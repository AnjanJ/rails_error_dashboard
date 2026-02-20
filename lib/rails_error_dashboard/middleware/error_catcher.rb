# frozen_string_literal: true

# Rack Middleware: Final safety net for uncaught errors
# This catches errors that somehow escape controller error handling
# Positioned at the Rack layer (outermost layer of Rails)
#
# Middleware stack order (outer to inner):
# 1. ErrorCatcher (this file) ← Catches everything
# 2. ActionDispatch middleware
# 3. Rails routing
# 4. Controllers (with ErrorHandler concern)
#
# This ensures NO error goes unreported

module RailsErrorDashboard
  module Middleware
    class ErrorCatcher
      def initialize(app)
        @app = app
      end

      def call(env)
        # Record request start time for duration calculation
        env["rails_error_dashboard.request_start"] = Time.now.to_f

        @app.call(env)
      rescue => exception
        # Report to Rails.error (will be logged by our ErrorReporter)
        # CRITICAL: Wrap in rescue to ensure gem failures don't break the app
        begin
          Rails.error.report(exception,
            handled: false,
            severity: :error,
            context: {
              request: ActionDispatch::Request.new(env),
              middleware: true
            },
            source: "rack.middleware"
          )
        rescue => e
          # If error reporting fails, log it but DON'T break the app
          RailsErrorDashboard::Logger.error("[RailsErrorDashboard] Middleware error reporting failed: #{e.class} - #{e.message}")
          RailsErrorDashboard::Logger.error(e.backtrace&.first(5)&.join("\n")) if e.backtrace
        end

        # Re-raise original exception to let Rails handle the response
        raise exception
      end
    end
  end
end
