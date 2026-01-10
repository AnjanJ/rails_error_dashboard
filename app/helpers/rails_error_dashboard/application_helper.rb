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

    # Returns the current user name for filtering "My Errors"
    # Uses configured dashboard username or system username
    # @return [String] Current user identifier
    def current_user_name
      RailsErrorDashboard.configuration.dashboard_username || ENV["USER"] || "unknown"
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
  end
end
