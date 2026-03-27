# frozen_string_literal: true

module RailsErrorDashboard
  module Middleware
    # Rate limiting middleware for Rails Error Dashboard routes
    # Protects both dashboard UI and API endpoints from abuse
    class RateLimiter
      # Rate limits by endpoint type (relative to engine mount path)
      API_LIMIT = { limit: 100, period: 60 }.freeze   # 100 req/min
      DASHBOARD_LIMIT = { limit: 300, period: 60 }.freeze # 300 req/min

      def initialize(app)
        @app = app
        @cache = Rails.cache
      end

      def call(env)
        return @app.call(env) unless enabled?

        request = Rack::Request.new(env)

        # Only apply rate limiting to error dashboard routes
        return @app.call(env) unless error_dashboard_route?(request.path)

        # Find matching rate limit configuration
        limit_config = find_limit_config(request.path)
        return @app.call(env) unless limit_config

        # Check rate limit
        key = rate_limit_key(request)
        current_count = @cache.read(key).to_i

        if current_count >= limit_config[:limit]
          return rate_limit_response(request, limit_config)
        end

        # Increment counter with expiration
        @cache.write(key, current_count + 1, expires_in: limit_config[:period].seconds)

        @app.call(env)
      end

      private

      def enabled?
        RailsErrorDashboard.configuration.enable_rate_limiting
      end

      def engine_mount_path
        @engine_mount_path ||= RailsErrorDashboard.configuration.engine_mount_path
      rescue
        "/red"
      end

      def error_dashboard_route?(path)
        path.start_with?(engine_mount_path)
      end

      def find_limit_config(path)
        if path.start_with?("#{engine_mount_path}/api")
          API_LIMIT
        else
          DASHBOARD_LIMIT
        end
      end

      def rate_limit_key(request)
        # Key format: rate_limit:IP:path_prefix:time_window
        # Time window ensures keys expire and reset
        limit_config = find_limit_config(request.path)
        time_window = Time.now.to_i / limit_config[:period]

        "rate_limit:#{request.ip}:#{request.path}:#{time_window}"
      end

      def rate_limit_response(request, limit_config)
        # Return JSON for API requests, HTML for dashboard
        if request.path.start_with?("#{engine_mount_path}/api")
          json_rate_limit_response(limit_config)
        else
          html_rate_limit_response(limit_config)
        end
      end

      def json_rate_limit_response(limit_config)
        [
          429,
          {
            "Content-Type" => "application/json",
            "Retry-After" => limit_config[:period].to_s,
            "X-RateLimit-Limit" => limit_config[:limit].to_s,
            "X-RateLimit-Period" => "#{limit_config[:period]} seconds"
          },
          [ { error: "Rate limit exceeded. Please try again later." }.to_json ]
        ]
      end

      def html_rate_limit_response(limit_config)
        body = <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <title>Rate Limit Exceeded</title>
            <style>
              body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                max-width: 600px;
                margin: 100px auto;
                padding: 20px;
                text-align: center;
              }
              h1 { color: #dc3545; }
              p { color: #6c757d; line-height: 1.6; }
              .code { background: #f8f9fa; padding: 10px; border-radius: 4px; margin: 20px 0; }
            </style>
          </head>
          <body>
            <h1>⚠️ Rate Limit Exceeded</h1>
            <p>You've made too many requests to the error dashboard.</p>
            <div class="code">
              <strong>Limit:</strong> #{limit_config[:limit]} requests per #{limit_config[:period]} seconds
            </div>
            <p>Please wait a moment before trying again.</p>
          </body>
          </html>
        HTML

        [
          429,
          {
            "Content-Type" => "text/html",
            "Retry-After" => limit_config[:period].to_s,
            "X-RateLimit-Limit" => limit_config[:limit].to_s,
            "X-RateLimit-Period" => "#{limit_config[:period]} seconds"
          },
          [ body ]
        ]
      end
    end
  end
end
