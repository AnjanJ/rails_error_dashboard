# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# The check mirrors Solid Queue's own rules (SolidQueue::Configuration and
# SolidQueue::QueueSelector), so it reports exactly the configs Solid Queue
# would run with no dispatcher, no worker, or no worker for one of RED's queues,
# and the ones it can't start at all. solid_queue_config_check_contract_spec.rb
# checks the same rules against the real library.
RSpec.describe RailsErrorDashboard::Services::SolidQueueConfigCheck do
  let(:fixtures) { File.expand_path("../fixtures/solid_queue", __dir__) }
  let(:queue_names) { %w[default error_notifications] }

  def check(config, environments: %w[production])
    described_class.check(config, environments: environments, queue_names: queue_names)
  end

  describe ".call" do
    it "reports every environment of the config the old RED generator wrote" do
      result = described_class.call(
        File.join(fixtures, "red_generator_queue.yml"),
        environments: %w[development test production staging],
        queue_names: queue_names
      )

      expect(result[:skipped]).to be_nil
      expect(result[:problems].size).to eq(4)
      %w[development test production staging].each do |env|
        expect(result[:problems]).to include(a_string_starting_with("#{env}:").and(including("no dispatcher")))
      end
    end

    it "finds nothing wrong with Solid Queue's own install template, ERB included" do
      result = described_class.call(
        File.join(fixtures, "solid_queue_install_queue.yml"),
        environments: %w[development test production],
        queue_names: queue_names
      )

      expect(result).to eq(problems: [], skipped: nil)
    end

    it "reports a file it cannot parse as skipped instead of raising" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "queue.yml")
        File.write(path, "production:\n  workers: [unclosed\n")

        result = described_class.call(path, environments: %w[production], queue_names: queue_names)

        expect(result[:problems]).to eq([])
        expect(result[:skipped]).to include("could not read")
      end
    end

    it "reports ERB that raises as skipped instead of raising" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "queue.yml")
        File.write(path, "production:\n  workers:\n    - threads: <%= raise 'boom' %>\n")

        result = described_class.call(path, environments: %w[production], queue_names: queue_names)

        expect(result[:skipped]).to include("could not read")
      end
    end
  end

  describe ".check" do
    it "reports workers with no dispatcher" do
      problems = check({ production: { workers: [ { queues: "*" } ] } })

      expect(problems).to contain_exactly(a_string_including("production:", "no dispatcher"))
    end

    # Solid Queue raises on these while it builds its processes, so bin/jobs
    # can't start (the contract spec checks each against the real library).
    it "reports a key with no value as a config Solid Queue can't start" do
      problems = check({ production: { workers: [ { queues: "*" } ], dispatchers: nil } })

      expect(problems).to contain_exactly(a_string_including("production:", "can't start", "dispatchers: must be a list"))
    end

    it "reports a map where a list belongs as a config Solid Queue can't start" do
      problems = check({ production: { dispatchers: [ {} ], workers: { queues: "*" } } })

      expect(problems).to contain_exactly(a_string_including("can't start", "workers: must be a list"))
    end

    it "reports processes that isn't a whole number as a config Solid Queue can't start" do
      problems = check({ production: { dispatchers: [ {} ], workers: [ { processes: "2" } ] } })

      expect(problems).to contain_exactly(a_string_including("can't start", "whole number"))
    end

    it "reports workers that all have processes: 0 as no worker process" do
      problems = check({ production: { dispatchers: [ {} ], workers: [ { queues: "*", processes: 0 } ] } })

      expect(problems).to contain_exactly(a_string_including("no worker process starts"))
    end

    it "only counts the workers that start a process for RED's queues" do
      config = { production: { dispatchers: [ {} ], workers: [ { queues: "*", processes: 0 }, { queues: "default" } ] } }

      expect(check(config)).to contain_exactly(a_string_including("no worker processes error_notifications"))
    end

    it "reports dispatchers with no workers" do
      problems = check({ production: { dispatchers: [ { polling_interval: 1 } ] } })

      expect(problems).to contain_exactly(a_string_including("production:", "no worker"))
    end

    it "reports a section that runs neither, such as scheduler only" do
      problems = check({ production: { scheduler: { polling_interval: 1 } } })

      expect(problems).to contain_exactly(a_string_including("no worker", "no dispatcher"))
    end

    # Solid Queue 1.4.0 made scheduler: a process key. Before it, a section
    # with only a scheduler fell back to the defaults.
    it "follows the loaded Solid Queue's rules for a scheduler-only section" do
      config = { production: { scheduler: { polling_interval: 1 } } }

      old = described_class.processes_for(config, environment: "production", queue_names: queue_names, solid_queue_version: "1.3.2")
      new = described_class.processes_for(config, environment: "production", queue_names: queue_names, solid_queue_version: "1.4.0")

      expect(old).to include(dispatchers: 1, workers: 1)
      expect(new).to include(dispatchers: 0, workers: 0)
    end

    it "accepts a section Solid Queue fills with its defaults" do
      expect(check({ production: {} })).to eq([])
      expect(check({ production: { concurrency_maintenance: true } })).to eq([])
    end

    it "uses the top level when the environment has no section, as Solid Queue does" do
      expect(check({ workers: [ { queues: "*" } ] })).to contain_exactly(a_string_including("no dispatcher"))
      expect(check({ development: { workers: [ { queues: "*" } ] } })).to eq([])
    end

    it "treats a worker without queues as processing every queue" do
      problems = check({ production: { workers: [ { threads: 3 } ], dispatchers: [ {} ] } })

      expect(problems).to eq([])
    end

    it "reports each of RED's queues that no worker processes" do
      problems = check({ production: { workers: [ { queues: "default" } ], dispatchers: [ {} ] } })

      expect(problems).to contain_exactly(a_string_including("production:", "error_notifications"))
    end

    it "counts a trailing-wildcard prefix and a queue list" do
      config = { production: { workers: [ { queues: [ "def*", "error_*" ] } ], dispatchers: [ {} ] } }

      expect(check(config)).to eq([])
    end

    it "matches the names the app really uses, queue_name_prefix included" do
      config = { production: { workers: [ { queues: %w[default error_notifications] } ], dispatchers: [ {} ] } }

      problems = described_class.check(config, environments: %w[production],
                                               queue_names: %w[myapp_default myapp_error_notifications])

      expect(problems).to contain_exactly(a_string_including("myapp_default", "myapp_error_notifications"))
    end
  end

  describe ".red_queue_names" do
    it "returns the queues RED's jobs are enqueued on" do
      expect(described_class.red_queue_names).to contain_exactly("default", "error_notifications")
    end

    it "follows a queue_name_prefix" do
      allow(RailsErrorDashboard::AsyncErrorLoggingJob).to receive(:queue_name).and_return("myapp_default")

      expect(described_class.red_queue_names).to include("myapp_default")
    end
  end

  describe ".config_path" do
    it "honours SOLID_QUEUE_CONFIG, as Solid Queue does" do
      original = ENV["SOLID_QUEUE_CONFIG"]
      ENV["SOLID_QUEUE_CONFIG"] = "config/jobs.yml"

      expect(described_class.config_path("/app").to_s).to eq("/app/config/jobs.yml")
    ensure
      ENV["SOLID_QUEUE_CONFIG"] = original
    end

    it "defaults to config/queue.yml" do
      original = ENV.delete("SOLID_QUEUE_CONFIG")

      expect(described_class.config_path("/app").to_s).to eq("/app/config/queue.yml")
    ensure
      ENV["SOLID_QUEUE_CONFIG"] = original if original
    end
  end
  # The running app's own verdict, for the dashboard banner and one boot log
  # line: worked out once per process, never raises.
  describe ".current_problems" do
    let(:generator_config) { Pathname(File.join(fixtures, "red_generator_queue.yml")) }

    before { described_class.reset_current_problems! }
    after { described_class.reset_current_problems! }

    def with_adapter(name)
      allow(RailsErrorDashboard::ApplicationJob).to receive(:queue_adapter_name).and_return(name)
    end

    it "reports this environment's problems when Solid Queue runs RED's jobs" do
      with_adapter("solid_queue")
      allow(described_class).to receive(:config_path).and_return(generator_config)

      expect(described_class.current_problems)
        .to contain_exactly(a_string_starting_with("test:").and(including("no dispatcher")))
    end

    it "is empty when another adapter runs RED's jobs" do
      with_adapter("async")
      allow(described_class).to receive(:config_path).and_return(generator_config)

      expect(described_class.current_problems).to eq([])
    end

    it "is empty when there is no config/queue.yml" do
      with_adapter("solid_queue")
      allow(described_class).to receive(:config_path).and_return(Pathname(Dir.tmpdir).join("no-such-queue.yml"))

      expect(described_class.current_problems).to eq([])
    end

    it "reads the file once per process" do
      with_adapter("solid_queue")
      allow(described_class).to receive(:config_path).and_return(generator_config)
      allow(described_class).to receive(:call).and_call_original

      2.times { described_class.current_problems }

      expect(described_class).to have_received(:call).once
    end

    it "never raises" do
      allow(RailsErrorDashboard::ApplicationJob).to receive(:queue_adapter_name).and_raise(RuntimeError, "boom")

      expect(described_class.current_problems).to eq([])
    end

    it "logs the problems once, at error level, at boot" do
      with_adapter("solid_queue")
      allow(described_class).to receive(:config_path).and_return(generator_config)
      logger = instance_double(ActiveSupport::Logger, error: nil)

      described_class.log_current_problems(logger)

      expect(logger).to have_received(:error).once.with(/Solid Queue won't run RED's jobs in test: .*no dispatcher/)
    end

    it "logs nothing when there is no problem" do
      with_adapter("async")
      logger = instance_double(ActiveSupport::Logger, error: nil)

      described_class.log_current_problems(logger)

      expect(logger).not_to have_received(:error)
    end
  end
end
