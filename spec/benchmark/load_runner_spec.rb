# frozen_string_literal: true

require "rails_helper"
require "stringio"
require_relative "../../benchmark/load/runner"

# The load test's procedure, benchmark/load/runner.rb. A fake stands in for
# compose's app and k6 here, so none of it needs Docker.
RSpec.describe RedBenchmark::Load::Runner do
  # The app holds any rate up to its capacity. Past it the app falls behind,
  # and a run shows that the way k6 does: requests dropped, requests answered
  # with an error, or requests k6 gave up on before they finished. A run that
  # keeps up at R a second for D seconds has R × D + 1 requests, as k6 sends.
  # A cold app falls behind on its first run after each start, at any rate.
  fake_driver = Class.new do
    attr_reader :calls

    def initialize(capacity:, overload: :drops, cold: false)
      @capacity = capacity
      @overload = overload
      @cold = cold
      @calls = []
      @runs_since_start = 0
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

  # Each probe, as the driver saw it: a start, then its runs.
  def probes_in(calls)
    calls.slice_before { |call| call.first == :start }.select { |probe| probe.first.first == :start }
  end

  describe "with no rate given" do
    it "measures the app's capacity with RED off and uses half of it (deploy-shape-benchmark/REQ-10)" do
      driver = fake_driver.new(capacity: 333)
      runner = runner_for(driver)

      # Never more than the app held, and within the search's 10% of it
      expect(runner.capacity).to be_between(300, 333)
      expect(runner.rate).to eq(runner.capacity / 2)
      expect(probes_in(driver.calls)).not_to be_empty
      expect(probes_in(driver.calls).map(&:first)).to all(eq([ :start, false ]))
    end

    it "restarts the app before each probe, and judges only what follows its warm-up (deploy-shape-benchmark/REQ-10)" do
      driver = fake_driver.new(capacity: 333, cold: true)
      warmup, seconds = described_class::PROBE.values_at(:warmup, :seconds)

      expect(runner_for(driver).capacity).to be_between(300, 333)
      probes = probes_in(driver.calls)
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
      expect(log.string).to match(/640 a second: didn't hold \(\d+ failed\)/)
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

  describe "RedBenchmark::Load.main, which bin/benchmark-load runs" do
    let(:out) { StringIO.new }

    def main(*arguments, driver:)
      RedBenchmark::Load.main(arguments, driver: driver, out: out, log: log)
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
