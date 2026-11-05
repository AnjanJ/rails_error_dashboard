# frozen_string_literal: true

require "rails_helper"
require "yaml"
require_relative "../../benchmark/load/shapes"
require_relative "../../benchmark/load/compose_driver"

# The deploy shapes, benchmark/load/shapes.rb: the CPU and memory limits a run
# is held to, so the app sees the machine a deploy target would give it.
RSpec.describe RedBenchmark::Load::Shapes do
  def shape(name)
    RedBenchmark::Load::Shapes.fetch(name)
  end

  it "holds the app to each shape's CPUs, quota and memory, on the runner of its architecture (deploy-shape-benchmark/REQ-16)" do
    limits = described_class::ALL.to_h { |each| [ each.name, each.to_h.slice(:cpus, :quota, :memory, :runner) ] }

    expect(limits).to eq(
      "medium" => { cpus: "0,1", quota: nil, memory: "4g", runner: "ubuntu-24.04" },
      "small" => { cpus: "0", quota: nil, memory: "1g", runner: "ubuntu-24.04" },
      "medium-throttled" => { cpus: "0,1", quota: "0.4", memory: "4g", runner: "ubuntu-24.04" },
      "medium-arm" => { cpus: "0,1", quota: nil, memory: "4g", runner: "ubuntu-24.04-arm" }
    )
  end

  it "gives compose the app's limits, with swap off, and the other CPUs to everything else (deploy-shape-benchmark/REQ-16)" do
    expect(shape("medium-throttled").compose_env)
      .to eq("APP_CPUSET" => "0,1", "APP_CPUS" => "0.4", "APP_MEMORY" => "4g", "REST_CPUSET" => "2,3")
    # compose reads an empty quota as none
    expect(shape("small").compose_env)
      .to eq("APP_CPUSET" => "0", "APP_CPUS" => "", "APP_MEMORY" => "1g", "REST_CPUSET" => "2,3")
  end

  it "gives docker run the same limits, for the rows (deploy-shape-benchmark/REQ-16)" do
    expect(shape("medium-throttled").docker_args)
      .to eq([ "--cpuset-cpus=0,1", "--memory=4g", "--memory-swap=4g", "--cpus=0.4" ])
    expect(shape("small").docker_args).to eq([ "--cpuset-cpus=0", "--memory=1g", "--memory-swap=1g" ])
  end

  it "prints a shape's docker run limits one to a line, for a workflow's shell (deploy-shape-benchmark/REQ-16)" do
    output, status = Open3.capture2e(RbConfig.ruby, File.join(__dir__, "../../benchmark/load/shapes.rb"), "medium-throttled")

    expect(status).to be_success
    expect(output.lines(chomp: true)).to eq(shape("medium-throttled").docker_args)
  end

  it "refuses a shape it doesn't have, and names the ones it does (deploy-shape-benchmark/REQ-16)" do
    expect { described_class.fetch("large") }.to raise_error(KeyError, "No shape large: medium, small, medium-throttled, medium-arm")

    output, status = Open3.capture2e(RbConfig.ruby, File.join(__dir__, "../../benchmark/load/shapes.rb"), "large")
    expect(status).not_to be_success
    expect(output).to include("No shape large")
  end

  describe "benchmark/load/compose.yml" do
    let(:services) { YAML.load_file(RedBenchmark::Load::ComposeDriver::FILE).fetch("services") }

    it "holds the app to the shape's limits, and leaves it unlimited with no shape (deploy-shape-benchmark/REQ-16)" do
      expect(services.fetch("app").slice("cpuset", "cpus", "mem_limit", "memswap_limit")).to eq(
        "cpuset" => "${APP_CPUSET:-}", "cpus" => "${APP_CPUS:-0}",
        "mem_limit" => "${APP_MEMORY:-0}", "memswap_limit" => "${APP_MEMORY:-0}"
      )
    end

    it "keeps the database and k6 off the app's CPUs (deploy-shape-benchmark/REQ-16)" do
      expect(services.values_at("db", "k6").map { |service| service["cpuset"] }).to eq([ "${REST_CPUSET:-}" ] * 2)
    end
  end

  describe RedBenchmark::Load::ComposeDriver do
    it "passes the shape's limits to every compose command (deploy-shape-benchmark/REQ-16)" do
      seen = []
      success = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture3) { |env, *| seen << env; [ "", "", success ] }

      driver = described_class.new(shape: shape("small"))
      driver.up
      driver.start(red: false)

      expect(seen).to eq([ shape("small").compose_env.merge("RED" => "on"), shape("small").compose_env.merge("RED" => "off") ])
    end

    it "passes no limits with no shape (deploy-shape-benchmark/REQ-16)" do
      seen = []
      success = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture3) { |env, *| seen << env; [ "", "", success ] }

      described_class.new.start(red: true)

      expect(seen).to eq([ { "RED" => "on" } ])
    end

    it "reads how often the app's CPU quota held it back, from its container's cpu.stat (deploy-shape-benchmark/REQ-16)" do
      stat = "usage_usec 9000\nnr_periods 50\nnr_throttled 12\nthrottled_usec 345678\n"
      success = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture3)
        .with(anything, "docker", "compose", "--file", described_class::FILE, "exec", "-T", "app", "cat", "/sys/fs/cgroup/cpu.stat",
          stdin_data: "")
        .and_return([ stat, "", success ])

      expect(described_class.new.throttling).to eq(times: 12, usec: 345_678)
    end
  end
end

# Shapes on the real stack, in Docker. It takes a couple of minutes, so it runs
# only when asked:
#
#   LOAD_APP_BOOT=1 bundle exec rspec spec/benchmark/load_shapes_spec.rb
RSpec.describe "The load test's app held to a shape", if: ENV["LOAD_APP_BOOT"] == "1" do
  def held_to(name)
    driver = RedBenchmark::Load::ComposeDriver.new(shape: RedBenchmark::Load::Shapes.fetch(name))
    driver.up
    yield driver
  ensure
    driver&.down
  end

  it "sees the shape's CPUs and memory inside the app's container (deploy-shape-benchmark/REQ-16)" do
    held_to("small") do |driver|
      expect(driver.environment).to include("CPUs" => "1", "Memory limit" => "1.00 GB", "CPU limit" => "none found")
    end
  end

  it "is throttled under a quota, and says so (deploy-shape-benchmark/REQ-16)" do
    held_to("medium-throttled") do |driver|
      expect(driver.environment).to include("CPUs" => "2", "CPU limit" => "0.40 CPU", "Memory limit" => "4.00 GB")
      # Booting Rails on 0.4 of a CPU uses up the quota many times over
      expect(driver.throttling[:times]).to be_positive
    end
  end
end
