module RailsErrorDashboard
  class ApplicationController < ActionController::Base
    # Authenticate EVERY dashboard controller, not just the ones that remember
    # to ask. This filter used to live on ErrorsController, which meant a new
    # controller inherited no protection at all — LocalesController (the P5-T1
    # language picker) shipped unauthenticated for exactly that reason, and an
    # unauthenticated POST reached controller code and 500'd instead of being
    # refused with a 401.
    #
    # Declaring it here inverts the default: a controller is protected unless
    # it explicitly opts out with skip_before_action, which is a visible,
    # reviewable act rather than an omission nobody notices.
    before_action :authenticate_dashboard_user!

    include Pagy::Method

    # Enable features that are disabled in API-only mode
    # These are ONLY enabled for Error Dashboard routes, not the entire app
    include ActionController::Cookies
    include ActionController::Flash
    include ActionController::RequestForgeryProtection

    # red_t for flash messages. Not the view helper — that html-escapes, and a
    # flash string is escaped again when the layout renders it.
    include Translation

    layout "rails_error_dashboard"

    protect_from_forgery with: :exception

    # Render pagination in the dashboard's own locale, not the host app's.
    #
    # Pagy stores its locale in Thread.current[:pagy_locale] and never resets it
    # (pagy 43.6.1, modules/i18n/i18n.rb:24-31 — the "for the duration of a single
    # request" comment is aspirational; nothing in the gem enforces it). A host app
    # that sets a per-request locale leaves that value on the Puma thread, so a
    # dashboard request landing on a recycled thread inherits whatever language the
    # host last used — Russian on one refresh, Portuguese on the next (issue #148).
    around_action :with_dashboard_locale

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

    # Handle Pagy pagination errors — redirect to page 1, preserving filters.
    # Drop both :page and :per_page from the preserved query string. Either can
    # trigger the rescue (page out of range, per_page negative or non-numeric);
    # carrying them into the redirect would loop the user right back into the
    # same error.
    rescue_from Pagy::RangeError, Pagy::OptionError do |exception|
      Rails.logger.warn("[RailsErrorDashboard] Pagination error: #{exception.message}")
      preserved = request.query_parameters.except("page", :page, "per_page", :per_page)
      target = preserved.any? ? "#{request.path}?#{preserved.to_query}" : request.path
      redirect_to target, status: :moved_permanently
    end

    private

    # Set the dashboard's locale for this request and restore whatever was
    # there before.
    #
    # Three details are load-bearing:
    #
    # 1. The previous value is read from Thread.current directly, NOT from
    #    Pagy::I18n.locale. The getter coerces nil to "en", so restoring through
    #    it would stamp "en" onto a thread that started clean — making the
    #    dashboard a source of the very leak it is fixing.
    # 2. around_action + ensure, not before_action. A before_action would strand
    #    the dashboard's locale on the thread for the host app's next request.
    #    The ensure also covers the rescue_from handlers above, which still
    #    render through the view layer.
    # 3. RED's own locale is set on RailsErrorDashboard::Current, NOT via
    #    I18n.with_locale. RED translates through a private backend
    #    (I18nStore); touching the host's I18n.locale would mutate host global
    #    state for no benefit and re-introduce exactly the coupling #148 removed.
    #
    # Pagy's locale and RED's are resolved independently: they ship different
    # dictionaries, so a locale RED can serve but Pagy cannot must still render
    # the UI translated, with English pagination, rather than raising.
    def with_dashboard_locale
      previous_pagy = Thread.current[:pagy_locale]
      Pagy::I18n.locale = dashboard_pagy_locale
      Current.locale = dashboard_locale
      yield
    ensure
      Thread.current[:pagy_locale] = previous_pagy
      Current.locale = nil
    end

    # The locale RED renders its own strings in. Resolved against the locales
    # RED ships (not Pagy's), and never raises.
    #
    # Precedence (P5-T1 REQ-3): session -> config.dashboard_locale -> "en".
    # The session half is applied here and the rest by locale_or_default, which
    # validates whatever it is given against the locales RED actually ships.
    # Assigning Current.locale only when the session holds a usable value keeps
    # an empty session from overriding the configured default.
    def dashboard_locale
      Current.locale = session_locale
      Current.locale_or_default
    rescue StandardError
      I18nStore::DEFAULT_LOCALE
    end

    # The user's picked locale, or nil.
    #
    # Returns nil rather than raising for every way this can go wrong: no
    # session at all (an API-only host where the engine's session middleware
    # did not take effect — REQ-7), or a tampered value (REQ-6). A garbage
    # value is not merely ignored but CLEARED, so a session poisoned once does
    # not cost a lookup on every subsequent request.
    #
    # #available? is total for any input, including an Array or a Hash, so no
    # type check is needed before it.
    def session_locale
      stored = session[:red_locale]
      return nil if stored.nil?
      return I18nStore.resolve(stored) if I18nStore.available?(stored)

      session.delete(:red_locale)
      nil
    rescue StandardError
      nil
    end

    def dashboard_pagy_locale
      configured = RailsErrorDashboard.configuration.dashboard_locale.to_s.strip
      return "en" if configured.empty?

      self.class.resolved_pagy_locales[configured] ||= resolve_pagy_locale(configured)
    rescue StandardError
      "en"
    end

    # Pagy looks its dictionary up by exact filename AND by an exact top-level
    # key inside that YAML, so "EN" finds en.yml but then reads a nil dictionary
    # and raises mid-render. Match the shipped filenames case-insensitively and
    # fall back to English for anything Pagy cannot serve.
    def resolve_pagy_locale(configured)
      available = Pagy::I18n.pathnames.flat_map { |dir| Dir.glob(dir.join("*.yml")) }
                              .map { |path| File.basename(path, ".yml") }
      available.find { |locale| locale.casecmp?(configured) } || "en"
    end

    def self.resolved_pagy_locales
      @resolved_pagy_locales ||= {}
    end

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
      # Only query when a before_action (e.g. ErrorsController#load_storm_banner)
      # hasn't already loaded it this request — the error renderer runs after
      # those callbacks, so reuse their result instead of querying a second time.
      # Tracked by a flag rather than the value, since the common case is nil.
      @storm_banner_event = Queries::StormHistory.banner_event unless @storm_banner_loaded
    end

    def authenticate_dashboard_user!
      auth_lambda = RailsErrorDashboard.configuration.authenticate_with

      if auth_lambda
        authenticate_with_lambda(auth_lambda)
      else
        authenticate_with_basic_auth
      end
    end

    def authenticate_with_lambda(auth_lambda)
      authorized = begin
        instance_exec(&auth_lambda)
      rescue => e
        Rails.logger.error(
          "[RailsErrorDashboard] authenticate_with lambda raised #{e.class}: #{e.message}"
        )
        false
      end

      return if performed?

      unless authorized
        render plain: "Access Denied", status: :forbidden
      end
    end

    def authenticate_with_basic_auth
      authenticate_or_request_with_http_basic do |username, password|
        ActiveSupport::SecurityUtils.secure_compare(
          username,
          RailsErrorDashboard.configuration.dashboard_username
        ) &
        ActiveSupport::SecurityUtils.secure_compare(
          password,
          RailsErrorDashboard.configuration.dashboard_password
        )
      end
    end
  end
end
