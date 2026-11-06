# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"
require "yaml"
require_relative "../../benchmark/load/shapes"
require_relative "../../benchmark/load/compose_driver"
require_relative "compose_files"

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

  describe "the network delay to the database" do
    let(:script) { File.join(__dir__, "../../benchmark/load/shapes.rb") }

    it "is 1 ms on every shape (deploy-shape-benchmark/REQ-17)" do
      expect(described_class::ALL.to_h { |each| [ each.name, each.delay_ms ] })
        .to eq("medium" => 1, "small" => 1, "medium-throttled" => 1, "medium-arm" => 1)
    end

    it "is added by tc netem, in a pinned container sharing the database's network (deploy-shape-benchmark/REQ-17)" do
      expect(described_class.netem("abc123", 1)).to eq([
        "docker", "run", "--rm", "--network", "container:abc123", "--cap-add", "NET_ADMIN", described_class::NETEM_IMAGE,
        "sh", "-c", "apk add --no-cache --quiet iproute2 && tc qdisc add dev eth0 root netem delay 1ms"
      ])
      expect(described_class::NETEM_IMAGE).to match(/\Aalpine:3\.20@sha256:\h{64}\z/)
    end

    it "is reported as the round trip measured, the part of it added, and the setting (deploy-shape-benchmark/REQ-17)" do
      expect(described_class.round_trip_line(0.08, 1.12, 1)).to eq("1.12 ms, 1.04 ms of it added (1 ms set)")
      expect(described_class.round_trip_line(0.08, 0.09, nil)).to eq("0.09 ms, nothing added")
      expect(described_class.round_trip_line(nil, 1.12, 1)).to eq("not available")
      expect(described_class.round_trip_line(0.08, nil, 1)).to eq("not available")
    end

    it "is measured as the median of TCP connects, and reads nil where nothing answers (deploy-shape-benchmark/REQ-17)" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      expect(described_class.round_trip("127.0.0.1", port, connects: 5)).to be_between(0, 50)

      server.close
      expect(described_class.round_trip("127.0.0.1", port, connects: 5)).to be_nil
    end

    # By name, every connect also asked Docker's DNS, and on a runner that read
    # 7.56 ms with the 1 ms delay lost in it.
    it "resolves the host's name once, so the round trip doesn't time a lookup (deploy-shape-benchmark/REQ-17)" do
      server = TCPServer.new("localhost", 0)
      port = server.addr[1]
      allow(Addrinfo).to receive(:getaddrinfo).and_call_original
      allow(TCPSocket).to receive(:new).and_call_original

      expect(described_class.round_trip("localhost", port, connects: 5)).to be_between(0, 50)
      expect(Addrinfo).to have_received(:getaddrinfo).once
      expect(TCPSocket).to have_received(:new).with(server.addr[3], port, connect_timeout: 2).exactly(5).times
    ensure
      server&.close
    end

    it "is added from a workflow's shell for a shape, and refuses what it can't use (deploy-shape-benchmark/REQ-17)" do
      output, status = Open3.capture2e(RbConfig.ruby, script, "--delay", "medium")
      expect(status).not_to be_success
      expect(output).to include("Usage: ruby benchmark/load/shapes.rb --delay SHAPE CONTAINER HOST PORT")

      output, status = Open3.capture2e(RbConfig.ruby, script, "--delay", "large", "abc123", "127.0.0.1", "5432")
      expect(status).not_to be_success
      expect(output).to include("No shape large")

      output, status = Open3.capture2e(RbConfig.ruby, script, "--delay", "medium", "abc123", "127.0.0.1", "6379", "Redis", "extra")
      expect(status).not_to be_success
      expect(output).to include("Usage: ruby benchmark/load/shapes.rb --delay SHAPE CONTAINER HOST PORT")
    end

    # docker is a stand-in that succeeds, so the delay "arrives" and only the
    # summary line is read
    it "names the part it delayed in its summary, the database unless told another (deploy-shape-benchmark/REQ-17)" do
      Dir.mktmpdir do |bin|
        File.write(File.join(bin, "docker"), "#!/bin/sh\nexit 0\n")
        File.chmod(0o755, File.join(bin, "docker"))
        server = TCPServer.new("127.0.0.1", 0)
        accepting = Thread.new { loop { server.accept.close } }
        env = { "PATH" => "#{bin}:#{ENV.fetch("PATH")}" }
        port = server.addr[1].to_s

        output, status = Open3.capture2e(env, RbConfig.ruby, script, "--delay", "medium", "abc123", "127.0.0.1", port, "Redis")
        expect(status).to be_success, output
        expect(output).to match(/\ARows' Redis round trip: [\d.]+ ms, -?[\d.]+ ms of it added \(1 ms set\)\n\z/)

        output, status = Open3.capture2e(env, RbConfig.ruby, script, "--delay", "medium", "abc123", "127.0.0.1", port)
        expect(status).to be_success, output
        expect(output).to start_with("Rows' database round trip: ")
      ensure
        accepting&.kill
        server&.close
      end
    end
  end

  describe "benchmark/load/compose.yml" do
    let(:services) { YAML.load_file(File.join(RedBenchmark::Load::Stacks::LOAD, "compose.yml")).fetch("services") }

    it "holds the app to the shape's limits, and leaves it unlimited with no shape (deploy-shape-benchmark/REQ-16)" do
      expect(services.fetch("app").slice("cpuset", "cpus", "mem_limit", "memswap_limit")).to eq(
        "cpuset" => "${APP_CPUSET:-}", "cpus" => "${APP_CPUS:-0}",
        "mem_limit" => "${APP_MEMORY:-0}", "memswap_limit" => "${APP_MEMORY:-0}"
      )
    end

    it "keeps every stack's database, Redis and k6 off the app's CPUs (deploy-shape-benchmark/REQ-16)" do
      rest = RedBenchmark::Load::Stacks.names.to_h do |name|
        others = ComposeFiles.merged(RedBenchmark::Load::Stacks.fetch(name)).fetch("services").except("app")
        [ name, others.transform_values { |service| service["cpuset"] } ]
      end

      expect(rest).to eq(
        "postgres-solid-queue" => { "db" => "${REST_CPUSET:-}", "k6" => "${REST_CPUSET:-}" },
        "postgres-sidekiq" => { "db" => "${REST_CPUSET:-}", "redis" => "${REST_CPUSET:-}", "k6" => "${REST_CPUSET:-}" },
        "mysql-solid-queue" => { "db" => "${REST_CPUSET:-}", "k6" => "${REST_CPUSET:-}" },
        "sqlite-solid-queue" => { "k6" => "${REST_CPUSET:-}" }
      )
    end
  end

  describe RedBenchmark::Load::ComposeDriver do
    let(:stacks) { RedBenchmark::Load::Stacks }

    # Answers each command as Docker would, and keeps them in order: compose ps
    # gives a service's container, Ruby in the app's container the next round
    # trip to the host it was asked about, and bin/rails runner the
    # environment block.
    def stub_docker(round_trips: { "db" => [ "0.08", "1.12" ] }, fail_netem: false)
      calls = []
      @scripts = []
      allow(Open3).to receive(:capture3) do |env, *argv, stdin_data: ""|
        calls << [ env, argv ]
        @scripts << stdin_data if argv.last(2) == [ "ruby", "-" ]
        output = if argv.include?("ps") then "#{argv.last}-container\n"
        elsif argv.last(2) == [ "ruby", "-" ] then round_trips.fetch(stdin_data.scan(/round_trip\("(\w+)"/).flatten.last).shift.to_s
        elsif argv.include?("runner") then %({"Ruby":"3.4.12","RED commit":"unknown"}\n)
        else ""
        end
        failed = fail_netem && argv.first(2) == [ "docker", "run" ]
        [ output, failed ? "RTNETLINK answers: Operation not permitted" : "", instance_double(Process::Status, success?: !failed) ]
      end
      calls
    end

    def compose_calls(calls)
      calls.select { |_env, argv| argv.first(2) == [ "docker", "compose" ] }
    end

    it "passes the shape's limits to every compose command (deploy-shape-benchmark/REQ-16)" do
      calls = stub_docker
      driver = described_class.new(shape: shape("small"))
      driver.up
      driver.start(red: false)

      expect(compose_calls(calls).map(&:first)).to all(include(shape("small").compose_env))
      expect(compose_calls(calls).filter_map { |env, _argv| env["RED"] }).to eq(%w[on off])
    end

    it "passes no limits with no shape (deploy-shape-benchmark/REQ-16)" do
      calls = stub_docker
      described_class.new.start(red: true)

      expect(calls.map(&:first)).to eq([ { "APP_RUBY" => "3.4", "RED" => "on" } ])
    end

    it "runs the default stack on Ruby 3.4 unless told another, through the stack's compose files (deploy-shape-benchmark/REQ-16)" do
      calls = stub_docker
      described_class.new.start(red: true)
      described_class.new(stack: stacks.fetch("mysql-solid-queue"), ruby: "4.0").start(red: true)

      expect(calls.map(&:first).map { |env| env["APP_RUBY"] }).to eq(%w[3.4 4.0])
      expect(calls.map(&:last).map { |argv| argv.each_cons(2).filter_map { |flag, file| file if flag == "--file" } }).to eq([
        stacks.fetch("postgres-solid-queue").compose_files.map { |file| File.join(stacks::LOAD, file) },
        stacks.fetch("mysql-solid-queue").compose_files.map { |file| File.join(stacks::LOAD, file) }
      ])
    end

    it "delays the database's network once the stack is up, and reports the round trip from the app (deploy-shape-benchmark/REQ-17)" do
      calls = stub_docker
      driver = described_class.new(shape: shape("small"))
      driver.up

      commands = calls.map(&:last)
      netem = commands.index(RedBenchmark::Load::Shapes.netem("db-container", 1))
      expect(netem).to be > commands.index { |argv| argv.include?("up") }
      # Measured from the app's container, before the delay and after it
      expect(commands.first(netem).count { |argv| argv.last(2) == [ "ruby", "-" ] && argv.include?("app") }).to eq(1)
      expect(driver.environment).to include("Stack" => "postgres-solid-queue",
        "Database round trip" => "1.12 ms, 1.04 ms of it added (1 ms set)")
    end

    it "delays Redis as well as the database on Sidekiq's stack, and reports both round trips (deploy-shape-benchmark/REQ-17)" do
      calls = stub_docker(round_trips: { "db" => [ "0.08", "1.12" ], "redis" => [ "0.05", "1.10" ] })
      driver = described_class.new(shape: shape("medium"), stack: stacks.fetch("postgres-sidekiq"))
      driver.up

      expect(calls.map(&:last)).to include(RedBenchmark::Load::Shapes.netem("db-container", 1),
        RedBenchmark::Load::Shapes.netem("redis-container", 1))
      expect(driver.environment).to include("Stack" => "postgres-sidekiq",
        "Database round trip" => "1.12 ms, 1.04 ms of it added (1 ms set)",
        "Redis round trip" => "1.10 ms, 1.05 ms of it added (1 ms set)")
    end

    it "measures the round trip to MySQL on its own port (deploy-shape-benchmark/REQ-17)" do
      stub_docker
      described_class.new(shape: shape("medium"), stack: stacks.fetch("mysql-solid-queue")).up

      expect(@scripts).to match([ a_string_ending_with(%(print RedBenchmark::Load::Shapes.round_trip("db", 3306)\n)) ])
    end

    it "adds no delay on SQLite's stack, which has nothing across the network, and says so (deploy-shape-benchmark/REQ-17)" do
      calls = stub_docker(round_trips: {})
      driver = described_class.new(shape: shape("medium"), stack: stacks.fetch("sqlite-solid-queue"))
      driver.up

      expect(calls.map(&:last)).not_to include(start_with("docker", "run"))
      expect(calls.map(&:last)).not_to include(end_with("ruby", "-"))
      environment = driver.environment
      expect(environment).to include("Stack" => "sqlite-solid-queue", "Database round trip" => "none: SQLite is a file in the app's container")
      expect(environment).not_to have_key("Redis round trip")
    end

    it "adds no delay with no shape, and still reports the round trip (deploy-shape-benchmark/REQ-17)" do
      calls = stub_docker(round_trips: { "db" => [ "0.08", "0.09" ] })
      driver = described_class.new
      driver.up

      expect(calls.map(&:last)).not_to include(start_with("docker", "run"))
      expect(driver.environment).to include("Database round trip" => "0.09 ms, nothing added")
    end

    it "stops the run when it can't add the delay, rather than measure without it (deploy-shape-benchmark/REQ-17)" do
      stub_docker(fail_netem: true)

      expect { described_class.new(shape: shape("small")).up }
        .to raise_error(RedBenchmark::Load::Error, /Operation not permitted/)
    end

    it "reads how often the app's CPU quota held it back, from its container's cpu.stat (deploy-shape-benchmark/REQ-16)" do
      stat = "usage_usec 9000\nnr_periods 50\nnr_throttled 12\nthrottled_usec 345678\n"
      success = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture3)
        .with(anything, "docker", "compose", *stacks.fetch(stacks::DEFAULT).compose_args, "exec", "-T", "app", "cat", "/sys/fs/cgroup/cpu.stat",
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

  # On a runner, 1 ms set added 1.06 and 1.07 ms in the probe, and the 20% that
  # T17 asks for is judged on a dispatch. Docker Desktop's VM overshoots: three
  # tries there added 1.08, 1.28 and 1.19 ms. So this only checks the delay
  # arrived, at about its size.
  it "adds about the shape's delay to the app's round trip to the database (deploy-shape-benchmark/REQ-17)" do
    held_to("medium") do |driver|
      added = driver.environment.fetch("Database round trip")[/([\d.]+) ms of it added \(1 ms set\)/, 1]
      expect(added.to_f).to be_between(0.8, 2.0)
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
