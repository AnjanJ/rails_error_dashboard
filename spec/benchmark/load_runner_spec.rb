# frozen_string_literal: true

require "rails_helper"
require "json"
require "open3"
require "stringio"
require "tmpdir"
require_relative "../../benchmark/load/runner"
require_relative "../../benchmark/load/compose_driver"

# The load test's procedure, benchmark/load/runner.rb. A fake stands in for
# compose's app and k6 here, so none of it needs Docker.
RSpec.describe RedBenchmark::Load::Runner do
  # The app holds any rate up to its capacity. Past it the app falls behind,
  # and a run shows that the way k6 does: requests dropped, requests answered
  # with an error, or requests k6 gave up on before they finished. A run that
  # keeps up at R a second for D seconds has R × D + 1 requests, as k6 sends.
  # A cold app falls behind on its first run after each start, at any rate.
  # Its machine counts 1,000 CPU ticks in each run, and has one stolen for
  # every 10 s the run lasts. Its app's quota holds it back twice a second, for
  # 1 ms each time, or it has no cgroup to say.
  fake_driver = Class.new do
    attr_reader :calls, :cpu_ticks, :throttling

    def initialize(capacity:, overload: :drops, cold: false, cgroup: true)
      @capacity = capacity
      @overload = overload
      @cold = cold
      @calls = []
      @runs_since_start = 0
      @cpu_ticks = { steal: 0, total: 0 }
      @throttling = { times: 0, usec: 0 } if cgroup
    end

    def environment
      { "Ruby" => "3.4.7", "CPU" => "AMD EPYC 9V74 80-Core Processor", "RED commit" => "abc1234" }
    end

    def up
      @calls << [ :up ]
    end

    def down
      @calls << [ :down ]
    end

    def start(red:)
      @calls << [ :start, red ]
      @runs_since_start = 0
    end

    def run(rate:, mix:, seconds:)
      @calls << [ :run, rate, mix, seconds ]
      @runs_since_start += 1
      @cpu_ticks = { steal: @cpu_ticks[:steal] + seconds / 10, total: @cpu_ticks[:total] + 1000 }
      @throttling &&= { times: @throttling[:times] + seconds * 2, usec: @throttling[:usec] + seconds * 2000 }
      sent = rate * seconds + 1
      kept_up = rate <= @capacity && !(@cold && @runs_since_start == 1)
      summary(sent, kept_up ? 0 : [ sent - @capacity * seconds, 1 ].max)
    end

    private

    # The fields the runner reads, where k6 1.8.2's summary has them. k6 leaves
    # dropped_iterations out when it dropped none.
    def summary(sent, behind)
      dropped, failed, unfinished = { drops: [ behind, 0, 0 ], errors: [ 0, behind, 0 ], unfinished: [ 0, 0, behind ] }.fetch(@overload)
      finished = sent - dropped - unfinished
      metrics = {
        "iterations" => { "values" => { "count" => finished } },
        "http_req_failed" => { "values" => { "passes" => failed, "fails" => finished - failed } }
      }
      metrics["dropped_iterations"] = { "values" => { "count" => dropped } } if dropped.positive?
      { "metrics" => metrics }
    end
  end

  let(:log) { StringIO.new }

  def runner_for(driver, rate: nil)
    described_class.new(driver, rate: rate, log: log)
  end

  # The driver's calls, split at each start: a probe or a window is a start,
  # then its runs.
  def restarts_in(calls)
    calls.slice_before { |call| call.first == :start }.select { |probe| probe.first.first == :start }
  end

  describe "with no rate given" do
    it "measures the app's capacity with RED off and uses half of it (deploy-shape-benchmark/REQ-10)" do
      driver = fake_driver.new(capacity: 333)
      runner = runner_for(driver)

      # Never more than the app held, and within the search's 10% of it
      expect(runner.capacity).to be_between(300, 333)
      expect(runner.rate).to eq(runner.capacity / 2)
      expect(restarts_in(driver.calls)).not_to be_empty
      expect(restarts_in(driver.calls).map(&:first)).to all(eq([ :start, false ]))
    end

    it "restarts the app before each probe, and judges only what follows its warm-up (deploy-shape-benchmark/REQ-10)" do
      driver = fake_driver.new(capacity: 333, cold: true)
      warmup, seconds = described_class::PROBE.values_at(:warmup, :seconds)

      expect(runner_for(driver).capacity).to be_between(300, 333)
      probes = restarts_in(driver.calls)
      # No run comes before a restart, and each probe is a restart, its
      # warm-up and its measured run, both at the probe's rate.
      expect(probes.flatten(1)).to eq(driver.calls)
      expect(probes).to all(
        match([ [ :start, false ], [ :run, Integer, "healthy", warmup ], [ :run, Integer, "healthy", seconds ] ])
      )
      expect(probes.map { |probe| probe.drop(1).map { |run| run[1] }.uniq.size }).to all(eq(1))
    end

    it "finds a capacity below the first rate it tries (deploy-shape-benchmark/REQ-10)" do
      runner = runner_for(fake_driver.new(capacity: 6))

      expect([ runner.capacity, runner.rate ]).to eq([ 6, 3 ])
    end

    it "counts a request answered with a status its kind doesn't expect as not holding the rate (deploy-shape-benchmark/REQ-10)" do
      runner = runner_for(fake_driver.new(capacity: 333, overload: :errors))

      expect(runner.capacity).to be_between(300, 333)
      expect(log.string).to match(/640 a second: didn't hold \(\d+ with an unexpected status\)/)
    end

    it "counts requests that didn't finish as not holding the rate (deploy-shape-benchmark/REQ-10)" do
      runner = runner_for(fake_driver.new(capacity: 333, overload: :unfinished))

      expect(runner.capacity).to be_between(300, 333)
      expect(log.string).to match(/640 a second: didn't hold \(\d+ of #{640 * described_class::PROBE[:seconds]} finished\)/)
    end

    it "stops when the app holds no rate at all (deploy-shape-benchmark/REQ-10)" do
      expect { runner_for(fake_driver.new(capacity: 0)).rate }
        .to raise_error(RedBenchmark::Load::Error, /held no rate/)
    end

    it "stops at the most it tries, rather than search for ever (deploy-shape-benchmark/REQ-10)" do
      expect { runner_for(fake_driver.new(capacity: 1_000_000)).rate }
        .to raise_error(RedBenchmark::Load::Error, /held #{described_class::MOST} requests a second/)
    end
  end

  it "uses a rate it's given, and skips the search (deploy-shape-benchmark/REQ-10)" do
    driver = fake_driver.new(capacity: 333)
    runner = runner_for(driver, rate: 40)

    expect([ runner.rate, runner.capacity ]).to eq([ 40, nil ])
    expect(driver.calls).to be_empty
  end

  describe "the windows" do
    it "alternate RED off and on in ABBA order, five pairs for each mix (deploy-shape-benchmark/REQ-11)" do
      windows = runner_for(fake_driver.new(capacity: 333), rate: 40).windows

      expect(windows.map(&:mix).uniq).to eq(%w[healthy failing storm])
      windows.group_by(&:mix).each_value do |mix|
        expect(mix.map(&:red)).to eq([ false, true, true, false, false, true, true, false, false, true ])
        expect(mix.map(&:pair)).to eq([ 1, 1, 2, 2, 3, 3, 4, 4, 5, 5 ])
      end
    end

    it "all run at the same rate, half the capacity when none was given (deploy-shape-benchmark/REQ-11)" do
      driver = fake_driver.new(capacity: 333)
      runner = runner_for(driver)
      runner.rate
      driver.calls.clear

      runner.windows
      expect(driver.calls.select { |call| call.first == :run }.map { |run| run[1] }.uniq).to eq([ 160 ])
    end

    it "each restart the app with RED as the window has it, and keep what follows the warm-up (deploy-shape-benchmark/REQ-11)" do
      driver = fake_driver.new(capacity: 333, cold: true)
      windows = runner_for(driver, rate: 40).windows
      warmup, seconds = described_class::WINDOW.values_at(:warmup, :seconds)

      expect(restarts_in(driver.calls)).to eq(windows.map { |window|
        [ [ :start, window.red ], [ :run, 40, window.mix, warmup ], [ :run, 40, window.mix, seconds ] ]
      })
      # The cold app fell behind in every warm-up, and no window kept that run
      expect(windows.map { |window| described_class.shortfall(window.summary, 40, seconds) }).to all(be_nil)
    end

    it "each say why they didn't hold their rate, as a probe would (deploy-shape-benchmark/REQ-15)" do
      expect(runner_for(fake_driver.new(capacity: 333), rate: 40).windows.map(&:shortfall)).to all(be_nil)
      expect(runner_for(fake_driver.new(capacity: 30), rate: 40).windows.map(&:shortfall)).to all(match(/\A\d+ dropped\z/))
    end

    # 12 ticks of 1,000 in a measured run's 120 s, against 6 in a warm-up's
    # 60 s: both runs together would read 0.90%.
    it "each give the share of CPU time stolen during their measured run (deploy-shape-benchmark/REQ-14)" do
      windows = runner_for(fake_driver.new(capacity: 333), rate: 40).windows

      expect(windows.map(&:steal).uniq).to eq([ "1.20%" ])
    end

    # Twice a second for 1 ms in a measured run's 120 s, and none of the
    # warm-up's.
    it "each say how often the app's CPU quota held it back during their measured run (deploy-shape-benchmark/REQ-16)" do
      expect(runner_for(fake_driver.new(capacity: 333), rate: 40).windows.map(&:throttled).uniq)
        .to eq([ "240 times, 0.24 s" ])
      expect(runner_for(fake_driver.new(capacity: 333, cgroup: false), rate: 40).windows.map(&:throttled).uniq)
        .to eq([ "not available" ])
      expect(described_class.throttled({ times: 4, usec: 0 }, { times: 5, usec: 61_000 })).to eq("1 time, 0.06 s")
    end
  end

  describe "RedBenchmark::Load.main, which bin/benchmark-load runs" do
    let(:out) { StringIO.new }

    # bin/benchmark-load makes its driver once it knows the shape, if any.
    def main(*arguments, driver:)
      RedBenchmark::Load.main(arguments, driver: ->(shape) { @shape = shape; driver }, out: out, log: log)
    end

    it "holds the stack to the shape it's given, and to none without one (deploy-shape-benchmark/REQ-16)" do
      expect(main("--rate", "40", "--shape", "small", driver: fake_driver.new(capacity: 333))).to eq(0)
      expect(@shape).to eq(RedBenchmark::Load::Shapes.fetch("small"))

      expect(main("--rate", "40", driver: fake_driver.new(capacity: 333))).to eq(0)
      expect(@shape).to be_nil
    end

    it "refuses a shape it doesn't have, before it starts anything (deploy-shape-benchmark/REQ-16)" do
      driver = fake_driver.new(capacity: 333)

      expect(main("--shape", "large", driver: driver)).to eq(1)
      expect(driver.calls).to be_empty
      expect(log.string).to include("--shape large", "Usage: bin/benchmark-load [--rate N] [--shape NAME]")
    end

    it "starts the stack, measures the rate with RED off, says what it is, and removes the stack (deploy-shape-benchmark/REQ-10)" do
      driver = fake_driver.new(capacity: 333)

      expect(main(driver: driver)).to eq(0)
      expect([ driver.calls.first, driver.calls.last ]).to eq([ [ :up ], [ :down ] ])
      expect(out.string).to include("Rate: 160 requests a second, half the 320 the app held with RED off.")
    end

    it "skips the search when given --rate (deploy-shape-benchmark/REQ-10)" do
      driver = fake_driver.new(capacity: 333)

      expect(main("--rate", "40", driver: driver)).to eq(0)
      expect(driver.calls.select { |call| call.first == :run }.map { |run| run[1] }).to all(eq(40))
      expect(out.string).to include("Rate: 40 requests a second, as given.")
    end

    it "prints the report, writes its figures as JSON, and adds it to a summary file (deploy-shape-benchmark/REQ-13)" do
      Dir.mktmpdir("red_load_report") do |dir|
        json = File.join(dir, "reports", "load.json")
        summary = File.join(dir, "summary.md")
        File.write(summary, "before\n")

        expect(main("--rate", "40", "--json", json, "--summary", summary, driver: fake_driver.new(capacity: 333))).to eq(0)
        expect(out.string).to start_with("## What RED adds under load\n")
        figures = JSON.parse(File.read(json))
        expect(figures["windows"].size).to eq(30)
        expect(figures["environment"]).to include("Ruby" => "3.4.7")
        expect(RedBenchmark::Load::LoadReport.markdown(figures)).to eq(out.string)
        expect(File.read(summary)).to eq("before\n#{out.string}")
      end
    end

    it "runs every window, at the rate it says, before it removes the stack (deploy-shape-benchmark/REQ-11)" do
      driver = fake_driver.new(capacity: 333)

      expect(main("--rate", "40", driver: driver)).to eq(0)
      windows = restarts_in(driver.calls)
      expect(windows.size).to eq(described_class::MIXES.size * described_class::PAIRS * 2)
      expect(windows.flatten(1).select { |call| call.first == :run }.map { |run| run[1] }.uniq).to eq([ 40 ])
      expect(driver.calls.last).to eq([ :down ])
    end

    it "refuses a rate that isn't a whole number above 0, before it starts anything (deploy-shape-benchmark/REQ-10)" do
      [ [ "--rate", "fast" ], [ "--rate", "0" ], [ "--rate", "2.5" ], [ "--rate" ], [ "40" ] ].each do |arguments|
        driver = fake_driver.new(capacity: 333)

        expect(main(*arguments, driver: driver)).to eq(1), arguments.inspect
        expect(driver.calls).to be_empty, arguments.inspect
      end
      expect(out.string).to be_empty
      expect(log.string).to include("Usage: bin/benchmark-load [--rate N]")
    end

    it "removes the stack and fails when the search finds nothing (deploy-shape-benchmark/REQ-10)" do
      driver = fake_driver.new(capacity: 0)

      expect(main(driver: driver)).to eq(1)
      expect(driver.calls.last).to eq([ :down ])
      expect(log.string).to include("held no rate")
    end
  end
end

# The driver the runner uses in Docker, against the real stack. It needs Docker
# and a couple of minutes, so it runs only when asked:
#
#   LOAD_APP_BOOT=1 bundle exec rspec spec/benchmark/load_runner_spec.rb
RSpec.describe RedBenchmark::Load::ComposeDriver, if: ENV["LOAD_APP_BOOT"] == "1" do
  before(:all) do
    @driver = described_class.new
    @driver.up
  end

  after(:all) { @driver.down }

  it "restarts the app with RED off or on, as asked (deploy-shape-benchmark/REQ-10)" do
    @driver.start(red: false)
    expect(status_of("/red")).to eq("404")

    # RED's dashboard is mounted, and asks for its login
    @driver.start(red: true)
    expect(status_of("/red")).to eq("401")
  end

  # Three Puma threads each waiting 100 ms on the database answer about 30 a
  # second, so 80 a second leaves k6 with no VU free to start a request.
  it "returns k6's summary, in which an easy rate holds and an overload doesn't (deploy-shape-benchmark/REQ-10)" do
    @driver.start(red: false)
    @driver.run(rate: 10, mix: "healthy", seconds: 5)
    easy = @driver.run(rate: 10, mix: "healthy", seconds: 10)
    expect(RedBenchmark::Load::Runner.shortfall(easy, 10, 10)).to be_nil

    delay_database(100)
    overload = @driver.run(rate: 80, mix: "healthy", seconds: 15)
    expect(RedBenchmark::Load::Runner.shortfall(overload, 80, 15)).to match(/\A\d+ dropped/)
  ensure
    remove_delay
  end

  it "reads bin/benchmark's environment block inside the app's container, with this checkout's commit (deploy-shape-benchmark/REQ-13)" do
    environment = @driver.environment

    expect(environment.keys).to eq(RedBenchmark::Harness.environment.keys + [ "Database round trip" ])
    expect(environment).to include("Rails" => start_with("8.1."), "Database" => "postgresql",
      "RED commit" => RedBenchmark::Harness.commit)
  end

  def compose
    [ "docker", "compose", "--file", described_class::FILE ]
  end

  def run!(*command)
    output, status = Open3.capture2e(*command)
    raise "#{command.join(" ")} failed:\n#{output}" unless status.success?

    output
  end

  def status_of(path)
    run!(*compose, "exec", "-T", "app", "curl", "--silent", "--output", "/dev/null", "--write-out", "%{http_code}",
      "http://localhost#{path}")
  end

  # Delays everything the database sends, with tc netem in a container sharing
  # its network. The app restarts; the database doesn't, so the delay stays.
  def delay_database(milliseconds)
    run!(*netem("add dev eth0 root netem delay #{milliseconds}ms"))
  end

  # Quietly, so a failure here can't hide the example's own.
  def remove_delay
    system(*netem("del dev eth0 root"), out: File::NULL, err: File::NULL)
  end

  def netem(change)
    database = run!(*compose, "ps", "--quiet", "db").strip
    [ "docker", "run", "--rm", "--network", "container:#{database}", "--cap-add", "NET_ADMIN", "alpine:3.20",
      "sh", "-c", "apk add --no-cache --quiet iproute2 && tc qdisc #{change}" ]
  end
end
