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

    # Returns the current user name for filtering "My Errors"
    # Uses configured dashboard username or system username
    # @return [String] Current user identifier
    def current_user_name
      RailsErrorDashboard.configuration.dashboard_username || ENV["USER"] || "unknown"
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

      # Preserve existing filter params while adding sort params
      link_params = params.permit!.to_h.merge(sort_by: column, sort_direction: new_direction)

      link_to errors_path(link_params), class: "text-decoration-none" do
        content_tag(:span, "#{label} ", class: current_sort == column ? "fw-bold" : "") +
        content_tag(:span, icon, class: "text-muted small")
      end
    end
  end
end
