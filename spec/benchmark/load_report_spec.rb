# frozen_string_literal: true

require "rails_helper"
require "json"
require_relative "../../benchmark/load/runner"
require_relative "../../benchmark/load/load_report"

# The load test's report, benchmark/load/load_report.rb, built from known
# windows.
RSpec.describe RedBenchmark::Load::LoadReport do
  # A window's k6 summary: its percentiles in ms, and its counts. A window at
  # 20 a second for 120 s that keeps up has 2,401 requests.
  def summary(p50:, p95:, p99:, requests: 2401, errors: 0, dropped: 0, unexpected: 0)
    metrics = {
      "http_req_duration" => { "values" => { "med" => p50, "p(95)" => p95, "p(99)" => p99, "max" => p99 + 5 } },
      "iterations" => { "values" => { "count" => requests } },
      "http_req_failed" => { "values" => { "passes" => unexpected, "fails" => requests - unexpected } },
      "http_reqs{kind:failing}" => { "values" => { "count" => errors } }
    }
    metrics["dropped_iterations"] = { "values" => { "count" => dropped } } if dropped.positive?
    { "metrics" => metrics }
  end

  # The runner judges each window as it does a probe, at the report's 20 a
  # second for 120 s.
  def window(mix, pair, red, steal: "0.00%", **counts)
    summary = summary(**counts)
    RedBenchmark::Load::Runner::Window.new(mix: mix, pair: pair, red: red, summary: summary, steal: steal,
      shortfall: RedBenchmark::Load::Runner.shortfall(summary, 20, 120))
  end

  # Five healthy pairs in the order they ran, ABBA. RED's side was faster in
  # pair 3. RED added at p50, pair by pair: +1.00, +2.00, -0.50, +1.50, +0.75.
  let(:healthy) do
    [
      window("healthy", 1, false, p50: 7.0, p95: 18.0, p99: 30.0, steal: "0.00%"),
      window("healthy", 1, true, p50: 8.0, p95: 19.0, p99: 33.0, steal: "0.25%"),
      window("healthy", 2, true, p50: 9.5, p95: 21.0, p99: 35.0),
      window("healthy", 2, false, p50: 7.5, p95: 19.0, p99: 31.0),
      window("healthy", 3, false, p50: 8.0, p95: 20.0, p99: 34.0),
      window("healthy", 3, true, p50: 7.5, p95: 19.5, p99: 33.0),
      window("healthy", 4, true, p50: 8.5, p95: 20.5, p99: 36.0),
      window("healthy", 4, false, p50: 7.0, p95: 18.5, p99: 30.5),
      window("healthy", 5, false, p50: 7.25, p95: 18.25, p99: 30.25),
      window("healthy", 5, true, p50: 8.0, p95: 19.75, p99: 33.25, steal: "not available")
    ]
  end

  # One pair of the 1% mix: 25 failing requests in each window.
  let(:failing) do
    [
      window("failing", 1, false, p50: 9.0, p95: 22.0, p99: 40.0, errors: 25),
      window("failing", 1, true, p50: 12.0, p95: 26.0, p99: 47.0, errors: 25)
    ]
  end

  let(:environment) { { "Ruby" => "3.4.7", "CPU" => "AMD EPYC 9V74 80-Core Processor", "RED commit" => "abc1234" } }

  def build(windows, rate: 20, capacity: 40)
    described_class.build(environment: environment, rate: rate, capacity: capacity,
      window: { warmup: 60, seconds: 120 }, windows: windows)
  end

  subject(:report) { build(healthy + failing) }

  let(:markdown) { described_class.markdown(report) }

  it "gives p50, p95 and p99 for each mix with RED off and on, the median of each side's windows (deploy-shape-benchmark/REQ-13)" do
    expect(report.dig("mixes", "healthy", "p50").slice("off", "on")).to eq("off" => 7.25, "on" => 8.0)
    expect(report.dig("mixes", "healthy", "p99").slice("off", "on")).to eq("off" => 30.5, "on" => 33.25)
    expect(report.dig("mixes", "failing", "p95").slice("off", "on")).to eq("off" => 22.0, "on" => 26.0)
    expect(markdown).to include("| healthy | 0.0 | p50 | 7.25 ms | 8.00 ms |", "| failing | 0.2 | p95 | 22.00 ms | 26.00 ms |")
  end

  it "gives what RED added in each pair, and their median (deploy-shape-benchmark/REQ-13)" do
    expect(report.dig("mixes", "healthy", "p50").slice("added", "pairs"))
      .to eq("added" => 1.0, "pairs" => [ 1.0, 2.0, -0.5, 1.5, 0.75 ])
    expect(report.dig("mixes", "healthy", "p99", "added")).to eq(3.0)
    expect(report.dig("mixes", "failing", "p50").slice("added", "pairs")).to eq("added" => 3.0, "pairs" => [ 3.0 ])
  end

  it "shows a negative difference as it is (deploy-shape-benchmark/REQ-13)" do
    expect(markdown).to include("| +1.00 ms | +1.00, +2.00, -0.50, +1.50, +0.75 |")
  end

  it "gives the share of CPU time stolen in each window (deploy-shape-benchmark/REQ-14)" do
    expect(report["windows"].map { |row| row["cpu_stolen"] })
      .to eq([ "0.00%", "0.25%", *[ "0.00%" ] * 7, "not available", "0.00%", "0.00%" ])
    expect(markdown).to include("| healthy | 1 | on | 8.00 ms | 19.00 ms | 33.00 ms | 2401 | 0 | 0 | 0 | 0.25% |")
  end

  it "puts the environment and the rate above the figures (deploy-shape-benchmark/REQ-13)" do
    expect(markdown).to include("\n| | |\n|---|---|\n| Ruby | 3.4.7 |\n", "| RED commit | abc1234 |",
      "Rate: 20 requests a second, half the 40 the app held with RED off.")
    expect(markdown.index("| RED commit |")).to be < markdown.index("| Mix |")
    expect(described_class.markdown(build(healthy, capacity: nil))).to include("Rate: 20 requests a second, as given.")
  end

  it "renders the Markdown from the figures the JSON keeps (deploy-shape-benchmark/REQ-13)" do
    expect(described_class.markdown(JSON.parse(JSON.generate(report)))).to eq(markdown)
  end

  describe "a window that didn't hold its rate" do
    # Pair 2's RED-on window dropped 40 requests and, behind, answered slowly.
    # The 1% mix's RED-off window got three statuses it didn't expect.
    let(:healthy_with_drops) do
      healthy.map do |each|
        next each unless each.pair == 2 && each.red

        window("healthy", 2, true, p50: 500.0, p95: 900.0, p99: 990.0, requests: 2361, dropped: 40)
      end
    end
    let(:failing_with_errors) do
      [ window("failing", 1, false, p50: 9.0, p95: 22.0, p99: 40.0, errors: 25, unexpected: 3), failing.last ]
    end

    subject(:report) { build(healthy_with_drops + failing_with_errors) }

    it "is invalid when it dropped requests, and left out of every figure (deploy-shape-benchmark/REQ-15)" do
      # The RED-on median is of the other four, and RED added is of the other four pairs.
      expect(report.dig("mixes", "healthy", "p50"))
        .to eq("off" => 7.25, "on" => 8.0, "added" => 0.875, "pairs" => [ 1.0, -0.5, 1.5, 0.75 ])
      expect(report["windows"].find { |row| row["pair"] == 2 && row["red"] == "on" })
        .to include("invalid" => "40 dropped")
    end

    it "is invalid when a request got a status its kind doesn't expect, and left out of every figure (deploy-shape-benchmark/REQ-15)" do
      expect(report.dig("mixes", "failing", "p50")).to eq("off" => nil, "on" => 12.0, "added" => nil, "pairs" => [])
      expect(report["windows"].find { |row| row["mix"] == "failing" && row["red"] == "off" })
        .to include("invalid" => "3 with an unexpected status")
      expect(markdown).to include("| failing | 0.2 | p50 | n/a | 12.00 ms | n/a | none |")
    end

    it "is listed, with why (deploy-shape-benchmark/REQ-15)" do
      expect(markdown).to include(
        "Left out of every figure, for not holding the rate: healthy pair 2 RED on (40 dropped), " \
        "failing pair 1 RED off (3 with an unexpected status).",
        "| healthy | 2 | on | 500.00 ms | 900.00 ms | 990.00 ms | 2361 | 0 | 40 | 0 | 0.00% | no |"
      )
      expect(described_class.markdown(build(healthy))).to include("Every window held its rate.")
    end
  end
end
