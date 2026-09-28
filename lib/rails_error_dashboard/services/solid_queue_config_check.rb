# frozen_string_literal: true

require "pathname"

module RailsErrorDashboard
  module Services
    # Pure algorithm: what in a Solid Queue config would stop jobs from running
    #
    # Mirrors Solid Queue 1.7.0's own rules, so it reports exactly what Solid
    # Queue would do with the file:
    # - SolidQueue::Configuration reads the section for the environment, or the
    #   whole file when there is none, keeps workers/dispatchers/scheduler, and
    #   only falls back to its defaults (a "*" worker and a dispatcher) when
    #   none of the three is there. A section with workers and no dispatchers
    #   therefore runs NO dispatcher: nothing scheduled ever becomes ready, so
    #   no `retry_on wait:` or `perform_later(wait:)` runs, the host app's own
    #   jobs included. That is what the retired rails_error_dashboard:solid_queue
    #   generator wrote.
    # - SolidQueue::QueueSelector treats a worker without queues as "*", "*" as
    #   every queue, and a trailing "*" as a prefix.
    #
    # @example
    #   path = SolidQueueConfigCheck.config_path(Rails.root)
    #   SolidQueueConfigCheck.call(path, environments: %w[development production])
    #   # => { problems: ["production: workers but no dispatcher ..."], skipped: nil }
    class SolidQueueConfigCheck
      DEFAULT_CONFIG_FILE = "config/queue.yml"
      PROCESS_KEYS = %i[workers dispatchers scheduler].freeze

      # The config file Solid Queue reads, honouring SOLID_QUEUE_CONFIG as it does.
      #
      # @param root [Pathname, String] the application root
      # @return [Pathname]
      def self.config_path(root)
        Pathname(root.to_s).join(ENV["SOLID_QUEUE_CONFIG"].presence || DEFAULT_CONFIG_FILE)
      end

      # The environments an app defines, from config/environments/*.rb.
      #
      # @param root [Pathname, String] the application root
      # @return [Array<String>]
      def self.app_environments(root)
        Dir[Pathname(root.to_s).join("config", "environments", "*.rb").to_s]
          .map { |file| File.basename(file, ".rb") }
          .sort
      end

      # The queues RED's jobs are enqueued on, as this app names them
      # (queue_name_prefix included).
      #
      # @return [Array<String>]
      def self.red_queue_names
        [ RailsErrorDashboard::AsyncErrorLoggingJob, RailsErrorDashboard::SlackErrorNotificationJob ]
          .map { |job| job.queue_name.to_s }
          .uniq
      rescue => e
        RailsErrorDashboard::Logger.debug("SolidQueueConfigCheck could not read queue names: #{e.class}: #{e.message}")
        %w[default error_notifications]
      end

      # Read the file the way Solid Queue does (ERB, then YAML with aliases) and
      # check each environment. Never raises: an unreadable file is reported as
      # skipped.
      #
      # @param path [Pathname, String]
      # @param environments [Array<String>]
      # @param queue_names [Array<String>]
      # @return [Hash] { problems: Array<String>, skipped: String or nil }
      def self.call(path, environments:, queue_names: red_queue_names)
        config = ActiveSupport::ConfigurationFile.parse(Pathname(path.to_s)).deep_symbolize_keys
        { problems: check(config, environments: environments, queue_names: queue_names), skipped: nil }
      rescue StandardError, ScriptError => e # ScriptError: ERB in the file that doesn't compile
        { problems: [], skipped: "could not read #{path}: #{e.class}: #{e.message.lines.first.to_s.strip}" }
      end

      # @param config [Hash] the parsed file, symbolized keys
      # @param environments [Array<String>]
      # @param queue_names [Array<String>]
      # @return [Array<String>] one line per problem, prefixed with the environment
      def self.check(config, environments:, queue_names:)
        environments.flat_map do |env|
          section_problems(section_for(config, env), queue_names).map { |problem| "#{env}: #{problem}" }
        end
      end

      # SolidQueue::Configuration#config_from: the environment's section when
      # present, else the whole file.
      def self.section_for(config, env)
        section = config[env.to_sym] ? config[env.to_sym] : config
        section.is_a?(Hash) ? section.slice(*PROCESS_KEYS) : {}
      end
      private_class_method :section_for

      def self.section_problems(section, queue_names)
        # Empty: Solid Queue runs its defaults, a "*" worker and a dispatcher.
        return [] if section.empty?

        workers = Array(section[:workers])
        dispatchers = Array(section[:dispatchers])

        return [ "no worker and no dispatcher, so no job ever runs" ] if workers.empty? && dispatchers.empty?
        return [ "dispatchers but no worker, so no job is ever performed" ] if workers.empty?

        problems = []
        if dispatchers.empty?
          problems << "workers but no dispatcher, so scheduled jobs and retries " \
                      "(retry_on wait:, perform_later(wait:)) never run, the app's own jobs included"
        end

        uncovered = queue_names.reject { |name| workers.any? { |worker| processes?(worker, name) } }
        problems << "no worker processes #{uncovered.join(' or ')}" if uncovered.any?
        problems
      end
      private_class_method :section_problems

      # SolidQueue::QueueSelector: no queues means "*"; "*" is every queue; a
      # trailing "*" is a prefix.
      def self.processes?(worker, queue_name)
        queues = worker.is_a?(Hash) ? Array(worker[:queues]).map { |queue| queue.to_s.strip } : []
        queues = [ "*" ] if queues.empty?

        queues.any? do |queue|
          queue == "*" || queue == queue_name || (queue.end_with?("*") && queue_name.start_with?(queue.delete_suffix("*")))
        end
      end
      private_class_method :processes?
    end
  end
end
