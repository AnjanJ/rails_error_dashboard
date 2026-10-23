# frozen_string_literal: true

# ActionDispatch::Flash is a lazy autoload, and Request#flash exists only once
# this file has run. A full-stack host loads it through its default middleware;
# an API-only host has nothing else that does, and the dashboard's layout calls
# flash on every page, including when this middleware steps aside.
require "action_dispatch/middleware/flash"

module RailsErrorDashboard
  module Middleware
    # The dashboard's own cookies and session, for an API-only host.
    #
    # An API-only Rails app runs no cookie or session middleware, but the
    # dashboard's controllers inherit ActionController::Base and need both: for
    # CSRF tokens, the flash and the language picker. The engine puts this on
    # ITS OWN middleware stack (engine.rb), which only requests routed into the
    # dashboard pass through, so the host's API endpoints stay as they are.
    #
    # A host that runs a session of its own keeps it: the dashboard then uses
    # the host's session (an authenticate_with lambda may read a Warden user
    # from it), and this steps aside.
    class DashboardSession
      COOKIE_KEY = "_rails_error_dashboard_session"

      def initialize(app)
        @app = app
        @with_session = ActionDispatch::Cookies.new(
          ActionDispatch::Session::CookieStore.new(ActionDispatch::Flash.new(app), key: COOKIE_KEY)
        )
      end

      def call(env)
        host_session?(env) ? @app.call(env) : @with_session.call(env)
      end

      private

      # Rails stores a disabled placeholder in the request on the first session
      # read when no session middleware ran, so presence alone proves nothing.
      def host_session?(env)
        session = env[Rack::RACK_SESSION]
        return false unless session

        !session.respond_to?(:enabled?) || session.enabled?
      end
    end
  end
end
