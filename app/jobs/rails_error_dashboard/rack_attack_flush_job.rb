# frozen_string_literal: true

module RailsErrorDashboard
  # Job: Persist buffered Rack::Attack event counts to the database.
  #
  # Two usage modes:
  # 1. With a counts hash — dispatched by RackAttackTracker's periodic flush.
  #    Zero I/O in the request path; all DB writes happen here.
  # 2. Without arguments — sweeps EVERY live thread's buffer.
  #
  # Mode 2 is now a belt-and-braces backstop, not the primary drain. Buffers are
  # drained at the end of each request and job by the executor hook registered in
  # the engine (see RackAttackTracker#flush_if_due!), and again at process exit.
  # Scheduling this job is therefore optional; it only ever finds counts on
  # threads that are still alive but have not completed a unit of work since
  # their deadline elapsed. It CANNOT recover counts from a thread that has
  # already died — Thread.list does not include it.
  #
  # Optional cron (via solid_queue or whenever):
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
