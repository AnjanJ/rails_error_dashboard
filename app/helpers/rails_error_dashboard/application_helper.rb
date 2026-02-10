module RailsErrorDashboard
  module ApplicationHelper
    # Returns Bootstrap color class for error severity
    # Uses Catppuccin Mocha colors in dark theme via CSS variables
    # @param severity [Symbol] The severity level (:critical, :high, :medium, :low, :info)
    # @return [String] Bootstrap color class (danger, warning, info, secondary)
    def severity_color(severity)
      case severity&.to_sym
      when :critical
        "danger"   # Maps to --ctp-red in dark mode
      when :high
        "warning"  # Maps to --ctp-peach in dark mode
      when :medium
        "info"     # Maps to --ctp-blue in dark mode
      when :low
        "secondary" # Maps to --ctp-overlay1 in dark mode
      else
        "secondary"
      end
    end

    # Returns CSS variable for severity color (for inline styles)
    # Useful when you need to set background-color or color directly
    # @param severity [Symbol] The severity level
    # @return [String] CSS variable reference
    def severity_color_var(severity)
      case severity&.to_sym
      when :critical
        "var(--ctp-red)"
      when :high
        "var(--ctp-peach)"
      when :medium
        "var(--ctp-blue)"
      when :low
        "var(--ctp-overlay1)"
      else
        "var(--ctp-overlay1)"
      end
    end

    # Returns platform-specific color class
    # @param platform [String] Platform name (ios, android, web, api)
    # @return [String] CSS color variable
    def platform_color_var(platform)
      case platform&.downcase
      when "ios"
        "var(--platform-ios)"
      when "android"
        "var(--platform-android)"
      when "web"
        "var(--platform-web)"
      when "api"
        "var(--platform-api)"
      else
        "var(--text-color)"
      end
    end

    # Returns platform icon
    # @param platform [String] Platform name (ios, android, web, api)
    # @return [String] Bootstrap icon class
    def platform_icon(platform)
      case platform&.downcase
      when "ios"
        "bi-apple"
      when "android"
        "bi-android2"
      when "web"
        "bi-globe"
      when "api"
        "bi-server"
      else
        "bi-question-circle"
      end
    end

    # Returns a sanitized hash of filter params safe for query links
    # @param extra_keys [Array<Symbol>] Additional permitted keys for specific contexts
    # @return [Hash] Whitelisted params for building URLs
    def permitted_filter_params(extra_keys: [])
      base_keys = RailsErrorDashboard::ErrorsController::FILTERABLE_PARAMS + %i[page per_page days]
      allowed_keys = base_keys + Array(extra_keys)
      params.permit(*allowed_keys).to_h.symbolize_keys
    end

    # Generates a sortable column header link
    # @param label [String] The column label to display
    # @param column [String] The column name to sort by
    # @return [String] HTML safe link with sort indicator
    def sortable_header(label, column)
      current_sort = params[:sort_by]
      current_direction = params[:sort_direction] || "desc"

      # Determine new direction: if clicking same column, toggle; otherwise default to desc
      new_direction = if current_sort == column
        current_direction == "asc" ? "desc" : "asc"
      else
        "desc"
      end

      # Choose icon based on current state
      icon = if current_sort == column
        current_direction == "asc" ? "▲" : "▼"
      else
        "⇅"  # Unsorted indicator
      end

      # Preserve whitelisted filter params while adding sort params
      link_params = permitted_filter_params.merge(sort_by: column, sort_direction: new_direction)

      link_to errors_path(link_params), class: "text-decoration-none" do
        content_tag(:span, "#{label} ", class: current_sort == column ? "fw-bold" : "") +
        content_tag(:span, icon, class: "text-muted small")
      end
    end

    # Generates a link to a git commit if repository URL is configured
    # @param git_sha [String] The git commit SHA
    # @param short [Boolean] Whether to show short SHA (7 chars) or full SHA
    # @return [String] HTML safe link to commit or plain text if no repo configured
    def git_commit_link(git_sha, short: true)
      return "" if git_sha.blank?

      config = RailsErrorDashboard.configuration
      display_sha = short ? git_sha[0..6] : git_sha

      if config.git_repository_url.present?
        # Support GitHub, GitLab, Bitbucket URL formats
        commit_url = "#{config.git_repository_url.chomp("/")}/commit/#{git_sha}"
        link_to display_sha, commit_url, class: "text-decoration-none font-monospace", target: "_blank", rel: "noopener"
      else
        content_tag(:code, display_sha, class: "font-monospace")
      end
    end

    # Renders a timestamp that will be automatically converted to user's local timezone
    # Server sends UTC timestamp, JavaScript converts to local timezone on page load
    # @param time [Time, DateTime, nil] The timestamp to display
    # @param format [Symbol] Format preset (:full, :short, :date_only, :time_only, :datetime)
    # @param fallback [String] Text to show if time is nil
    # @return [String] HTML safe span with data attributes for JS conversion
    def local_time(time, format: :full, fallback: "N/A")
      return fallback if time.nil?

      # Convert to UTC if not already
      utc_time = time.respond_to?(:utc) ? time.utc : time

      # ISO 8601 format for JavaScript parsing
      iso_time = utc_time.iso8601

      # Format presets for data-format attribute
      format_string = case format
      when :full
        "%B %d, %Y %I:%M:%S %p"  # December 31, 2024 11:59:59 PM
      when :short
        "%m/%d %I:%M%p"          # 12/31 11:59PM
      when :date_only
        "%B %d, %Y"              # December 31, 2024
      when :time_only
        "%I:%M:%S %p"            # 11:59:59 PM
      when :datetime
        "%b %d, %Y %H:%M"        # Dec 31, 2024 23:59
      else
        format.to_s
      end

      content_tag(
        :span,
        utc_time.strftime(format_string + " UTC"),  # Fallback for non-JS browsers
        class: "local-time",
        data: {
          utc: iso_time,
          format: format_string
        }
      )
    end

    # Renders a relative time ("3 hours ago") that updates automatically
    # @param time [Time, DateTime, nil] The timestamp to display
    # @param fallback [String] Text to show if time is nil
    # @return [String] HTML safe span with data attributes for JS conversion
    def local_time_ago(time, fallback: "N/A")
      return fallback if time.nil?

      # Convert to UTC if not already
      utc_time = time.respond_to?(:utc) ? time.utc : time
      iso_time = utc_time.iso8601

      content_tag(
        :span,
        time_ago_in_words(time) + " ago",  # Fallback for non-JS browsers
        class: "local-time-ago",
        data: {
          utc: iso_time
        }
      )
    end

    # Automatically converts URLs in text to clickable links that open in new window
    # Also highlights inline code wrapped in backticks with syntax highlighting
    # Also converts file paths to GitHub links if repository URL is configured
    # Supports http://, https://, and common patterns like github.com/user/repo
    # @param text [String] The text containing URLs, file paths, and inline code
    # @param error [RailsErrorDashboard::ErrorLog, nil] The error for context (to get repo URL)
    # @return [String] HTML safe text with clickable links and styled code
    def auto_link_urls(text, error: nil)
      return "" if text.blank?

      # Get repository URL from error's application or global config
      repo_url = if error&.application.respond_to?(:repository_url) && error.application.repository_url.present?
        error.application.repository_url
      elsif RailsErrorDashboard.configuration.git_repository_url.present?
        RailsErrorDashboard.configuration.git_repository_url
      end

      # First, protect inline code with backticks by replacing with placeholders
      code_blocks = []
      file_paths = []
      text_with_placeholders = text.gsub(/`([^`]+)`/) do |match|
        code_content = Regexp.last_match(1)

        # Check if the code block contains a file path pattern
        if repo_url && code_content =~ %r{^(app|lib|config|db|spec|test)/[^\s]+\.(rb|js|jsx|ts|tsx|erb|yml|yaml|json|css|scss)$}
          # It's a file path - save it and mark for GitHub linking
          file_paths << code_content
          "###FILE_PATH_#{file_paths.length - 1}###"
        else
          # Regular code block
          code_blocks << code_content
          "###CODE_BLOCK_#{code_blocks.length - 1}###"
        end
      end

      # Regex to match URLs (http://, https://, www., and common domains)
      url_regex = %r{
        (
          (?:https?://|www\.)           # http://, https://, or www.
          (?:[^\s<>"]+)                 # Domain and path (no spaces, <, >, or ")
          |
          (?:^|\s)                      # Start of string or whitespace
          (?:github\.com|gitlab\.com|bitbucket\.org|jira\.[^\s]+)
          /[^\s<>"]+                    # Path after domain
        )
      }xi

      # Replace URLs with clickable links
      linked_text = text_with_placeholders.gsub(url_regex) do |url|
        # Clean up the URL
        clean_url = url.strip

        # Add protocol if missing
        href = clean_url.start_with?("http://", "https://") ? clean_url : "https://#{clean_url}"

        # Truncate display text for very long URLs
        display_text = clean_url.length > 60 ? "#{clean_url[0..57]}..." : clean_url

        "<a href=\"#{ERB::Util.html_escape(href)}\" target=\"_blank\" rel=\"noopener noreferrer\" class=\"text-primary text-decoration-underline\">#{ERB::Util.html_escape(display_text)}</a>"
      end

      # Restore file paths with GitHub links (elvish magic! 🧝‍♀️)
      linked_text.gsub!(/###FILE_PATH_(\d+)###/) do
        file_path = file_paths[Regexp.last_match(1).to_i]
        github_url = "#{repo_url.chomp('/')}/blob/main/#{file_path}"
        "<a href=\"#{ERB::Util.html_escape(github_url)}\" target=\"_blank\" rel=\"noopener noreferrer\" class=\"text-decoration-none\" title=\"View on GitHub\">" \
        "<code class=\"inline-code-highlight file-path-link\">#{ERB::Util.html_escape(file_path)}</code></a>"
      end

      # Restore code blocks with styling
      linked_text.gsub!(/###CODE_BLOCK_(\d+)###/) do
        code_content = code_blocks[Regexp.last_match(1).to_i]
        "<code class=\"inline-code-highlight\">#{ERB::Util.html_escape(code_content)}</code>"
      end

      # Preserve line breaks and return as HTML safe
      simple_format(linked_text, {}, sanitize: false)
    end
  end
end
