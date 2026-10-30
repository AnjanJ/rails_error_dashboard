# frozen_string_literal: true

require "rails_helper"
require_relative "../../benchmark/timer"
require_relative "../../benchmark/report"

RSpec.describe RedBenchmark::Report do
  def result(name, median:, p95:, budget:)
    RedBenchmark::Timer::Result.new(name: name, median: median, p95: p95, round_medians: [ median ], budget: budget)
  end

  let(:environment) { { "Ruby" => "3.4.5", "CPU" => "AMD EPYC 7763", "RED commit" => "abc1234" } }
  let(:results) do
    [
      result("Storm check, calm", median: 2.4e-6, p95: 3.1e-6, budget: 5e-6),
      result("Capture, async (installer default)", median: 6.2e-3, p95: 8e-3, budget: 5e-3),
      result("Capture, sync", median: 1.25e-3, p95: 2e-3, budget: nil)
    ]
  end

  subject(:markdown) { described_class.markdown(environment, results) }

  it "puts the environment above the table (overhead-benchmark/REQ-6)" do
    expect(markdown).to include("| Ruby | 3.4.5 |", "| CPU | AMD EPYC 7763 |", "| RED commit | abc1234 |")
    expect(markdown.index("| CPU |")).to be < markdown.index("| Measurement |")
  end

  it "shows each row's median, p95, budget and verdict, in readable units (overhead-benchmark/REQ-4)" do
    expect(markdown).to include("| Measurement | Median | p95 | Budget | Result |")
    expect(markdown).to include("| Storm check, calm | 2.40 µs | 3.10 µs | < 5.00 µs | PASS |")
    expect(markdown).to include("| Capture, async (installer default) | 6.20 ms | 8.00 ms | < 5.00 ms | FAIL |")
    expect(markdown).to include("| Capture, sync | 1.25 ms | 2.00 ms | none | reported |")
  end
end
