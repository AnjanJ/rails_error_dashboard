# frozen_string_literal: true

module RailsErrorDashboard
  # Recalculates every error-type/platform baseline from recent history.
  #
  # Nothing in the gem schedules this: run it from the host's scheduler
  # (Solid Queue recurring tasks, sidekiq-cron, whenever, cron + runner)
  # roughly daily. Without it there are no baselines and no baseline alerts.
  class BaselineCalculationJob < ApplicationJob
    queue_as :default

    def perform
      result = Services::BaselineCalculator.calculate_all_baselines
      Rails.logger.info("[RailsErrorDashboard] Baselines recalculated: #{result[:calculated]}")
      result
    rescue => e
      Rails.logger.error("[RailsErrorDashboard] BaselineCalculationJob failed: #{e.class}: #{e.message}")
      raise
    end
  end
end
