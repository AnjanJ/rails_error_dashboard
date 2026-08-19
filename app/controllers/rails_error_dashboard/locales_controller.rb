# frozen_string_literal: true

module RailsErrorDashboard
  # Per-user language selection for the dashboard, persisted in the session.
  #
  # Its own controller rather than another action on ErrorsController: this
  # touches no error data, and keeping it separate means the picker cannot be
  # reached by anything that filters or loads errors.
  class LocalesController < ApplicationController
    # POST /locale
    #
    # Sets session[:red_locale] and returns the user to where they were.
    #
    # The new locale takes effect on the NEXT request, not this one. That is
    # deliberate and it is what keeps the around_action ordering intact
    # (P5-T1 REQ-9): with_dashboard_locale has already resolved and set
    # Current.locale by the time this action body runs, so writing the session
    # here cannot disturb a locale that is mid-request. The redirect then
    # renders the target page under the new value.
    def create
      requested = params[:locale].to_s

      if I18nStore.available?(requested)
        # Store the canonical shipped spelling, not what the user sent.
        # I18nStore.resolve matches case-insensitively, so "PT-br" would
        # otherwise be written to the session and re-resolved on every
        # subsequent request.
        session[:red_locale] = I18nStore.resolve(requested)
      else
        # REQ-6: an unrecognized value is cleared rather than left to fail
        # silently on every later request. Falling through to config is the
        # correct behaviour, and clearing is what makes it happen.
        session.delete(:red_locale)
        flash[:alert] = red_t("red.flash.locale.unavailable")
      end

      redirect_to safe_return_path
    rescue StandardError => e
      # Session storage can be unavailable (REQ-7: an API-only host where the
      # engine's session middleware did not take effect). Changing the language
      # is never worth breaking the dashboard over — the user keeps the
      # configured locale and the page still renders.
      Rails.logger.warn("[RailsErrorDashboard] Locale selection failed: #{e.class} - #{e.message}")
      redirect_to safe_return_path
    end

    private

    # Where to send the user back to (REQ-8: same page, query params intact).
    #
    # Never trusts the raw Referer. An absolute URL from another origin would
    # turn the picker into an open redirect, so only the path and query of a
    # referer that belongs to this engine are reused; anything else falls back
    # to the dashboard root.
    def safe_return_path
      referer = request.referer.to_s
      return default_return_path if referer.empty?

      uri = URI.parse(referer)
      return default_return_path unless same_origin?(uri)

      candidate = uri.path.to_s
      return default_return_path unless candidate.start_with?(engine_mount_path)

      uri.query.present? ? "#{candidate}?#{uri.query}" : candidate
    rescue StandardError
      default_return_path
    end

    def same_origin?(uri)
      return true if uri.host.nil? # a relative referer

      uri.host == request.host && uri.port == request.port
    end

    def engine_mount_path
      path = RailsErrorDashboard::Engine.routes.find_script_name({})
      path.presence || "/"
    rescue StandardError
      "/"
    end

    def default_return_path
      overview_path
    end
  end
end
