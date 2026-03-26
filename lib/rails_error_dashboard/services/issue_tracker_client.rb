# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module RailsErrorDashboard
  module Services
    # Base class and factory for issue tracker API clients.
    #
    # Supports GitHub, GitLab, and Codeberg/Gitea/Forgejo via a unified interface.
    # Each provider implements the same methods with provider-specific API calls.
    #
    # @example
    #   client = IssueTrackerClient.for(:github, token: "ghp_xxx", repo: "user/repo")
    #   result = client.create_issue(title: "NoMethodError", body: "...", labels: ["bug"])
    #   # => { url: "https://github.com/user/repo/issues/42", number: 42 }
    class IssueTrackerClient
      REQUEST_TIMEOUT = 15 # seconds
      MAX_BODY_LENGTH = 65_000 # GitHub has ~65K limit for issue body

      attr_reader :token, :repo, :api_url

      # Factory method — returns the correct client for the provider
      #
      # @param provider [Symbol] :github, :gitlab, or :codeberg
      # @param token [String] API authentication token
      # @param repo [String] Repository identifier ("owner/repo")
      # @param api_url [String, nil] Custom API base URL (for self-hosted)
      # @return [IssueTrackerClient] Provider-specific client instance
      def self.for(provider, token:, repo:, api_url: nil)
        case provider&.to_sym
        when :github
          GitHubIssueClient.new(token: token, repo: repo, api_url: api_url)
        when :gitlab
          GitLabIssueClient.new(token: token, repo: repo, api_url: api_url)
        when :codeberg
          CodebergIssueClient.new(token: token, repo: repo, api_url: api_url)
        else
          raise ArgumentError, "Unknown issue tracker provider: #{provider}. Supported: :github, :gitlab, :codeberg"
        end
      end

      # Build a client from the current gem configuration
      #
      # @return [IssueTrackerClient, nil] Client instance or nil if not configured
      def self.from_config
        config = RailsErrorDashboard.configuration
        return nil unless config.enable_issue_tracking

        provider = config.effective_issue_tracker_provider
        token = config.effective_issue_tracker_token
        repo = config.effective_issue_tracker_repo
        api_url = config.effective_issue_tracker_api_url

        return nil unless provider && token && repo

        self.for(provider, token: token, repo: repo, api_url: api_url)
      rescue => e
        nil
      end

      def initialize(token:, repo:, api_url: nil)
        @token = token
        @repo = repo
        @api_url = api_url
      end

      # Create an issue on the platform
      # @return [Hash] { url:, number:, success: true } or { success: false, error: "..." }
      def create_issue(title:, body:, labels: [])
        raise NotImplementedError
      end

      # Close an issue
      # @return [Hash] { success: true } or { success: false, error: "..." }
      def close_issue(number:)
        raise NotImplementedError
      end

      # Reopen a closed issue
      # @return [Hash] { success: true } or { success: false, error: "..." }
      def reopen_issue(number:)
        raise NotImplementedError
      end

      # Add a comment to an issue
      # @return [Hash] { url:, success: true } or { success: false, error: "..." }
      def add_comment(number:, body:)
        raise NotImplementedError
      end

      # Fetch comments from an issue
      # @return [Hash] { comments: [...], success: true } or { success: false, error: "..." }
      def fetch_comments(number:, per_page: 10)
        raise NotImplementedError
      end

      private

      def http_post(uri, body, headers = {})
        http_request(:post, uri, body, headers)
      end

      def http_patch(uri, body, headers = {})
        http_request(:patch, uri, body, headers)
      end

      def http_put(uri, body, headers = {})
        http_request(:put, uri, body, headers)
      end

      def http_get(uri, headers = {})
        http_request(:get, uri, nil, headers)
      end

      def http_request(method, uri, body, headers)
        parsed = URI.parse(uri)
        http = Net::HTTP.new(parsed.host, parsed.port)
        http.use_ssl = parsed.scheme == "https"
        http.open_timeout = REQUEST_TIMEOUT
        http.read_timeout = REQUEST_TIMEOUT

        request = case method
        when :post then Net::HTTP::Post.new(parsed)
        when :patch then Net::HTTP::Patch.new(parsed)
        when :put then Net::HTTP::Put.new(parsed)
        when :get then Net::HTTP::Get.new(parsed)
        end

        request["Content-Type"] = "application/json"
        headers.each { |k, v| request[k] = v }
        request.body = body.to_json if body

        response = http.request(request)
        { status: response.code.to_i, body: parse_response(response.body) }
      rescue => e
        { status: 0, body: nil, error: "#{e.class}: #{e.message}" }
      end

      def parse_response(body)
        return nil if body.nil? || body.empty?
        JSON.parse(body)
      rescue JSON::ParserError
        nil
      end

      def truncate_body(body)
        return body if body.length <= MAX_BODY_LENGTH
        body[0...MAX_BODY_LENGTH] + "\n\n---\n*Truncated — full details in the error dashboard*"
      end

      def success_response(data)
        data.merge(success: true)
      end

      def error_response(message)
        { success: false, error: message }
      end
    end
  end
end
