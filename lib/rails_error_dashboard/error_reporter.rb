# frozen_string_literal: true

# Centralized Error Reporting for ALL errors in the application
# Uses Rails 7+ built-in error reporter - single source of truth
#
# This catches errors from:
# - Controllers (via ErrorHandler concern)
# - Background Jobs (via ActiveJob integration)
# - Sidekiq (via ActiveJob)
# - Services (if they use Rails.error.handle)
# - Model callbacks
# - Rake tasks
# - Console
# - Anywhere in the app
#
# Based on Rails 7+ Error Reporting Guide:
# https://guides.rubyonrails.org/error_reporting.html

module RailsErrorDashboard
  class ErrorReporter
    def report(error, handled:, severity:, context:, source: nil)
      # Skip low-severity warnings
      return if handled && severity == :warning

      # CRITICAL: Wrap entire process in rescue to ensure failures don't break the app
      begin
        # Enrich context with request data from Thread.current when available.
        # Rails internals (ActionDispatch::Executor) report errors with
        # source: "application.action_dispatch" but pass NO request object,
        # resulting in placeholder values ("Rails Application", "{}", etc.).
        # Our middleware stores the Rack env in Thread.current so we can
        # build a proper request here — fixing issue #106.
        if context[:request].nil? && Thread.current[:rails_error_dashboard_request_env]
          env = Thread.current[:rails_error_dashboard_request_env]
          context = context.merge(request: ActionDispatch::Request.new(env))
        end

        # Skip duplicate reports from our own middleware when the subscriber
        # already captured this error with full request context above.
        # Without this, async logging enqueues two jobs for one exception —
        # and non-deterministic job ordering can overwrite good data.
        if source == "rack.middleware" &&
           Thread.current[:rails_error_dashboard_reported_errors]&.include?(error.object_id)
          return
        end

        # Track that we've reported this error (for dedup with middleware)
        if Thread.current[:rails_error_dashboard_request_env]
          Thread.current[:rails_error_dashboard_reported_errors] ||= Set.new
          Thread.current[:rails_error_dashboard_reported_errors].add(error.object_id)
        end

        # Extract context information
        error_context = ValueObjects::ErrorContext.new(context, source)

        # Log to our error dashboard using Command
        Commands::LogError.call(error, error_context.to_h.merge(source: source))
      rescue => e
        # Don't let error logging cause more errors - fail silently
        # Log failure for debugging but NEVER propagate exception
        RailsErrorDashboard::Logger.error("[RailsErrorDashboard] ErrorReporter failed: #{e.class} - #{e.message}")
        RailsErrorDashboard::Logger.error("Original error: #{error.class} - #{error.message}") if error
        RailsErrorDashboard::Logger.error("Context: #{context.inspect}") if context
        RailsErrorDashboard::Logger.error(e.backtrace&.first(5)&.join("\n")) if e.backtrace
        nil # Explicitly return nil, never raise
      end
    end
  end
end
