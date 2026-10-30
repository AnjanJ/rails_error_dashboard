# frozen_string_literal: true

require "rails_helper"
require_relative "../../benchmark/timer"

# overhead-benchmark/REQ-4, overhead-benchmark/REQ-7
RSpec.describe RedBenchmark::Timer do
  # A clock that returns the next value from a list, so every sample is known.
  def clock_from(ticks)
    queue = ticks.dup
    -> { queue.shift or raise "the clock ran out of ticks" }
  end

  # One sample per pair of ticks: start, then end.
  def ticks_for(durations)
    t = 0.0
    durations.flat_map { |d| [ t, (t += d) ].tap { t += 1.0 } }
  end

  describe "#measure" do
    it "reports the median of round medians and the p95 of every sample (overhead-benchmark/REQ-4)" do
      # 2 rounds of 5 samples, no warm-up. Round medians: 3 and 13.
      samples = [ 1, 2, 3, 4, 100, 11, 12, 13, 14, 15 ].map { |us| us / 1_000_000.0 }
      timer = described_class.new(rounds: 2, iterations: 5, warmup: 0, clock: clock_from(ticks_for(samples)))

      result = timer.measure("op", budget: 20e-6) { nil }

      expect(result.round_medians[0]).to be_within(1e-12).of(3e-6)
      expect(result.round_medians[1]).to be_within(1e-12).of(13e-6)
      expect(result.median).to be_within(1e-12).of(8e-6)
      expect(result.p95).to be_within(1e-12).of(100e-6)
    end

    it "times a batch of calls per sample and reports the cost of one (overhead-benchmark/REQ-4)" do
      # macOS's monotonic clock ticks in whole microseconds, so a 2 µs call
      # timed alone is mostly rounding. Each sample here is 4 calls in 8 µs.
      calls = 0
      timer = described_class.new(rounds: 1, iterations: 3, warmup: 0, clock: clock_from(ticks_for([ 8e-6 ] * 3)))

      result = timer.measure("op", batch: 4) { calls += 1 }

      expect(calls).to eq(12)
      expect(result.median).to be_within(1e-12).of(2e-6)
    end

    it "runs the warm-up iterations before it starts timing (overhead-benchmark/REQ-4)" do
      calls = 0
      timer = described_class.new(rounds: 1, iterations: 3, warmup: 4, clock: clock_from(ticks_for([ 1e-6 ] * 3)))

      timer.measure("op") { calls += 1 }

      expect(calls).to eq(7)
    end
  end

  describe "#measure_difference" do
    it "times each pair back to back and reports what the first block adds (overhead-benchmark/REQ-4)" do
      # Pairs alternate: without, then with. Differences: 2, 4, 6 µs.
      samples = [ 1, 3, 1, 5, 2, 8 ].map { |us| us / 1_000_000.0 }
      timer = described_class.new(rounds: 1, iterations: 3, warmup: 0, clock: clock_from(ticks_for(samples)))
      order = []

      result = timer.measure_difference("capture", budget: 5e-3,
        with: -> { order << :with }, without: -> { order << :without })

      expect(order).to eq(%i[without with] * 3)
      expect(result.median).to be_within(1e-12).of(4e-6)
    end
  end

  describe RedBenchmark::Timer::Result do
    def result(median:, budget:)
      described_class.new(name: "op", median: median, p95: median, round_medians: [ median ], budget: budget)
    end

    it "passes at the budget and fails above it (overhead-benchmark/REQ-7)" do
      expect(result(median: 5e-6, budget: 5e-6)).to be_pass
      expect(result(median: 5.01e-6, budget: 5e-6)).not_to be_pass
    end

    it "always passes when it has no budget (a reported-only row)" do
      expect(result(median: 1.0, budget: nil)).to be_pass
      expect(result(median: 1.0, budget: nil)).not_to be_gated
    end
  end

  describe ".exit_status" do
    def result(median:, budget:)
      RedBenchmark::Timer::Result.new(name: "op", median: median, p95: median, round_medians: [ median ], budget: budget)
    end

    it "is 1 when a gated row is over budget (overhead-benchmark/REQ-7)" do
      expect(RedBenchmark::Timer.exit_status([ result(median: 6e-6, budget: 5e-6) ])).to eq(1)
    end

    it "is 0 when only a reported row is slow (overhead-benchmark/REQ-7)" do
      results = [ result(median: 1e-6, budget: 5e-6), result(median: 9.0, budget: nil) ]

      expect(RedBenchmark::Timer.exit_status(results)).to eq(0)
    end
  end
end
