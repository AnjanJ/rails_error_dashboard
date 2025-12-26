# frozen_string_literal: true

module RailsErrorDashboard
  module BacktraceHelper
    # Parse backtrace string into structured frames
    def parse_backtrace(backtrace_string)
      Services::BacktraceParser.parse(backtrace_string)
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
    def frame_bg_class(category)
      case category
      when :app
        "bg-success bg-opacity-10"
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
  end
end
