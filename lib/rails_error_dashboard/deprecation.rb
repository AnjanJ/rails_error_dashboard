# frozen_string_literal: true

require "set"

module RailsErrorDashboard
  # Says once that part of RED's public surface is going away.
  #
  # Not ActiveSupport::Deprecation: the option setters run while the host's
  # initializer loads, so in an app with deprecations set to :raise, that would
  # raise during boot. Not RailsErrorDashboard::Logger either: it's silent unless
  # enable_internal_logging is on, which would hide this from most apps.
  module Deprecation
    PREFIX = "[Rails Error Dashboard] DEPRECATION:"

    @reported = Set.new
    @lock = Mutex.new

    class << self
      # @param key [Symbol, String] what's being reported, once per process
      # @param message [String] what's deprecated, what to use instead, and the
      #   version that removes it
      # @param stderr [Boolean] also write to standard error, for a task run from cron
      # @return [void]
      def warn(key, message, stderr: false)
        return unless first_report?(key)

        line = "#{PREFIX} #{message}"
        write { Rails.logger&.warn(line) }
        write { $stderr.puts(line) } if stderr
        nil
      rescue StandardError
        nil
      end

      # For specs: one example's warning mustn't hide another's.
      def reset!
        @lock.synchronize { @reported.clear }
      end

      private

      def first_report?(key)
        @lock.synchronize { @reported.add?(key) }
      end

      # Each on its own, so a broken logger doesn't cost the stderr line.
      def write
        yield
      rescue StandardError
        nil
      end
    end
  end
end
