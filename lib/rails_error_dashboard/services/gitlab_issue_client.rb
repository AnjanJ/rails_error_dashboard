# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # GitLab REST API client for issue management.
    #
    # API Docs: https://docs.gitlab.com/api/issues/
    # Auth: Personal access token or project access token
    # Project ID: URL-encoded path ("user%2Frepo") or numeric ID
    class GitLabIssueClient < IssueTrackerClient
      def initialize(token:, repo:, api_url: nil)
        super
        @api_url = api_url || "https://gitlab.com/api/v4"
        @encoded_repo = URI.encode_www_form_component(@repo)
      end

      def create_issue(title:, body:, labels: [])
        response = http_post(
          "#{@api_url}/projects/#{@encoded_repo}/issues",
          { title: title, description: truncate_body(body), labels: labels.join(",") },
          auth_headers
        )

        if response[:status] == 201
          data = response[:body]
          success_response(url: data["web_url"], number: data["iid"])
        else
          error_response("GitLab API error (#{response[:status]}): #{response[:body]&.dig("message") || response[:error]}")
        end
      end

      def close_issue(number:)
        response = http_put(
          "#{@api_url}/projects/#{@encoded_repo}/issues/#{number}",
          { state_event: "close" },
          auth_headers
        )

        response[:status] == 200 ? success_response({}) : error_response("GitLab API error (#{response[:status]})")
      end

      def reopen_issue(number:)
        response = http_put(
          "#{@api_url}/projects/#{@encoded_repo}/issues/#{number}",
          { state_event: "reopen" },
          auth_headers
        )

        response[:status] == 200 ? success_response({}) : error_response("GitLab API error (#{response[:status]})")
      end

      def add_comment(number:, body:)
        response = http_post(
          "#{@api_url}/projects/#{@encoded_repo}/issues/#{number}/notes",
          { body: truncate_body(body) },
          auth_headers
        )

        if response[:status] == 201
          # GitLab notes don't have a direct URL — construct from issue URL + note anchor
          note_id = response[:body]["id"]
          issue_url = "#{@api_url.sub("/api/v4", "")}/#{@repo}/-/issues/#{number}#note_#{note_id}"
          success_response(url: issue_url)
        else
          error_response("GitLab API error (#{response[:status]})")
        end
      end

      def fetch_comments(number:, per_page: 10)
        response = http_get(
          "#{@api_url}/projects/#{@encoded_repo}/issues/#{number}/notes?per_page=#{per_page}&sort=desc",
          auth_headers
        )

        if response[:status] == 200
          comments = (response[:body] || []).reject { |n| n["system"] }.map { |n|
            {
              author: n.dig("author", "username"),
              avatar_url: n.dig("author", "avatar_url"),
              body: n["body"],
              created_at: n["created_at"],
              url: nil # GitLab notes don't have individual URLs in API response
            }
          }
          success_response(comments: comments)
        else
          error_response("GitLab API error (#{response[:status]})")
        end
      end

      private

      def auth_headers
        { "PRIVATE-TOKEN" => @token }
      end
    end
  end
end
