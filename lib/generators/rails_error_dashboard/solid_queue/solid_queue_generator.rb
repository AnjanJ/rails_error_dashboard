# frozen_string_literal: true

module RailsErrorDashboard
  module Generators
    # Deprecated: checks the app's Solid Queue config for RED. Writes nothing.
    # Usage: rails generate rails_error_dashboard:solid_queue
    #
    # It used to write a config/queue.yml with workers and no dispatchers.
    # Solid Queue only falls back to its default dispatcher when a section has
    # neither, so that file ran no dispatcher: no delayed job ran, the host
    # app's own included. Solid Queue's own installer already writes a
    # config whose "*" worker processes RED's queues, so this generator now
    # only checks the file the app has. To be removed in a later minor release.
    class SolidQueueGenerator < Rails::Generators::Base
      desc "Deprecated: checks config/queue.yml for problems that stop RED's jobs. Writes nothing."

      def check_queue_config
        say "\nrails_error_dashboard:solid_queue is deprecated and no longer writes config/queue.yml.", :yellow
        say "Solid Queue's own config (bin/rails solid_queue:install) already processes RED's queues.\n\n"

        check = RailsErrorDashboard::Services::SolidQueueConfigCheck
        path = check.config_path(destination_root)
        relative = path.relative_path_from(Pathname(destination_root)).to_s

        unless path.exist?
          say "No #{relative} found. Run: bin/rails solid_queue:install", :yellow
          return
        end

        environments = check.app_environments(destination_root)
        environments = [ Rails.env.to_s ] if environments.empty?
        result = check.call(path, environments: environments)

        if result[:skipped]
          say "Could not check #{relative}: #{result[:skipped]}", :yellow
        elsif result[:problems].any?
          say "#{relative} has problems that stop jobs from running:", :red
          result[:problems].each { |problem| say "  - #{problem}", :red }
          say "\nFix: replace it with Solid Queue's own template (bin/rails solid_queue:install),", :yellow
          say "which has a \"*\" worker and a dispatchers: block.", :yellow
        else
          say "#{relative} processes RED's queues (#{check.red_queue_names.join(', ')}) and runs a dispatcher.", :green
        end
      end

      def show_instructions
        say "\nTo run RED's jobs with Solid Queue:", :cyan
        say "  config.active_job.queue_adapter = :solid_queue   (config/environments/production.rb)", :white
        say "  Run a worker: bin/jobs, or SOLID_QUEUE_IN_PUMA=1 with Puma's solid_queue plugin", :white
        say "  Check anytime: bin/rails error_dashboard:verify\n", :white
      end
    end
  end
end
