# frozen_string_literal: true

module RailsErrorDashboard
  module OverviewHelper
    def error_rate_border_class(rate)
      return "border-success" if rate < 1.0
      return "border-warning" if rate < 5.0
      "border-danger"
    end

    def error_rate_text_class(rate)
      return "text-success" if rate < 1.0
      return "text-warning" if rate < 5.0
      "text-danger"
    end

    def trend_arrow(value)
      return "→" if value.zero?
      value > 0 ? "↑" : "↓"
    end

    def trend_color_class(value)
      return "text-muted" if value.zero?
      value > 0 ? "text-danger" : "text-success"
    end

    def trend_text(direction)
      case direction
      when :increasing
        "Increasing"
      when :decreasing
        "Decreasing"
      else
        "Stable"
      end
    end

    def severity_icon(severity)
      case severity
      when :critical
        "🔴"
      when :high
        "🟠"
      when :medium
        "🟡"
      else
        "⚪"
      end
    end

    def health_status_color(status)
      case status
      when :healthy
        "success"
      when :warning
        "warning"
      else
        "danger"
      end
    end

    def health_status_text(status)
      case status
      when :healthy
        "✅ Healthy"
      when :warning
        "⚠️ Warning"
      else
        "🔴 Critical"
      end
    end
  end
end
