# frozen_string_literal: true

require "rails_helper"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

# SolidQueueConfigCheck copies Solid Queue's rules by hand: how
# SolidQueue::Configuration reads config/queue.yml, and how
# SolidQueue::QueueSelector matches queues. This spec runs the real library on
# the same configs and checks the two agree on what Solid Queue would start.
#
# The real library runs in a child process (spec/fixtures/solid_queue/
# solid_queue_probe.rb): RED branches on defined?(::SolidQueue), so loading
# Solid Queue into this process would change how other specs behave.
#
# CI resolves the newest Solid Queue on every run, so a Solid Queue release
# that changes these rules fails here before it reaches users.
RSpec.describe RailsErrorDashboard::Services::SolidQueueConfigCheck, "agreement with the real Solid Queue" do
  fixtures = File.expand_path("../fixtures/solid_queue", __dir__)
  queue_names = %w[default error_notifications]
  dispatcher = "  dispatchers:\n    - polling_interval: 1\n"

  cases = {
    "the config the old RED generator wrote" => {
      yaml: File.read(File.join(fixtures, "red_generator_queue.yml")),
      environments: %w[development test production staging]
    },
    "Solid Queue's install template (ERB and aliases)" => {
      yaml: File.read(File.join(fixtures, "solid_queue_install_queue.yml")),
      environments: %w[development test production]
    },
    "a file with no environment sections" => { yaml: "workers:\n  - queues: \"*\"\n" },
    "a file with no section for this environment" => {
      yaml: "development:\n  workers:\n    - queues: \"*\"\n", environments: %w[development production]
    },
    "an empty environment section" => { yaml: "production: {}\n" },
    "an environment section with no value" => { yaml: "production:\n" },
    "an environment section that is not a set of settings" => { yaml: "production: workers\n" },
    "a section with no process settings" => { yaml: "production:\n  polling_interval: 1\n" },
    "a scheduler only" => { yaml: "production:\n  scheduler:\n    polling_interval: 1\n" },
    "dispatchers only" => { yaml: "production:\n#{dispatcher}" },
    "an empty workers list" => { yaml: "production:\n#{dispatcher}  workers: []\n" },
    "a worker with no queues" => { yaml: "production:\n#{dispatcher}  workers:\n    - threads: 3\n" },
    "a worker with an empty queue list" => { yaml: "production:\n#{dispatcher}  workers:\n    - queues: []\n" },
    "a queue list without error_notifications" => {
      yaml: "production:\n#{dispatcher}  workers:\n    - queues: [default, mailers]\n"
    },
    "prefix wildcards" => { yaml: "production:\n#{dispatcher}  workers:\n    - queues: [\"def*\", \"error_*\"]\n" },
    "a prefix that matches one of RED's queues" => { yaml: "production:\n#{dispatcher}  workers:\n    - queues: \"def*\"\n" },
    "queues written as one comma-separated string" => {
      yaml: "production:\n#{dispatcher}  workers:\n    - queues: \"default, error_notifications\"\n"
    },
    "several processes per worker" => {
      yaml: "production:\n#{dispatcher}  workers:\n    - queues: \"*\"\n      processes: 3\n"
    },
    "processes: 0" => { yaml: "production:\n#{dispatcher}  workers:\n    - queues: \"*\"\n      processes: 0\n" },
    "processes: 0 on one of two workers" => {
      yaml: "production:\n#{dispatcher}  workers:\n    - queues: \"*\"\n      processes: 0\n    - queues: default\n"
    },
    "processes written as a string" => {
      yaml: "production:\n#{dispatcher}  workers:\n    - queues: \"*\"\n      processes: \"2\"\n"
    },
    "workers written as a map instead of a list" => {
      yaml: "production:\n#{dispatcher}  workers:\n    queues: \"*\"\n    threads: 3\n"
    },
    "dispatchers written as a map instead of a list" => {
      yaml: "production:\n  dispatchers:\n    polling_interval: 1\n  workers:\n    - queues: \"*\"\n"
    },
    "a worker written as a bare string" => { yaml: "production:\n#{dispatcher}  workers:\n    - \"*\"\n" },
    "a workers key with no value" => { yaml: "production:\n#{dispatcher}  workers:\n" },
    "a dispatchers key with no value" => { yaml: "production:\n  dispatchers:\n  workers:\n    - queues: \"*\"\n" }
  }.transform_values { |test_case| { environments: %w[production] }.merge(test_case) }

  # One child process for every case: it boots Rails with Solid Queue.
  before(:all) do
    skip "Solid Queue needs Rails 7.1+, so it is not in this bundle" unless Gem.loaded_specs.key?("solid_queue")

    input = {
      queue_names: queue_names,
      cases: cases.map { |name, test_case| { name: name, yaml: test_case[:yaml], environments: test_case[:environments] } }
    }
    probe = File.join(fixtures, "solid_queue_probe.rb")
    Dir.mktmpdir do |dir|
      output_path = File.join(dir, "probe.json")
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, probe, output_path, stdin_data: JSON.generate(input))
      raise "Solid Queue probe failed (#{status}):\n#{stderr}\n#{stdout}" unless status.success? && File.exist?(output_path)

      @probe = JSON.parse(File.read(output_path))
    end
  end

  def facts_for(yaml, environment, queue_names)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "queue.yml")
      File.write(path, yaml)
      described_class.processes_for(described_class.parse(path), environment: environment, queue_names: queue_names,
                                                                 solid_queue_version: @probe["solid_queue_version"])
    end
  end

  cases.each do |name, test_case|
    test_case[:environments].each do |environment|
      it "agrees on #{name} (#{environment})" do
        solid_queue = @probe.dig("results", name, environment)
        ours = facts_for(test_case[:yaml], environment, queue_names)
        version = "Solid Queue #{@probe['solid_queue_version']}"

        if solid_queue["error"]
          expect(ours[:error]).to be_present,
            "#{version} can't start with this config (#{solid_queue['error']}), but the check says it can: #{ours}"
        else
          expect(ours).to eq(
            { dispatchers: solid_queue["dispatchers"], workers: solid_queue["workers"],
              processed: solid_queue["processed"], error: nil }
          ), "#{version} starts #{solid_queue.except('error')}, the check says #{ours}"
        end
      end
    end
  end
end
