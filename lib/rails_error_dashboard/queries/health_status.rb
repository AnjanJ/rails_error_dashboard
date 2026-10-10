# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: is the error dashboard itself able to do its job right now?
    #
    # "Who watches the watchmen": if the error database is unreachable, or the
    # async queue that carries captures is misconfigured, no error ever reaches
    # the dashboard and nothing else will say so. GET /health answers that
    # question for an uptime monitor.
    #
    # Four checks, each individually rescued so one failing probe never hides
    # the others:
    #
    #   database         SELECT 1 on the ERROR database (ErrorLogsRecord's
    #                    pool, so use_separate_database is honoured), plus
    #                    "are RED's tables there". The one check that can make
    #                    the whole answer "down".
    #   errors           last capture time and the last-24h count: cheap,
    #                    both served by the occurred_at index.
    #   queue            the Active Job adapter RED's jobs run on, whether
    #                    captures are async, and the Solid Queue config
    #                    problems the boot check found (memoised per process).
    #   storm_protection the circuit breaker's current state.
    #
    # Budget: one DB round trip plus two indexed queries. No COUNT(*) over the
    # whole table (unbounded on a large install), no file reads (the Solid
    # Queue check is memoised), nothing external. Never raises.
    class HealthStatus
      OK = "ok"
      DEGRADED = "degraded"
      DOWN = "down"

      def self.call
        new.call
      end

      def call
        started = monotonic_now

        database = check_database
        checks = {
          database: database,
          # Skipped when the database is down: the queries would only fail
          # again, slower, against a server that is not answering.
          errors: database[:status] == DOWN ? skipped("database unreachable") : check_errors,
          queue: check_queue,
          storm_protection: check_storm_protection
        }

        {
          status: overall_status(checks),
          version: RailsErrorDashboard::VERSION,
          timestamp: Time.current.utc.iso8601,
          checks: checks,
          duration_ms: elapsed_ms(started)
        }
      rescue StandardError => e
        # Last line of defence: the controller must always have something to
        # render, and a health endpoint that 500s is the wrong kind of alarm.
        {
          status: DOWN,
          version: RailsErrorDashboard::VERSION,
          timestamp: Time.current.utc.iso8601,
          checks: {},
          error: e.class.name
        }
      end

      # The HTTP status the controller should answer with.
      def self.http_status_for(result)
        result[:status] == DOWN ? 503 : 200
      end

      private

      def check_database
        config = RailsErrorDashboard.configuration
        started = monotonic_now

        adapter = nil
        ErrorLogsRecord.connection_pool.with_connection do |connection|
          adapter = connection.adapter_name
          connection.select_value("SELECT 1")
        end

        tables_present = ErrorLog.table_exists?

        {
          status: tables_present ? OK : DOWN,
          adapter: adapter,
          separate_database: config.use_separate_database ? true : false,
          tables_present: tables_present,
          latency_ms: elapsed_ms(started)
        }.tap do |check|
          check[:reason] = "missing_tables" unless tables_present
        end
      rescue StandardError => e
        {
          status: DOWN,
          separate_database: RailsErrorDashboard.configuration.use_separate_database ? true : false,
          # Class only: the message can carry a host name or a connection string.
          error: e.class.name
        }
      end

      def check_errors
        last = ErrorLog.maximum(:occurred_at)
        {
          status: OK,
          last_error_at: last&.utc&.iso8601,
          last_24h: ErrorLog.where("occurred_at >= ?", 24.hours.ago).count
        }
      rescue StandardError => e
        { status: DEGRADED, error: e.class.name }
      end

      def check_queue
        config = RailsErrorDashboard.configuration
        problems = Services::SolidQueueConfigCheck.current_problems

        {
          status: problems.empty? ? OK : DEGRADED,
          async_logging: config.async_logging ? true : false,
          adapter: ApplicationJob.queue_adapter_name.to_s,
          problems: problems
        }
      rescue StandardError => e
        { status: DEGRADED, error: e.class.name }
      end

      def check_storm_protection
        enabled = RailsErrorDashboard.configuration.enable_storm_protection ? true : false
        state = enabled ? Services::StormProtection::Gate.state.to_s : "closed"

        {
          # Any state but closed means captures are being shed or merely
          # counted: the dashboard is lagging reality by design, and a monitor
          # should know.
          status: state == "closed" ? OK : DEGRADED,
          enabled: enabled,
          state: state
        }
      rescue StandardError => e
        { status: DEGRADED, error: e.class.name }
      end

      def skipped(reason)
        { status: DEGRADED, skipped: reason }
      end

      def overall_status(checks)
        statuses = checks.values.map { |c| c[:status] }
        return DOWN if statuses.include?(DOWN)
        return DEGRADED if statuses.include?(DEGRADED)

        OK
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def elapsed_ms(started)
        ((monotonic_now - started) * 1000).round(2)
      end
    end
  end
end
