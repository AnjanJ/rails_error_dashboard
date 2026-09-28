# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# The check mirrors Solid Queue 1.7.0's own rules (SolidQueue::Configuration
# and SolidQueue::QueueSelector), so it reports exactly the configs Solid Queue
# would run with no dispatcher, no worker, or no worker for one of RED's queues.
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

    it "treats a dispatchers key with no value as no dispatcher" do
      problems = check({ production: { workers: [ { queues: "*" } ], dispatchers: nil } })

      expect(problems).to contain_exactly(a_string_including("no dispatcher"))
    end

    it "reports dispatchers with no workers" do
      problems = check({ production: { dispatchers: [ { polling_interval: 1 } ] } })

      expect(problems).to contain_exactly(a_string_including("production:", "no worker"))
    end

    it "reports a section that runs neither, such as scheduler only" do
      problems = check({ production: { scheduler: { polling_interval: 1 } } })

      expect(problems).to contain_exactly(a_string_including("no worker", "no dispatcher"))
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
end
