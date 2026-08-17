# frozen_string_literal: true

module RailsErrorDashboard
  module OverviewHelper
    # All helper methods return Bootstrap semantic classes (success, warning, danger)
    # These automatically map to Catppuccin Mocha colors in dark theme via CSS variables:
    # - success → --ctp-green
    # - warning → --ctp-peach
    # - danger → --ctp-red
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

    # The direction is a machine symbol; these are its display labels. An
    # unrecognized value reads as stable, which is what the English original
    # did with its else branch.
    def trend_text(direction)
      case direction
      when :increasing
        red_t("red.common.trend.increasing")
      when :decreasing
        red_t("red.common.trend.decreasing")
      else
        red_t("red.common.trend.stable")
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

    # The emoji is part of the English rendering and lives in the key so a
    # locale can drop it. These are deliberately not the
    # red.analytics.platform_comparison.health_card keys — that page renders
    # the same states without emoji.
    def health_status_text(status)
      case status
      when :healthy
        red_t("red.common.health_status.healthy")
      when :warning
        red_t("red.common.health_status.warning")
      else
        red_t("red.common.health_status.critical")
      end
    end
  end
end
