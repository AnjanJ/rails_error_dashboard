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

        # Store request env in thread-local so the ErrorReporter subscriber
        # can access request context when Rails.error.report fires from
        # Rails internals (e.g., ActionDispatch::ShowExceptions)
        Thread.current[:rails_error_dashboard_request_env] = env

        # Initialize breadcrumb buffer for this request
        if RailsErrorDashboard.configuration.enable_breadcrumbs
          RailsErrorDashboard::Services::BreadcrumbCollector.init_buffer
        end

        @app.call(env)
      rescue => exception
        # Report to Rails.error (will be logged by our ErrorReporter)
        # CRITICAL: Wrap in rescue to ensure gem failures don't break the app
        begin
          options = {
            handled: false,
            severity: :error,
            context: {
              request: ActionDispatch::Request.new(env),
              middleware: true
            }
          }
          # Rails 7.0's ErrorReporter#report takes no source: keyword (7.1
          # added it). Passing one raised ArgumentError there, which the rescue
          # below swallowed, so on 7.0 this middleware reported nothing.
          options[:source] = "rack.middleware" if report_takes_source?
          Rails.error.report(exception, **options)
        rescue => e
          # If error reporting fails, log it but DON'T break the app
          RailsErrorDashboard::Logger.error("[RailsErrorDashboard] Middleware error reporting failed: #{e.class} - #{e.message}")
          RailsErrorDashboard::Logger.error(e.backtrace&.first(5)&.join("\n")) if e.backtrace
        end

        # Re-raise original exception to let Rails handle the response
        raise exception
      ensure
        # CRITICAL: Always clean up thread-local storage (Puma reuses threads)
        Thread.current[:rails_error_dashboard_request_env] = nil
        Thread.current[:rails_error_dashboard_reported_errors] = nil
        RailsErrorDashboard::Services::BreadcrumbCollector.clear_buffer
      end

      private

      # Asked of the reporter's class, not the object: a stubbed or wrapped
      # report method hides its real keywords.
      def report_takes_source?
        Rails.error.class.instance_method(:report).parameters.any? do |type, name|
          name == :source || type == :keyrest
        end
      end
    end
  end
end
