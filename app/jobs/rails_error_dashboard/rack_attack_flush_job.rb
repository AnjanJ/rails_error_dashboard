# frozen_string_literal: true

module RailsErrorDashboard
  # Job: Persist buffered Rack::Attack event counts to the database.
  #
  # Two usage modes:
  # 1. With a counts hash — dispatched by RackAttackTracker's periodic flush.
  #    Zero I/O in the request path; all DB writes happen here.
  # 2. Without arguments — scheduled periodic sweep that flushes the current
  #    thread's buffer (useful as a cron safety net for low-traffic apps where
  #    the flush interval may not be reached during a request).
  #
  # Example cron (via solid_queue or whenever):
  #   every 5.minutes { RailsErrorDashboard::RackAttackFlushJob.perform_later }
  class RackAttackFlushJob < ApplicationJob
    queue_as :default

    def perform(counts = nil)
      return unless RailsErrorDashboard.configuration.enable_rack_attack_tracking

      if counts
        # Mode 1: Persist provided snapshot (dispatched from tracker flush)
        Commands::FlushRackAttackEvents.call(counts: counts)
      else
        # Mode 2: Flush current thread's buffer (scheduled cron safety net).
        # sync: true because we are already off the request path.
        Services::RackAttackTracker.flush!(sync: true)
      end
    end
  end
end
