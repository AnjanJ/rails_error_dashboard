# frozen_string_literal: true

require "rails_helper"
require "json"
require "stringio"
require "tmpdir"
require_relative "../../benchmark/load/runner"

# The compare tool, benchmark/load/compare.rb: two load test reports, as
# bin/benchmark-load --json writes them, side by side.
RSpec.describe RedBenchmark::Load::Compare do
  # A mix's figures as LoadReport.build gives them, with what RED added at
  # p50, p95 and p99. nil is a latency whose pairs were all invalid.
  def mix(p50, p95, p99)
    { "errors_a_second" => 0.0,
      **{ "p50" => p50, "p95" => p95, "p99" => p99 }.transform_values do |added|
        { "off" => 3.0, "on" => added && 3.0 + added, "added" => added, "pairs" => added ? [ added ] : [] }
      end }
  end

  def report(shape:, cpu:, commit:, rate:, mixes:)
    { "shape" => shape && { "name" => shape, "size_of" => "a #{shape} plan" },
      "environment" => { "Ruby" => "3.4.12", "CPU" => cpu, "CPU topology" => "2 CPUs on 1 core",
                         "RED commit" => commit, "Database round trip" => "1.10 ms, 1.03 ms of it added (1 ms set)" },
      "rate" => rate, "capacity" => rate * 2, "warmup" => 60, "seconds" => 120,
      "mixes" => mixes, "windows" => [] }
  end

  let(:first) do
    report(shape: "medium", cpu: "AMD EPYC 7763 64-Core Processor", commit: "1c6efc4", rate: 220,
      mixes: { "healthy" => mix(0.02, -0.26, 0.40), "failing" => mix(0.0, 0.10, 0.40), "storm" => mix(0.12, nil, 0.50) })
  end
  let(:second) do
    report(shape: "medium-throttled", cpu: "AMD EPYC 7763 64-Core Processor", commit: "dbe513a", rate: 55,
      mixes: { "healthy" => mix(0.11, 0.30, 0.80), "failing" => mix(0.05, 0.25, 5.84), "slow" => mix(1.0, 2.0, 3.0) })
  end

  let(:markdown) { described_class.markdown(first, second, names: [ "medium.json", "throttled.json" ]) }

  it "prints what RED added in each report, per mix and latency, and the ratio between them (deploy-shape-benchmark/REQ-20)" do
    expect(markdown).to start_with("## What RED added in two load tests\n")
    expect(markdown).to include(
      "| Mix | Latency | RED added, first | RED added, second | Second over first |",
      "| healthy | p50 | +0.02 ms | +0.11 ms | 5.50x |",
      "| healthy | p99 | +0.40 ms | +0.80 ms | 2.00x |",
      "| failing | p99 | +0.40 ms | +5.84 ms | 14.60x |"
    )
  end

  it "says which shape, CPU, commit and rate each report measured (deploy-shape-benchmark/REQ-20)" do
    expect(markdown).to include(
      "| | First | Second |",
      "| Report | medium.json | throttled.json |",
      "| Shape | medium, the size of a medium plan | medium-throttled, the size of a medium-throttled plan |",
      "| CPU | AMD EPYC 7763 64-Core Processor | AMD EPYC 7763 64-Core Processor |",
      "| RED commit | 1c6efc4 | dbe513a |",
      "| Rate | 220 requests a second | 55 requests a second |"
    )
  end

  it "lists a mix only one report ran, with the other side not run and no ratio (deploy-shape-benchmark/REQ-20)" do
    expect(markdown).to include(
      "| storm | p50 | +0.12 ms | not run | n/a |",
      "| slow | p99 | not run | +3.00 ms | n/a |"
    )
    expect(markdown.lines.grep(/\A\| (healthy|failing|storm|slow) \|/).map { |line| line.split(" | ").first })
      .to eq([ "| healthy" ] * 3 + [ "| failing" ] * 3 + [ "| storm" ] * 3 + [ "| slow" ] * 3)
  end

  it "gives no ratio where either report has RED adding nothing, or no valid pair (deploy-shape-benchmark/REQ-20)" do
    expect(markdown).to include(
      "| healthy | p95 | -0.26 ms | +0.30 ms | n/a |",
      "| failing | p50 | +0.00 ms | +0.05 ms | n/a |"
    )
    expect(described_class.ratio(0.4, 5.84)).to be_within(1e-9).of(14.6)
    expect([ [ -0.26, 0.3 ], [ 0.0, 0.05 ], [ 0.3, -0.1 ], [ nil, 0.2 ], [ 0.2, nil ] ].map { |a, b| described_class.ratio(a, b) })
      .to all(be_nil)
  end

  it "reads a missing latency as n/a, and names a report with no shape (deploy-shape-benchmark/REQ-20)" do
    unshaped = described_class.markdown(first.merge("shape" => nil), second, names: [ "a.json", "b.json" ])

    expect(unshaped).to include("| storm | p95 | n/a | not run | n/a |", "| Shape | none |")
  end

  it "says a report from before reports named their shape didn't record one (deploy-shape-benchmark/REQ-20)" do
    older = described_class.markdown(first, second.except("shape"), names: [ "a.json", "b.json" ])

    expect(older).to include("| Shape | medium, the size of a medium plan | not recorded |")
  end

  describe "bin/benchmark-load --compare" do
    let(:out) { StringIO.new }
    let(:log) { StringIO.new }

    def main(*arguments)
      RedBenchmark::Load.main(arguments, driver: ->(**) { raise "compare must not start the stack" }, out: out, log: log)
    end

    def with_reports
      Dir.mktmpdir("red_load_compare") do |dir|
        paths = { first: first, second: second }.to_h do |name, figures|
          path = File.join(dir, "#{name}.json")
          File.write(path, JSON.pretty_generate(figures))
          [ name, path ]
        end
        yield paths[:first], paths[:second], dir
      end
    end

    it "prints the comparison of two reports without starting the stack, and adds it to a summary file (deploy-shape-benchmark/REQ-20)" do
      with_reports do |first_path, second_path, dir|
        summary = File.join(dir, "summary.md")
        File.write(summary, "before\n")

        expect(main("--compare", first_path, second_path, "--summary", summary)).to eq(0)
        expect(out.string).to eq(described_class.markdown(first, second, names: [ first_path, second_path ]))
        expect(File.read(summary)).to eq("before\n#{out.string}")
      end
    end

    it "refuses anything but two reports, or a measuring option beside them (deploy-shape-benchmark/REQ-20)" do
      with_reports do |first_path, second_path|
        [ [ "--compare", first_path ], [ "--compare", first_path, second_path, first_path ],
          [ "--compare", first_path, second_path, "--rate", "40" ], [ "--compare", first_path, second_path, "--json", "x.json" ],
          [ "--compare", first_path, second_path, "--shape", "small" ],
          [ "--compare", first_path, second_path, "--stack", "postgres-sidekiq" ],
          [ "--compare", first_path, second_path, "--ruby", "4.0" ] ].each do |arguments|
          expect(main(*arguments)).to eq(1), arguments.inspect
        end
      end
      expect(out.string).to be_empty
      expect(log.string).to include("bin/benchmark-load --compare FIRST.json SECOND.json")
    end

    it "fails with the file's name when one isn't a load test report (deploy-shape-benchmark/REQ-20)" do
      with_reports do |first_path, _second_path, dir|
        not_json = File.join(dir, "rows.md")
        File.write(not_json, "## RED overhead benchmark\n")
        no_mixes = File.join(dir, "other.json")
        File.write(no_mixes, JSON.generate("rows" => []))
        missing = File.join(dir, "missing.json")

        [ not_json, no_mixes, missing ].each do |path|
          expect(main("--compare", first_path, path)).to eq(1), path
          expect(log.string).to include("#{path} isn't a load test report"), path
        end
      end
      expect(out.string).to be_empty
    end
  end
end
