# frozen_string_literal: true

# Asks the real Solid Queue what it would run for each sample config, for
# spec/services/solid_queue_config_check_contract_spec.rb.
#
# It runs in a child process, never in the test process: RED branches on
# defined?(::SolidQueue), so loading Solid Queue there would change how other
# specs behave.
#
#   ruby solid_queue_probe.rb OUTPUT_PATH < input.json
#
# stdin:       { "queue_names": [...], "cases": [{ "name", "yaml", "environments" }] }
# OUTPUT_PATH: { "solid_queue_version", "results": { name => { environment =>
#                { "dispatchers", "workers", "processed", "error" } } } }
#
# The result goes to a file, not stdout, because Solid Queue prints its own
# warnings to stdout (1.3.x warns about a missing config/recurring.yml).
#
# For each environment it builds SolidQueue::Configuration from the file, the
# way bin/jobs does, and counts the dispatchers and workers it would start.
# "processed" lists the queues whose ready jobs some worker's
# SolidQueue::QueueSelector would pick up, on an in-memory database seeded
# with one ready job per queue. "error" is set when Solid Queue itself raises
# on the config, which means bin/jobs could not start.

require "bundler/setup"
require "json"
require "logger"
require "tmpdir"

ENV["DATABASE_URL"] = "sqlite3::memory:"

require "rails"
require "active_record/railtie"
require "active_job/railtie"
require "solid_queue"

PROBE_ROOT = Dir.mktmpdir("solid_queue_probe")

class SolidQueueProbeApp < Rails::Application
  config.root = PROBE_ROOT
  config.eager_load = false
  config.logger = Logger.new(nil)
  config.secret_key_base = "solid-queue-probe"
end

Rails.application.initialize!
SolidQueue.logger = Logger.new(nil)
ActiveRecord::Schema.verbose = false
load File.join(Gem.loaded_specs.fetch("solid_queue").full_gem_path,
               "lib/generators/solid_queue/install/templates/db/queue_schema.rb")

output_path = ARGV.fetch(0)
input = JSON.parse($stdin.read)
queue_names = input.fetch("queue_names")
queue_names.each do |queue_name|
  SolidQueue::Job.create!(queue_name: queue_name, class_name: "SolidQueueProbeJob", arguments: {})
end
unless SolidQueue::ReadyExecution.distinct.pluck(:queue_name).sort == queue_names.sort
  abort "probe setup: expected one ready job per queue"
end

def processed_queues(workers, queue_names)
  queue_names.select do |queue_name|
    workers.any? do |worker|
      SolidQueue::QueueSelector.new(worker.attributes[:queues], SolidQueue::ReadyExecution)
        .scoped_relations.any? { |relation| relation.where(queue_name: queue_name).exists? }
    end
  end
end

config_file = Pathname(PROBE_ROOT).join("config", "queue.yml")
config_file.dirname.mkpath

results = input.fetch("cases").to_h do |test_case|
  config_file.write(test_case.fetch("yaml"))

  per_environment = test_case.fetch("environments").to_h do |environment|
    Rails.env = environment
    processes = SolidQueue::Configuration.new(config_file: config_file, mode: :fork).configured_processes
    workers = processes.select { |process| process.kind == :worker }

    [ environment, {
      "dispatchers" => processes.count { |process| process.kind == :dispatcher },
      "workers" => workers.size,
      "processed" => processed_queues(workers, queue_names),
      "error" => nil
    } ]
  rescue StandardError => e
    [ environment, { "dispatchers" => 0, "workers" => 0, "processed" => [], "error" => "#{e.class}: #{e.message}" } ]
  end

  [ test_case.fetch("name"), per_environment ]
end

File.write(output_path, JSON.generate("solid_queue_version" => SolidQueue::VERSION, "results" => results))
