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
        # Mode 2: Flush EVERY live thread's buffer (scheduled cron safety net).
        #
        # This used to call flush!, which only ever sees Thread.current — the
        # job worker's own buffer, which is always empty. The counts live on the
        # Puma threads that served the requests, so the documented safety net
        # swept nothing. flush_all_threads! is what makes the promise true.
        Services::RackAttackTracker.flush_all_threads!
      end
    end
  end
end
