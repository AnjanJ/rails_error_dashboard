# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # GitHub REST API client for issue management.
    #
    # API Docs: https://docs.github.com/en/rest/issues/issues
    # Auth: Personal access token with `repo` scope
    # Rate limit: 5,000 requests/hour per authenticated user
    class GitHubIssueClient < IssueTrackerClient
      def initialize(token:, repo:, api_url: nil)
        super
        @api_url = api_url || "https://api.github.com"
      end

      def create_issue(title:, body:, labels: [])
        response = http_post(
          "#{@api_url}/repos/#{@repo}/issues",
          { title: title, body: truncate_body(body), labels: labels },
          auth_headers
        )

        if response[:status] == 201
          data = response[:body]
          success_response(url: data["html_url"], number: data["number"])
        else
          error_response("GitHub API error (#{response[:status]}): #{response[:body]&.dig("message") || response[:error]}")
        end
      end

      def close_issue(number:)
        response = http_patch(
          "#{@api_url}/repos/#{@repo}/issues/#{number}",
          { state: "closed" },
          auth_headers
        )

        response[:status] == 200 ? success_response({}) : error_response("GitHub API error (#{response[:status]})")
      end

      def reopen_issue(number:)
        response = http_patch(
          "#{@api_url}/repos/#{@repo}/issues/#{number}",
          { state: "open" },
          auth_headers
        )

        response[:status] == 200 ? success_response({}) : error_response("GitHub API error (#{response[:status]})")
      end

      def add_comment(number:, body:)
        response = http_post(
          "#{@api_url}/repos/#{@repo}/issues/#{number}/comments",
          { body: truncate_body(body) },
          auth_headers
        )

        if response[:status] == 201
          success_response(url: response[:body]["html_url"])
        else
          error_response("GitHub API error (#{response[:status]})")
        end
      end

      def fetch_comments(number:, per_page: 10)
        response = http_get(
          "#{@api_url}/repos/#{@repo}/issues/#{number}/comments?per_page=#{per_page}&sort=created&direction=desc",
          auth_headers
        )

        if response[:status] == 200
          comments = (response[:body] || []).map { |c|
            {
              author: c.dig("user", "login"),
              avatar_url: c.dig("user", "avatar_url"),
              body: c["body"],
              created_at: c["created_at"],
              url: c["html_url"]
            }
          }
          success_response(comments: comments)
        else
          error_response("GitHub API error (#{response[:status]})")
        end
      end

      private

      def auth_headers
        { "Authorization" => "Bearer #{@token}", "Accept" => "application/vnd.github+json" }
      end
    end
  end
end
