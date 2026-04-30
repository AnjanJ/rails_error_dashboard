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

      render_dashboard_error(
        icon: "bi-exclamation-triangle",
        icon_style: "background: var(--status-warning-bg); color: var(--status-warning);",
        title: "Something went wrong",
        message: "The Error Dashboard encountered an issue displaying this page. Your application is unaffected.",
        detail: exception.message,
        status: :internal_server_error
      )
    end

    # Handle record not found — return 404 instead of 500
    rescue_from ActiveRecord::RecordNotFound do |exception|
      Rails.logger.warn("[RailsErrorDashboard] Record not found: #{exception.message}")

      render_dashboard_error(
        icon: "bi-search",
        title: "The requested error was not found",
        message: "It may have been deleted or the ID is invalid.",
        detail: exception.message,
        status: :not_found
      )
    end

    # Handle Pagy pagination errors — redirect to page 1
    rescue_from Pagy::RangeError, Pagy::OptionError do |exception|
      Rails.logger.warn("[RailsErrorDashboard] Pagination error: #{exception.message}")
      redirect_to request.path, status: :moved_permanently
    end

    private

    def render_dashboard_error(icon:, title:, message:, detail: nil, icon_style: nil, status: :internal_server_error)
      set_common_view_variables
      error_html = <<~ERB
        <div class="red-empty-state" style="margin-top: var(--space-6);">
          <div class="red-empty-state-icon"#{icon_style ? " style=\"#{icon_style}\"" : ""}><i class="bi #{icon}"></i></div>
          <div class="red-empty-state-title">#{ERB::Util.html_escape(title)}</div>
          <div class="red-empty-state-message">#{ERB::Util.html_escape(message)}</div>
          #{"<div style=\"font-size: 12px; color: var(--text-tertiary); margin-top: var(--space-2); font-family: var(--font-mono);\">" + ERB::Util.html_escape(detail) + "</div>" if detail}
          <a href="#{errors_path}" class="red-empty-state-cta" style="margin-top: var(--space-4);"><i class="bi bi-arrow-left"></i> Back to errors</a>
        </div>
      ERB
      render html: error_html.html_safe, status: status, layout: "rails_error_dashboard"
    end

    def set_common_view_variables
      @applications = Application.ordered_by_name.pluck(:name, :id) rescue []
      @default_credentials_warning = RailsErrorDashboard.configuration.default_credentials? rescue false
    end
  end
end
