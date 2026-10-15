# frozen_string_literal: true

module RailsErrorDashboard
  # GET /health — can the dashboard itself still capture and show errors?
  #
  # JSON only, for an uptime monitor: 200 when the error database answers,
  # 503 when it does not (status "down"). "degraded" (a storm in progress,
  # a Solid Queue config that will not run RED's jobs) is still a 200: the
  # dashboard works, with a caveat the body spells out. See
  # Queries::HealthStatus for what is probed and why.
  #
  # Authenticated like every other dashboard route (ApplicationController
  # prepends the filter): the body names the database adapter and the queue
  # backend, which is more than an anonymous caller should learn. Basic auth
  # works from any monitor; with authenticate_with, point the monitor at
  # whatever that lambda accepts.
  #
  # Its own controller rather than an ErrorsController action: no
  # application context, no storm banner, no error data is loaded here.
  class HealthController < ApplicationController
    # ApplicationController's handler renders the HTML error page. A health
    # endpoint must answer in JSON whatever happens, so this one, declared
    # later, takes precedence.
    rescue_from StandardError do |exception|
      Rails.logger.error("[RailsErrorDashboard] Health check failed: #{exception.class} - #{exception.message}")
      render json: { status: Queries::HealthStatus::DOWN, version: RailsErrorDashboard::VERSION,
                     error: exception.class.name },
             status: :service_unavailable
    end

    def show
      result = Queries::HealthStatus.call

      response.headers["Cache-Control"] = "no-store"
      render json: result, status: Queries::HealthStatus.http_status_for(result)
    end
  end
end
