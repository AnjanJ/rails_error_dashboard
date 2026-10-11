# frozen_string_literal: true

module RailsErrorDashboard
  module Middleware
    # Rate limiting middleware for Rails Error Dashboard routes: at most
    # config.rate_limit_per_minute requests per IP per path, per minute.
    class RateLimiter
      PERIOD = 60 # seconds
      DEFAULT_LIMIT = 300 # requests per PERIOD, when rate_limit_per_minute isn't a positive number

      def initialize(app)
        @app = app
        @cache = Rails.cache
      end

      def call(env)
        return @app.call(env) unless enabled?

        request = Rack::Request.new(env)

        # Only apply rate limiting to error dashboard routes
        return @app.call(env) unless error_dashboard_route?(request.path)

        limit_config = { limit: configured_limit, period: PERIOD }

        # Check rate limit
        key = rate_limit_key(request, limit_config)
        current_count = @cache.read(key).to_i

        if current_count >= limit_config[:limit]
          return html_rate_limit_response(limit_config)
        end

        # Increment counter with expiration
        @cache.write(key, current_count + 1, expires_in: limit_config[:period].seconds)

        @app.call(env)
      end

      private

      def enabled?
        RailsErrorDashboard.configuration.enable_rate_limiting
      end

      # nil passes validation, and a limit of 0 would refuse every request.
      def configured_limit
        limit = RailsErrorDashboard.configuration.rate_limit_per_minute.to_i
        limit.positive? ? limit : DEFAULT_LIMIT
      end

      def engine_mount_path
        @engine_mount_path ||= RailsErrorDashboard.configuration.engine_mount_path
      rescue
        "/red"
      end

      # The mount itself or anything below it. A plain start_with? also
      # matched the host's own /redirect when the engine was at /red. An
      # engine mounted at "/" owns every path.
      def error_dashboard_route?(path)
        mount = engine_mount_path.to_s.chomp("/")
        return true if mount.empty?

        path == mount || path.start_with?("#{mount}/")
      end

      def rate_limit_key(request, limit_config)
        # Key format: rate_limit:IP:path:time_window
        # Time window ensures keys expire and reset
        time_window = Time.now.to_i / limit_config[:period]

        "rate_limit:#{request.ip}:#{request.path}:#{time_window}"
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
