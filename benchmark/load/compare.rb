# frozen_string_literal: true

require "json"
require_relative "load_report"

module RedBenchmark
  module Load
    # A failure the run can't go on from, as runner.rb has it
    class Error < StandardError; end

    # The compare tool (REQ-20): two load test reports, as bin/benchmark-load
    # --json writes them, side by side. For each mix and latency it prints what
    # RED added in each report, and the second's over the first's. The figures
    # are each report's own, read as they are: it measures nothing itself.
    module Compare
      # What each report measured, from its environment block
      ENVIRONMENT = [ "CPU", "CPU topology", "CPU limit", "Memory limit", "Database round trip", "RED commit" ].freeze

      module_function

      # A report's figures, or Error naming the file when it isn't one
      def read(path)
        report = JSON.parse(File.read(path))
        return report if report.is_a?(Hash) && report["mixes"].is_a?(Hash)

        raise Error, not_a_report(path)
      rescue JSON::ParserError, SystemCallError
        raise Error, not_a_report(path)
      end

      def markdown(first, second, names:)
        lines = [ "## What RED added in two load tests", "",
          "| | First | Second |", "|---|---|---|",
          "| Report | #{names[0]} | #{names[1]} |",
          "| Shape | #{shape(first)} | #{shape(second)} |" ]
        ENVIRONMENT.each do |name|
          values = [ first, second ].map { |report| report.fetch("environment", {})[name] }
          lines << "| #{name} | #{values.map { |value| value || "n/a" }.join(" | ")} |" if values.any?
        end
        lines.push("| Rate | #{rate(first)} | #{rate(second)} |", "",
          "| Mix | Latency | RED added, first | RED added, second | Second over first |",
          "|---|---|---|---|---|")
        (first["mixes"].keys | second["mixes"].keys).each do |mix|
          LoadReport::LATENCIES.each_key do |latency|
            added = [ first, second ].map { |report| report["mixes"].key?(mix) ? report["mixes"][mix].dig(latency, "added") : :not_run }
            lines << "| #{mix} | #{latency} | #{added.map { |value| cell(value) }.join(" | ")} | #{ratio_cell(*added)} |"
          end
        end
        lines.push("", "RED added is each report's own figure: the median of its pairs' RED on minus RED off. The " \
          "ratio is the second's over the first's, and reads n/a where a report didn't run the mix, had no valid " \
          "pair, or had RED adding nothing or less. A ratio of two small figures is mostly noise, so read it " \
          "beside each report's pairs.")
        lines.join("\n") + "\n"
      end

      # The second's added time over the first's, when both are above 0. Below
      # that, a ratio would say nothing about how RED's cost grew.
      def ratio(first, second)
        return unless first.is_a?(Numeric) && second.is_a?(Numeric) && first.positive? && second.positive?

        second / first.to_f
      end

      def cell(value)
        return "not run" if value == :not_run

        LoadReport.ms(value, sign: true)
      end

      def ratio_cell(first, second)
        value = ratio(first, second)
        value ? format("%.2fx", value) : "n/a"
      end

      # A report from before reports named their shape has no "shape" at all,
      # and one run without a shape has it as null.
      def shape(report)
        return "not recorded" unless report.key?("shape")

        shape = report["shape"]
        shape ? "#{shape["name"]}, the size of #{shape["size_of"]}" : "none"
      end

      def rate(report)
        report["rate"] ? "#{report["rate"]} requests a second" : "n/a"
      end

      def not_a_report(path)
        "#{path} isn't a load test report: bin/benchmark-load --json writes one."
      end
      private_class_method :cell, :ratio_cell, :shape, :rate, :not_a_report
    end
  end
end
