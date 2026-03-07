# frozen_string_literal: true

module RailsErrorDashboard
  # Job: Persist swallowed exception counters to the database.
  #
  # Two usage modes:
  # 1. With arguments (raise_counts, rescue_counts) — dispatched by the TracePoint
  #    periodic flush. Zero I/O in the request path; all DB writes happen here.
  # 2. Without arguments — scheduled periodic sweep that flushes the current
  #    thread's counters (useful as a cron safety net).
  #
  # Example cron (via solid_queue or whenever):
  #   every 5.minutes { RailsErrorDashboard::SwallowedExceptionFlushJob.perform_later }
  class SwallowedExceptionFlushJob < ApplicationJob
    queue_as :default

    def perform(raise_counts = nil, rescue_counts = nil)
      return unless RailsErrorDashboard.configuration.detect_swallowed_exceptions

      if raise_counts && rescue_counts
        # Mode 1: Persist provided snapshots (dispatched from TracePoint flush)
        Commands::FlushSwallowedExceptions.call(
          raise_counts: raise_counts,
          rescue_counts: rescue_counts
        )
      else
        # Mode 2: Flush current thread's counters (scheduled cron safety net)
        Services::SwallowedExceptionTracker.flush!
      end
    end
  end
end
