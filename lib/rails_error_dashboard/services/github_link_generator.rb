# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Generates links to source code on GitHub, GitLab, or Bitbucket
    # Supports commit SHA, branch, and tag references
    #
    # @example
    #   generator = GithubLinkGenerator.new(
    #     repository_url: "https://github.com/user/repo",
    #     file_path: "app/models/user.rb",
    #     line_number: 42,
    #     commit_sha: "abc123def456"
    #   )
    #   generator.generate_link
    #   # => "https://github.com/user/repo/blob/abc123def456/app/models/user.rb#L42"
    class GithubLinkGenerator
      # The generated link is an href handed to every dashboard user, so only
      # web URLs are ever linked. javascript:, data: and scp-style git@ forms
      # produce no link even though the value comes from deployer configuration.
      ALLOWED_SCHEMES = %w[http https].freeze

      attr_reader :repository_url, :file_path, :line_number, :commit_sha, :branch, :error

      # Initialize a new link generator
      #
      # @param repository_url [String] Base repository URL (GitHub, GitLab, Bitbucket)
      # @param file_path [String] Relative path to file from repository root
      # @param line_number [Integer] Line number to link to
      # @param commit_sha [String, nil] Git commit SHA (recommended for accuracy)
      # @param branch [String, nil] Branch name (fallback if no commit SHA)
      def initialize(repository_url:, file_path:, line_number:, commit_sha: nil, branch: nil)
        @repository_url = repository_url
        @file_path = file_path
        @line_number = line_number.to_i
        @commit_sha = commit_sha
        @branch = branch || "main"
        @error = nil
      end

      # Generate a link to the source file on the repository host
      #
      # @return [String, nil] URL to the source file or nil if invalid
      def generate_link
        return nil if repository_url.blank? || file_path.blank?

        # Normalize repository URL
        normalized_repo = normalize_repository_url

        unless repository_host
          @error = "Unsupported repository URL scheme: only http and https URLs are linked"
          return nil
        end

        # Determine reference (commit SHA or branch)
        reference = determine_reference

        # Generate link based on repository type
        case detect_repository_type
        when :github
          generate_github_link(normalized_repo, reference)
        when :gitlab
          generate_gitlab_link(normalized_repo, reference)
        when :bitbucket
          generate_bitbucket_link(normalized_repo, reference)
        when :codeberg
          generate_codeberg_link(normalized_repo, reference)
        else
          @error = "Unsupported repository type"
          nil
        end
      rescue StandardError => e
        @error = "Error generating link: #{e.message}"
        RailsErrorDashboard::Logger.error("GithubLinkGenerator error for #{repository_url} - #{e.message}")
        nil
      end

      private

      # Normalize repository URL (remove .git suffix, trailing slashes, etc.)
      #
      # @return [String]
      def normalize_repository_url
        url = repository_url.strip
        url = url.chomp(".git")
        url = url.chomp("/")
        url
      end

      # Host of the repository URL, downcased, or nil when the value is not an
      # http(s) URL with a host.
      #
      # @return [String, nil]
      def repository_host
        uri = URI.parse(normalize_repository_url)
        return nil unless ALLOWED_SCHEMES.include?(uri.scheme.to_s.downcase) && uri.host.present?

        uri.host.downcase
      rescue URI::InvalidURIError
        nil
      end

      # Detect repository type from the URL's host. Only the host is consulted,
      # so "github.com" appearing in a path, query string or userinfo does not
      # count. Self-hosted GitLab, Bitbucket, Gitea and Forgejo instances are
      # recognised by their conventional subdomain ("gitlab.example.com").
      #
      # @return [Symbol] :github, :gitlab, :bitbucket, :codeberg, or :unknown
      def detect_repository_type
        host = repository_host
        return :unknown unless host

        return :github if host == "github.com" || host.end_with?(".github.com")
        return :gitlab if host == "gitlab.com" || host.include?("gitlab.")
        return :bitbucket if host == "bitbucket.org" || host.include?("bitbucket.")
        return :codeberg if host == "codeberg.org" || host.include?("gitea.") || host.include?("forgejo.")

        :unknown
      end

      # Determine which reference to use (commit SHA or branch)
      #
      # @return [String]
      def determine_reference
        if commit_sha.present?
          commit_sha
        else
          branch
        end
      end

      # Normalize file path (remove leading slashes, Rails.root prefix, etc.)
      #
      # @return [String]
      def normalize_file_path
        path = file_path.strip

        # Remove leading slash
        path = path.sub(%r{^/}, "")

        # Remove Rails.root or app root prefix if present
        # Handles paths like "/Users/foo/myapp/app/models/user.rb" -> "app/models/user.rb"
        # Match pattern: look for one of the standard Rails directories
        match = path.match(%r{.*/?((?:app|lib|config|db|spec|test)/.*)$})
        if match
          path = match[1]
        end

        path
      end

      # Generate GitHub link
      #
      # Format: https://github.com/user/repo/blob/{ref}/path/to/file.rb#L42
      #
      # @param repo_url [String] Normalized repository URL
      # @param ref [String] Commit SHA or branch name
      # @return [String]
      def generate_github_link(repo_url, ref)
        normalized_path = normalize_file_path
        "#{repo_url}/blob/#{ref}/#{normalized_path}#L#{line_number}"
      end

      # Generate GitLab link
      #
      # Format: https://gitlab.com/user/repo/-/blob/{ref}/path/to/file.rb#L42
      #
      # @param repo_url [String] Normalized repository URL
      # @param ref [String] Commit SHA or branch name
      # @return [String]
      def generate_gitlab_link(repo_url, ref)
        normalized_path = normalize_file_path
        "#{repo_url}/-/blob/#{ref}/#{normalized_path}#L#{line_number}"
      end

      # Generate Bitbucket link
      #
      # Format: https://bitbucket.org/user/repo/src/{ref}/path/to/file.rb#lines-42
      #
      # @param repo_url [String] Normalized repository URL
      # @param ref [String] Commit SHA or branch name
      # @return [String]
      def generate_bitbucket_link(repo_url, ref)
        normalized_path = normalize_file_path
        "#{repo_url}/src/#{ref}/#{normalized_path}#lines-#{line_number}"
      end

      # Generate Codeberg/Gitea/Forgejo link
      #
      # Format: https://codeberg.org/user/repo/src/commit/{ref}/path/to/file.rb#L42
      # Same as GitHub's /blob/ but Codeberg uses /src/commit/ or /src/branch/
      #
      # @param repo_url [String] Normalized repository URL
      # @param ref [String] Commit SHA or branch name
      # @return [String]
      def generate_codeberg_link(repo_url, ref)
        normalized_path = normalize_file_path
        # Codeberg uses /src/commit/{sha} for commits and /src/branch/{name} for branches
        ref_type = ref.match?(/\A[0-9a-f]{7,40}\z/i) ? "commit" : "branch"
        "#{repo_url}/src/#{ref_type}/#{ref}/#{normalized_path}#L#{line_number}"
      end
    end
  end
end
