# frozen_string_literal: true

require_relative "load/shapes"

module RedBenchmark
  # The benchmark's output: the environment the numbers came from, then one
  # row per measurement. Markdown, so the same text reads in a terminal and in
  # a GitHub Actions job summary.
  module Report
    module_function

    # shape is the deploy shape the rows ran in, or nil (REQ-19)
    def markdown(environment, results, shape: nil)
      lines = [ "## RED overhead benchmark", "" ]
      lines.push(shape_line(shape.name, shape.size_of), "") if shape
      lines.push(*environment_table(environment))
      lines.push("", "| Measurement | Median | p95 | Budget | Result |", "|---|---|---|---|---|")
      results.each { |result| lines << row(result) }
      rounds = results.find { |result| !result.skipped? }&.round_medians&.size || 0
      lines.push("", "Medians are the median of #{rounds} round medians. " \
        "Capture rows are what RED adds to a failing request (with RED minus without). " \
        "Rows marked \"reported\" have no budget and never fail the run.")
      lines.join("\n") + "\n"
    end

    # What a report from a deploy shape measures (REQ-19): the shape's limits on
    # a runner, which no plan's own machine is. Both reports put it under their
    # heading.
    def shape_line(name, size_of)
      "Shape: #{name}, the size of #{size_of}, held to its limits on a GitHub runner. " \
        "These figures measure that shape, not any plan's machine."
    end

    # Where the numbers came from, as a table. bin/benchmark-load's report
    # puts the same one above its figures.
    def environment_table(environment)
      [ "| | |", "|---|---|", *environment.map { |name, value| "| #{name} | #{value} |" } ]
    end

    def row(result)
      return "| #{result.name} | n/a | n/a | none | not applicable: #{result.reason} |" if result.skipped?

      budget = result.gated? ? "< #{duration(result.budget)}" : "none"
      verdict = result.gated? ? (result.pass? ? "PASS" : "FAIL") : "reported"
      "| #{result.name} | #{duration(result.median)} | #{duration(result.p95)} | #{budget} | #{verdict} |"
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
