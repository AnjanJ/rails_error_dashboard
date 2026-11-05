# frozen_string_literal: true

require_relative "../report"

module RedBenchmark
  module Load
    # The load test's report (REQ-13, REQ-14). For each mix, p50, p95 and p99
    # with RED off and on, and what RED added in each pair. Then every window,
    # with the share of CPU time stolen while it ran. A window that didn't hold
    # its rate is invalid: it's listed, and left out of every figure (REQ-15).
    # build gives the figures as plain data, which bin/benchmark-load writes as
    # JSON for the compare tool, and markdown renders that same data.
    module LoadReport
      # Each latency, by the name k6's summary gives it in http_req_duration
      LATENCIES = { "p50" => "med", "p95" => "p(95)", "p99" => "p(99)" }.freeze

      module_function

      # The windows are the runner's: each has its mix, pair, whether RED was
      # on, k6's summary of its measured run, and the CPU time stolen.
      def build(environment:, rate:, capacity:, window:, windows:)
        rows = windows.map { |each| row(each) }
        {
          "environment" => environment,
          "rate" => rate,
          "capacity" => capacity,
          "warmup" => window[:warmup],
          "seconds" => window[:seconds],
          "mixes" => rows.group_by { |row| row["mix"] }.transform_values { |mix| figures(mix, window[:seconds]) },
          "windows" => rows
        }
      end

      def markdown(report)
        lines = [ "## What RED adds under load", "", *Report.environment_table(report["environment"]), "",
          "#{rate_line(report["rate"], report["capacity"])} Each window restarts the app, throws away " \
          "#{report["warmup"]} s of warm-up, then measures #{report["seconds"]} s.", "",
          "| Mix | Errors a second | Latency | RED off | RED on | RED added | In each pair (ms) |",
          "|---|---|---|---|---|---|---|" ]
        report["mixes"].each do |mix, figures|
          LATENCIES.each_key { |name| lines << figure_row(mix, figures, name) }
        end
        lines.push("", "RED off and RED on are the median of each side's valid windows. RED added is the median of " \
          "each pair's RED on minus RED off, from the pairs whose windows are both valid, and a negative one is a " \
          "pair whose RED-on window was faster.", "", invalid_line(report["windows"]),
          "", "### Windows", "",
          "| Mix | Pair | RED | p50 | p95 | p99 | Requests | Errors | Dropped | Unexpected | CPU stolen | Valid |",
          "|---|---|---|---|---|---|---|---|---|---|---|---|")
        report["windows"].each { |row| lines << window_row(row) }
        lines.join("\n") + "\n"
      end

      # Which windows didn't hold their rate, and why
      def invalid_line(rows)
        invalid = rows.select { |row| row["invalid"] }
        return "Every window held its rate." if invalid.empty?

        "Left out of every figure, for not holding the rate: " +
          invalid.map { |row| "#{row["mix"]} pair #{row["pair"]} RED #{row["red"]} (#{row["invalid"]})" }.join(", ") + "."
      end

      def rate_line(rate, capacity)
        if capacity
          "Rate: #{rate} requests a second, half the #{capacity} the app held with RED off."
        else
          "Rate: #{rate} requests a second, as given."
        end
      end

      def row(window)
        metrics = window.summary.fetch("metrics", {})
        latency = metrics.dig("http_req_duration", "values") || {}
        count = ->(name, field = "count") { metrics.dig(name, "values", field).to_i }
        {
          "mix" => window.mix,
          "pair" => window.pair,
          "red" => window.red ? "on" : "off",
          **LATENCIES.to_h { |name, stat| [ name, latency[stat] ] },
          "requests" => count.call("iterations"),
          "errors" => count.call("http_reqs{kind:failing}"),
          "dropped" => count.call("dropped_iterations"),
          "unexpected" => count.call("http_req_failed", "passes"),
          "cpu_stolen" => window.steal,
          "invalid" => window.shortfall
        }
      end

      # RED off and on are the median of each side's valid windows. RED added is
      # the median of each pair's on minus off, from the pairs whose windows are
      # both valid, and every such pair's is kept beside it.
      def figures(rows, seconds)
        rows = rows.reject { |row| row["invalid"] }
        sides = rows.group_by { |row| row["red"] }
        pairs = rows.group_by { |row| row["pair"] }.values.filter_map do |pair|
          off = pair.find { |row| row["red"] == "off" }
          on = pair.find { |row| row["red"] == "on" }
          [ off, on ] if off && on
        end
        latencies = LATENCIES.keys.to_h do |name|
          added = pairs.filter_map { |off, on| on[name] - off[name] if on[name] && off[name] }
          [ name, { "off" => median(sides.fetch("off", []).filter_map { |row| row[name] }),
                    "on" => median(sides.fetch("on", []).filter_map { |row| row[name] }),
                    "added" => median(added),
                    "pairs" => added } ]
        end
        errors = median(rows.map { |row| row["errors"] })
        { "errors_a_second" => (errors.to_f / seconds if errors), **latencies }
      end

      def figure_row(mix, figures, name)
        latency = figures[name]
        each_pair = latency["pairs"].map { |added| format("%+.2f", added) }.join(", ")
        each_pair = "none" if each_pair.empty?
        errors = figures["errors_a_second"] ? format("%.1f", figures["errors_a_second"]) : "n/a"
        "| #{mix} | #{errors} | #{name} | #{ms(latency["off"])} | " \
          "#{ms(latency["on"])} | #{ms(latency["added"], sign: true)} | #{each_pair} |"
      end

      def window_row(row)
        latencies = LATENCIES.keys.map { |name| ms(row[name]) }
        counts = row.values_at("requests", "errors", "dropped", "unexpected", "cpu_stolen")
        valid = row["invalid"] ? "no" : "yes"
        "| #{row["mix"]} | #{row["pair"]} | #{row["red"]} | #{(latencies + counts).join(" | ")} | #{valid} |"
      end

      def median(values)
        sorted = values.sort
        return if sorted.empty?

        middle = sorted.size / 2
        sorted.size.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
      end

      def ms(value, sign: false)
        return "n/a" if value.nil?

        format(sign ? "%+.2f ms" : "%.2f ms", value)
      end
    end
  end
end
