# frozen_string_literal: true

module RedBenchmark
  # Times one operation the way RED's budgets are stated: per call, on the
  # monotonic clock, after a warm-up.
  #
  # Each measurement runs `rounds` rounds of `iterations` timed calls. The
  # number that is gated is the median of the round medians: it shrugs off a
  # noisy round or two (a GC pause, a busy CI neighbour) without hiding a real
  # regression. The p95 of every sample is reported too, but never gated, since
  # it moves with GC on any shared machine. (.shipkit/specs/_shipped/overhead-benchmark/
  # design.md records why this is not benchmark-ips.)
  class Timer
    MONOTONIC = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

    # median, p95 and budget are in seconds; budget is nil for a row that is
    # reported but not gated.
    Result = Struct.new(:name, :median, :p95, :round_medians, :budget, keyword_init: true) do
      def gated?
        !budget.nil?
      end

      def pass?
        !gated? || median <= budget
      end

      def skipped?
        false
      end
    end

    # A row the database can't run: no figures, and it can't fail a run.
    Skipped = Struct.new(:name, :reason, keyword_init: true) do
      def gated?
        false
      end

      def pass?
        true
      end

      def skipped?
        true
      end
    end

    # 1 when any gated row is over its budget, else 0. Reported-only rows never
    # fail a run.
    def self.exit_status(results)
      results.any? { |result| result.gated? && !result.pass? } ? 1 : 0
    end

    def initialize(rounds: 5, iterations: 1_000, warmup: 200, clock: MONOTONIC)
      @rounds = rounds
      @iterations = iterations
      @warmup = warmup
      @clock = clock
    end

    # Times the block itself. With batch > 1 each sample is that many calls
    # in a row, divided by the count: for operations of a few microseconds,
    # where one call is close to the clock's resolution (whole microseconds on
    # macOS) and its own cost.
    def measure(name, budget: nil, batch: 1, &block)
      @warmup.times(&block)
      collect(name, budget) { time { batch.times(&block) } / batch }
    end

    # What `with` adds over `without`: each sample times the two back to back
    # and keeps the difference, so slow drift on the machine cancels out.
    def measure_difference(name, with:, without:, budget: nil)
      @warmup.times do
        without.call
        with.call
      end
      collect(name, budget) do
        baseline = time(&without)
        time(&with) - baseline
      end
    end

    private

    def collect(name, budget)
      rounds = Array.new(@rounds) { Array.new(@iterations) { yield } }
      round_medians = rounds.map { |samples| Stats.median(samples) }

      Result.new(
        name: name,
        median: Stats.median(round_medians),
        p95: Stats.percentile(rounds.flatten, 95),
        round_medians: round_medians,
        budget: budget
      )
    end

    def time
      started = @clock.call
      yield
      @clock.call - started
    end
  end

  module Stats
    module_function

    def median(values)
      sorted = values.sort
      mid = sorted.size / 2
      sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
    end

    # Nearest-rank percentile: the smallest sample with at least pct% of the
    # samples at or below it.
    def percentile(values, pct)
      sorted = values.sort
      sorted[[ (pct / 100.0 * sorted.size).ceil - 1, 0 ].max]
    end
  end
end
