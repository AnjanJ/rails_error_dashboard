# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Capture on-demand diagnostic snapshot of current system state
    #
    # Aggregates data from existing services (zero duplication):
    # - SystemHealthSnapshot: GC, memory, threads, connection pool, Puma, job queue
    # - EnvironmentSnapshot: Ruby/Rails versions, gems, server, DB adapter
    # - BreadcrumbCollector: Current thread's breadcrumb buffer (non-destructive)
    #
    # Additional data unique to diagnostic dumps:
    # - Per-thread info (name, status, alive)
    # - Full GC.stat (SystemHealthSnapshot only captures a subset)
    # - ObjectSpace.count_objects (O(1) type counts — NOT each_object)
    # - Process uptime
    #
    # SAFETY RULES (HOST_APP_SAFETY.md):
    # - Every section individually wrapped in rescue => nil
    # - Never raises — returns partial dump on error
    # - No ObjectSpace.each_object (banned rule #8)
    # - No Thread.list.map(&:backtrace) (GVL hold)
    # - No Signal.trap (banned rule #9)
    class DiagnosticDumpGenerator
      def self.call
        new.call
      end

      def call
        {
          captured_at: Time.current.iso8601,
          pid: Process.pid,
          uptime_seconds: process_uptime,
          environment: environment_info,
          system_health: system_health,
          breadcrumbs: breadcrumbs,
          threads: thread_info,
          gc: gc_info,
          object_counts: object_counts
        }
      rescue => e
        { captured_at: Time.current.iso8601, error: e.message }
      end

      private

      def process_uptime
        Process.clock_gettime(Process::CLOCK_MONOTONIC) - PROCESS_START_TIME
      rescue => e
        nil
      end

      def environment_info
        EnvironmentSnapshot.snapshot.dup
      rescue => e
        nil
      end

      def system_health
        SystemHealthSnapshot.capture
      rescue => e
        nil
      end

      def breadcrumbs
        return [] unless RailsErrorDashboard.configuration.enable_breadcrumbs
        BreadcrumbCollector.current_breadcrumbs
      rescue => e
        []
      end

      def thread_info
        Thread.list.map do |t|
          { name: t.name, status: t.status, alive: t.alive? }
        rescue => e
          { name: nil, status: "unknown", alive: false }
        end
      rescue => e
        nil
      end

      def gc_info
        GC.stat
      rescue => e
        nil
      end

      def object_counts
        ObjectSpace.count_objects
      rescue => e
        nil
      end

      PROCESS_START_TIME = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      private_constant :PROCESS_START_TIME
    end
  end
end
