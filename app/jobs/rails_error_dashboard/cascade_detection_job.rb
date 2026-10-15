# frozen_string_literal: true

module RailsErrorDashboard
  # Finds error cascades (A reliably followed by B) in recent occurrences and
  # upserts them as CascadePattern rows, which the error page's Cascades card
  # reads.
  #
  # Nothing in the gem schedules this: run it from the host's scheduler like
  # the other periodic jobs (docs/PRODUCTION.md). Before this job existed the
  # docs said cascades were detected "hourly" by a background job that no
  # code path ever ran, so the card stayed empty on every install.
  #
  # Use a lookback equal to the interval it runs at: an hourly run with a
  # 24-hour lookback re-counts the same pairs 24 times a day.
  class CascadeDetectionJob < ApplicationJob
    queue_as :default

    # @param lookback_hours [Integer] the window of occurrences to scan
    def perform(lookback_hours: 1)
      return { detected: 0, updated: 0, skipped: "enable_error_cascades is off" } unless RailsErrorDashboard.configuration.enable_error_cascades

      result = Services::CascadeDetector.call(lookback_hours: lookback_hours.to_i.clamp(1, 24 * 30))
      Rails.logger.info("[RailsErrorDashboard] Cascade detection: #{result[:detected]} detected, #{result[:updated]} updated")
      result
    rescue => e
      Rails.logger.error("[RailsErrorDashboard] CascadeDetectionJob failed: #{e.class}: #{e.message}")
      raise
    end
  end
end
