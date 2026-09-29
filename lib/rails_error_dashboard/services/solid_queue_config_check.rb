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
      # Before 1.4.0, scheduler: was not a process key: a section with only a
      # scheduler fell back to the defaults, a "*" worker and a dispatcher.
      SCHEDULER_KEY_SINCE = Gem::Version.new("1.4.0")
      GUIDE_URL = "https://anjanj.github.io/rails_error_dashboard/docs/guides/solid-queue-setup/#what-red-needs-from-solid-queue"

      # The fix printed with a reported problem. It is never Solid Queue's
      # installer: whoever sees this already uses Solid Queue, and its 1.7.0
      # installer also rewrites production.rb to use a separate queue database.
      FIX = [
        "Fix: edit the file. Give each environment a dispatchers: block and a worker",
        "for RED's queues (a \"*\" worker covers them). Guide: #{GUIDE_URL}"
      ].freeze

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
        { problems: check(parse(path), environments: environments, queue_names: queue_names), skipped: nil }
      rescue StandardError, ScriptError => e # ScriptError: ERB in the file that doesn't compile
        { problems: [], skipped: "could not read #{path}: #{e.class}: #{e.message.lines.first.to_s.strip}" }
      end

      # @param path [Pathname, String]
      # @return [Hash] the parsed file, symbolized keys, as Solid Queue reads it
      def self.parse(path)
        ActiveSupport::ConfigurationFile.parse(Pathname(path.to_s)).deep_symbolize_keys
      end

      # @param config [Hash] the parsed file, symbolized keys
      # @param environments [Array<String>]
      # @param queue_names [Array<String>]
      # @return [Array<String>] one line per problem, prefixed with the environment
      def self.check(config, environments:, queue_names:)
        environments.flat_map do |env|
          facts = processes_for(config, environment: env, queue_names: queue_names)
          problems_in(facts, queue_names).map { |problem| "#{env}: #{problem}" }
        end
      end

      # What Solid Queue would start for one environment. The contract spec
      # compares this with the real SolidQueue::Configuration and QueueSelector.
      #
      # @param config [Hash] the parsed file, symbolized keys
      # @param environment [String]
      # @param queue_names [Array<String>]
      # @param solid_queue_version [String, nil] the rules to follow; the loaded
      #   Solid Queue's by default, the newest when none is loaded
      # @return [Hash] { dispatchers: Integer, workers: Integer,
      #   processed: Array<String> (the queue_names a worker picks up), error: String or nil }
      def self.processes_for(config, environment:, queue_names:, solid_queue_version: loaded_solid_queue_version)
        section = section_for(config, environment)
        return cannot_start("the #{environment} section is not a set of settings") unless section.is_a?(Hash)

        section = section.slice(*process_keys(solid_queue_version))
        # Empty: Solid Queue runs its defaults, a "*" worker and a dispatcher.
        return { dispatchers: 1, workers: 1, processed: queue_names.dup, error: nil } if section.empty?

        error = shape_error(section)
        return cannot_start(error) if error

        # bin/jobs runs in fork mode: each worker entry starts `processes` of them.
        workers = section.fetch(:workers, []).select { |worker| worker.fetch(:processes, 1).positive? }
        {
          dispatchers: section.fetch(:dispatchers, []).size,
          workers: workers.sum { |worker| worker.fetch(:processes, 1) },
          processed: queue_names.select { |name| workers.any? { |worker| processes?(worker, name) } },
          error: nil
        }
      end

      def self.loaded_solid_queue_version
        ::SolidQueue::VERSION if defined?(::SolidQueue::VERSION)
      end

      def self.process_keys(solid_queue_version)
        return PROCESS_KEYS if solid_queue_version.nil? || Gem::Version.new(solid_queue_version) >= SCHEDULER_KEY_SINCE

        PROCESS_KEYS - [ :scheduler ]
      rescue ArgumentError # a version string Gem::Version can't read
        PROCESS_KEYS
      end
      private_class_method :process_keys

      # SolidQueue::Configuration#config_from: the environment's section when
      # present, else the whole file.
      def self.section_for(config, env)
        config[env.to_sym] ? config[env.to_sym] : config
      end
      private_class_method :section_for

      # Settings Solid Queue raises on while it builds its processes, so
      # bin/jobs can't start: a key present with no value, a map where a list
      # belongs, a list entry that isn't a set of settings, or processes that
      # isn't a whole number.
      def self.shape_error(section)
        %i[workers dispatchers].each do |key|
          next unless section.key?(key)

          list = section[key]
          return "#{key}: must be a list, each entry starting with \"- \"" unless list.is_a?(Array)
          return "every entry under #{key}: must be a set of settings" unless list.all?(Hash)
        end

        if section.fetch(:workers, []).any? { |worker| worker.key?(:processes) && !worker[:processes].is_a?(Integer) }
          return "a worker's processes: must be a whole number"
        end

        nil
      end
      private_class_method :shape_error

      def self.cannot_start(reason)
        { dispatchers: 0, workers: 0, processed: [], error: reason }
      end
      private_class_method :cannot_start

      def self.problems_in(facts, queue_names)
        return [ "Solid Queue can't start with this config: #{facts[:error]}" ] if facts[:error]

        dispatchers = facts[:dispatchers]
        workers = facts[:workers]
        return [ "no worker and no dispatcher, so no job ever runs" ] if workers.zero? && dispatchers.zero?
        return [ "no worker process starts (no workers, or processes: 0), so no job is ever performed" ] if workers.zero?

        problems = []
        if dispatchers.zero?
          problems << "workers but no dispatcher, so scheduled jobs and retries " \
                      "(retry_on wait:, perform_later(wait:)) never run, the app's own jobs included"
        end

        uncovered = queue_names - facts[:processed]
        problems << "no worker processes #{uncovered.join(' or ')}" if uncovered.any?
        problems
      end
      private_class_method :problems_in

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
