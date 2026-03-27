# frozen_string_literal: true

module RailsErrorDashboard
  module BacktraceHelper
    # Language mapping for syntax highlighting
    LANGUAGE_MAP = {
      ".rb" => "ruby",
      ".js" => "javascript",
      ".jsx" => "javascript",
      ".ts" => "typescript",
      ".tsx" => "typescript",
      ".erb" => "erb",
      ".html" => "html",
      ".htm" => "html",
      ".css" => "css",
      ".scss" => "scss",
      ".sass" => "scss",
      ".yml" => "yaml",
      ".yaml" => "yaml",
      ".json" => "json",
      ".sql" => "sql",
      ".xml" => "xml",
      ".py" => "python",
      ".go" => "go",
      ".java" => "java",
      ".c" => "c",
      ".cpp" => "cpp",
      ".h" => "c",
      ".hpp" => "cpp",
      ".sh" => "bash",
      ".bash" => "bash",
      ".zsh" => "bash",
      ".php" => "php",
      ".pl" => "perl",
      ".r" => "r",
      ".rs" => "rust",
      ".swift" => "swift",
      ".kt" => "kotlin",
      ".scala" => "scala",
      ".clj" => "clojure",
      ".ex" => "elixir",
      ".exs" => "elixir"
    }.freeze

    # Parse backtrace string into structured frames
    def parse_backtrace(backtrace_string)
      Services::BacktraceParser.parse(backtrace_string)
    end

    # Detect programming language from file path
    # Returns Highlight.js language identifier
    def detect_language_from_path(file_path)
      return "plaintext" unless file_path

      ext = File.extname(file_path).downcase
      LANGUAGE_MAP[ext] || "plaintext"
    end

    # Filter to show only application code
    def filter_app_code(frames)
      frames.select { |f| f[:category] == :app }
    end

    # Filter to show framework/gem code
    def filter_framework_code(frames)
      frames.reject { |f| f[:category] == :app }
    end

    # Get icon for frame category
    def frame_icon(category)
      case category
      when :app
        '<i class="bi bi-code-square text-success"></i>'.html_safe
      when :gem
        '<i class="bi bi-box text-info"></i>'.html_safe
      when :framework
        '<i class="bi bi-gear text-warning"></i>'.html_safe
      when :ruby_core
        '<i class="bi bi-gem text-secondary"></i>'.html_safe
      else
        '<i class="bi bi-question-circle text-muted"></i>'.html_safe
      end
    end

    # Get color class for frame category
    def frame_color_class(category)
      case category
      when :app
        "text-success fw-bold"
      when :gem
        "text-info"
      when :framework
        "text-warning"
      when :ruby_core
        "text-secondary"
      else
        "text-muted"
      end
    end

    # Get background color class for frame
    # Uses Catppuccin-themed backtrace frame classes from _components.scss
    def frame_bg_class(category)
      case category
      when :app
        "backtrace-frame frame-app"
      when :gem
        "backtrace-frame frame-gem"
      when :framework
        "backtrace-frame frame-framework"
      when :ruby_core
        "backtrace-frame frame-ruby-core"
      else
        ""
      end
    end

    # Format category name
    def frame_category_name(category)
      case category
      when :app
        "Your Code"
      when :gem
        "Gem"
      when :framework
        "Rails Framework"
      when :ruby_core
        "Ruby Core"
      else
        "Unknown"
      end
    end

    # Count frames by category
    def frame_count_by_category(frames)
      frames.group_by { |f| f[:category] }
            .transform_values(&:count)
    end

    # Read source code for a backtrace frame
    # Returns hash with { lines:, error: } or nil
    def read_source_code(frame, context: 5)
      return nil unless RailsErrorDashboard.configuration.enable_source_code_integration
      return nil unless frame[:file_path] && frame[:line_number]

      # Cache key includes file path, line number, and git SHA if available
      cache_key = "source_code/#{frame[:file_path]}/#{frame[:line_number]}"
      cache_ttl = RailsErrorDashboard.configuration.source_code_cache_ttl || 3600

      Rails.cache.fetch(cache_key, expires_in: cache_ttl) do
        context_lines = RailsErrorDashboard.configuration.source_code_context_lines || 5
        reader = Services::SourceCodeReader.new(frame[:file_path], frame[:line_number])
        lines = reader.read_lines(context: context_lines)

        if lines
          {
            lines: lines,
            language: detect_language_from_path(frame[:file_path]),
            error: nil
          }
        else
          {
            lines: nil,
            language: nil,
            error: reader.error
          }
        end
      end
    end

    # Read coverage data for a file when coverage tracking is active
    # @return [Hash{Integer => Boolean}] line_number => executed?, or nil
    def read_coverage_for_file(file_path)
      return nil unless RailsErrorDashboard.configuration.enable_coverage_tracking
      return nil unless Services::CoverageTracker.active?

      Services::CoverageTracker.peek(file_path)
    rescue => e
      Rails.logger.error("[RailsErrorDashboard] read_coverage_for_file failed: #{e.class}: #{e.message}")
      nil
    end

    # Read git blame for a backtrace frame
    # Returns blame data hash or nil
    def read_git_blame(frame)
      return nil unless RailsErrorDashboard.configuration.enable_source_code_integration
      return nil unless RailsErrorDashboard.configuration.enable_git_blame
      return nil unless frame[:file_path] && frame[:line_number]

      # Cache key includes file path and line number
      cache_key = "git_blame/#{frame[:file_path]}/#{frame[:line_number]}"
      cache_ttl = RailsErrorDashboard.configuration.source_code_cache_ttl || 3600

      Rails.cache.fetch(cache_key, expires_in: cache_ttl) do
        reader = Services::GitBlameReader.new(frame[:file_path], frame[:line_number])
        reader.read_blame
      end
    end

    # Generate GitHub/GitLab/Bitbucket link for a frame
    # Returns URL string or nil
    def generate_repository_link(frame, error_log)
      return nil unless RailsErrorDashboard.configuration.enable_source_code_integration
      return nil unless RailsErrorDashboard.configuration.git_repository_url.present?
      return nil unless frame[:file_path] && frame[:line_number]

      repo_url = RailsErrorDashboard.configuration.git_repository_url
      commit_sha = determine_commit_sha(error_log)

      generator = Services::GithubLinkGenerator.new(
        repository_url: repo_url,
        file_path: frame[:file_path],
        line_number: frame[:line_number],
        commit_sha: commit_sha
      )

      generator.generate_link
    end

    private

    # Determine which commit SHA to use based on strategy
    def determine_commit_sha(error_log)
      strategy = RailsErrorDashboard.configuration.git_branch_strategy || :commit_sha

      case strategy
      when :commit_sha
        # Use the SHA from when the error occurred (most accurate)
        error_log.respond_to?(:git_sha) ? error_log.git_sha : nil
      when :current_branch
        # Use current branch HEAD
        get_current_git_sha
      when :main
        # Use main/master branch
        nil # Will default to "main" in GithubLinkGenerator
      else
        nil
      end
    end

    # Get current git SHA from repository
    def get_current_git_sha
      return @current_git_sha if defined?(@current_git_sha)

      @current_git_sha = begin
        `git rev-parse HEAD 2>/dev/null`.strip.presence
      rescue StandardError
        nil
      end
    end
  end
end
