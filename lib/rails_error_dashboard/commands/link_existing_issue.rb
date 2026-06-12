# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Link an existing issue URL to an error record
    #
    # Parses the URL to extract provider, owner/repo, and issue number.
    # No API call needed — just stores the relationship.
    #
    # @example
    #   result = LinkExistingIssue.call(error_id, issue_url: "https://github.com/user/repo/issues/42")
    #   result[:success] # => true
    class LinkExistingIssue
      PROVIDER_PATTERNS = {
        github: %r{github\.com/([^/]+/[^/]+)/issues/(\d+)}i,
        gitlab: %r{gitlab\.com/([^/]+/[^/]+)/-/issues/(\d+)}i,
        codeberg: %r{codeberg\.org/([^/]+/[^/]+)/issues/(\d+)}i,
        # https://linear.app/<workspace>/issue/ENG-123/<slug> — capture team key + number
        linear: %r{linear\.app/[^/]+/issue/([A-Za-z][A-Za-z0-9]*)-(\d+)}i
      }.freeze

      def self.call(error_id, issue_url:)
        new(error_id, issue_url: issue_url).call
      end

      def initialize(error_id, issue_url:)
        @error_id = error_id
        @issue_url = issue_url.to_s.strip
      end

      def call
        return { success: false, error: "Issue URL is required" } if @issue_url.blank?

        error = ErrorLog.find(@error_id)
        parsed = parse_issue_url(@issue_url)

        error.update!(
          external_issue_url: @issue_url,
          external_issue_number: parsed[:number],
          external_issue_provider: parsed[:provider]&.to_s
        )

        { success: true, issue_url: @issue_url, provider: parsed[:provider] }
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Error not found: #{@error_id}" }
      rescue => e
        { success: false, error: "#{e.class}: #{e.message}" }
      end

      private

      def parse_issue_url(url)
        PROVIDER_PATTERNS.each do |provider, pattern|
          match = url.match(pattern)
          if match
            return { provider: provider, repo: match[1], number: match[2].to_i }
          end
        end

        # Unknown provider — store URL without parsed details
        # Try to extract issue number from common /issues/N pattern
        number_match = url.match(%r{/issues/(\d+)}i)
        { provider: nil, repo: nil, number: number_match&.[](1)&.to_i }
      end
    end
  end
end
