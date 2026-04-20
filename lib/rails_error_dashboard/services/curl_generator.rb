# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Assemble a curl command from an error log's request data
    #
    # Operates on data already stored in ErrorLog — zero runtime cost.
    # Called at display time only.
    #
    # @example
    #   RailsErrorDashboard::Services::CurlGenerator.call(error)
    #   # => "curl -X POST 'https://example.com/users' -H 'Content-Type: application/json' -d '{\"name\":\"test\"}'"
    class CurlGenerator
      BODY_METHODS = %w[ POST PUT PATCH ].freeze

      # @param error [ErrorLog] An error log record
      # @return [String] curl command string, or "" if insufficient data
      def self.call(error)
        new(error).generate
      rescue => e
        ""
      end

      def initialize(error)
        @error = error
      end

      # @return [String]
      def generate
        url = build_url
        return "" if url.blank?

        parts = [ "curl" ]

        method = @error.respond_to?(:http_method) && @error.http_method.presence
        parts << "-X #{method}" if method && method != "GET"

        parts << shell_quote(url)

        content_type = @error.respond_to?(:content_type) && @error.content_type.presence
        parts << "-H #{shell_quote("Content-Type: #{content_type}")}" if content_type

        user_agent = @error.respond_to?(:user_agent) && @error.user_agent.presence
        parts << "-H #{shell_quote("User-Agent: #{user_agent}")}" if user_agent

        if method && BODY_METHODS.include?(method.to_s.upcase)
          body = @error.respond_to?(:request_params) && @error.request_params.presence
          parts << "-d #{shell_quote(body)}" if body
        end

        parts.join(" ")
      rescue => e
        ""
      end

      private

      def build_url
        request_url = @error.respond_to?(:request_url) && @error.request_url.presence
        return nil unless request_url

        # If request_url is already a full URL, use it directly
        return request_url if request_url.start_with?("http://", "https://")

        # Otherwise, prepend hostname
        hostname = @error.respond_to?(:hostname) && @error.hostname.presence
        return nil unless hostname

        scheme = local_host?(hostname) ? "http" : "https"
        "#{scheme}://#{hostname}#{request_url}"
      end

      def shell_quote(str)
        # Replace ' with '\'' (end quote, escaped quote, start quote)
        escaped = str.to_s.gsub("'") { "'\\''" }
        "'#{escaped}'"
      end

      def local_host?(hostname)
        hostname.match?(/\A(localhost|127\.\d+\.\d+\.\d+|::1|0\.0\.0\.0)(:\d+)?\z/)
      end
    end
  end
end
