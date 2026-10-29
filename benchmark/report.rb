# frozen_string_literal: true

module RedBenchmark
  # The benchmark's output: the environment the numbers came from, then one
  # row per measurement. Markdown, so the same text reads in a terminal and in
  # a GitHub Actions job summary.
  module Report
    module_function

    def markdown(environment, results)
      lines = [ "## RED overhead benchmark", "", "| | |", "|---|---|" ]
      environment.each { |name, value| lines << "| #{name} | #{value} |" }
      lines.push("", "| Measurement | Median | p95 | Budget | Result |", "|---|---|---|---|---|")
      results.each do |result|
        budget = result.gated? ? "< #{duration(result.budget)}" : "none"
        verdict = result.gated? ? (result.pass? ? "PASS" : "FAIL") : "reported"
        lines << "| #{result.name} | #{duration(result.median)} | #{duration(result.p95)} | #{budget} | #{verdict} |"
      end
      lines.push("", "Medians are the median of #{results.first&.round_medians&.size || 0} round medians. " \
        "Capture rows are what RED adds to a failing request (with RED minus without). " \
        "Rows marked \"reported\" have no budget and never fail the run.")
      lines.join("\n") + "\n"
    end

    def duration(seconds)
      if seconds < 1e-3
        format("%.2f µs", seconds * 1e6)
      elsif seconds < 1
        format("%.2f ms", seconds * 1e3)
      else
        format("%.2f s", seconds)
      end
    end
  end
end
