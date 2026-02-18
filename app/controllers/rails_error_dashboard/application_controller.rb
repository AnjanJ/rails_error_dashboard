module RailsErrorDashboard
  class ApplicationController < ActionController::Base
    include Pagy::Method

    # Enable features that are disabled in API-only mode
    # These are ONLY enabled for Error Dashboard routes, not the entire app
    include ActionController::Cookies
    include ActionController::Flash
    include ActionController::RequestForgeryProtection

    layout "rails_error_dashboard"

    protect_from_forgery with: :exception

    # CRITICAL: Ensure dashboard errors never break the app
    # Catch all exceptions and render user-friendly error page
    # NOTE: rescue_from is checked in reverse declaration order (last = highest priority).
    # The generic handler must be declared FIRST so specific handlers below take precedence.
    rescue_from StandardError do |exception|
      # Log the error for debugging
      Rails.logger.error("[RailsErrorDashboard] Dashboard controller error: #{exception.class} - #{exception.message}")
      Rails.logger.error("Request: #{request.path} (#{request.method})")
      Rails.logger.error("Params: #{params.inspect}")
      Rails.logger.error(exception.backtrace&.first(10)&.join("\n")) if exception.backtrace

      # Render user-friendly error page
      render plain: "The Error Dashboard encountered an issue displaying this page.\n\n" \
                    "Your application is unaffected - this is only a dashboard display error.\n\n" \
                    "Error: #{exception.message}\n\n" \
                    "Check Rails logs for details: [RailsErrorDashboard]",
             status: :internal_server_error,
             layout: false
    end

    # Handle record not found — return 404 instead of 500
    rescue_from ActiveRecord::RecordNotFound do |exception|
      Rails.logger.warn("[RailsErrorDashboard] Record not found: #{exception.message}")
      render plain: "The requested error was not found.\n\n" \
                    "It may have been deleted or the ID is invalid.\n\n" \
                    "Error: #{exception.message}",
             status: :not_found,
             layout: false
    end

    # Handle Pagy pagination errors — redirect to page 1
    rescue_from Pagy::RangeError, Pagy::OptionError do |exception|
      Rails.logger.warn("[RailsErrorDashboard] Pagination error: #{exception.message}")
      redirect_to request.path, status: :moved_permanently
    end
  end
end
