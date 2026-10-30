# frozen_string_literal: true

require "rails_helper"

# overhead-benchmark/REQ-10: what the docs say about overhead comes from
# bin/benchmark, and each figure says which machine it came from. CI's runners
# aren't one CPU, and the same code's health snapshot more than doubles between
# them, so a figure with no CPU beside it doesn't tell a reader much.
RSpec.describe "What the docs say about overhead" do
  root = RailsErrorDashboard::Engine.root

  # One sentence, word for word, on every page that quotes the row, so a page
  # can't be left behind when the figures change.
  health = "a median of 0.45 ms on an AMD EPYC 9V45, 0.80 ms on an AMD EPYC 7763, " \
           "0.85 ms on an AMD EPYC 9V74 and 1.24 ms on an Intel Xeon Platinum 8573C, " \
           "against a 1 ms budget"
  breadcrumb = "a median of 1.18 µs on CI's AMD EPYC 9V45 runner and 1.89 µs on its " \
               "AMD EPYC 7763 runner, against a 10 µs budget"

  health_pages = %w[
    README.md docs/FEATURES.md _getting_started/features.md
    docs/guides/CONFIGURATION.md _guides/configuration.md
  ]
  breadcrumb_pages = %w[
    docs/FEATURES.md docs/LLM_OBSERVABILITY.md _getting_started/features.md
    docs/guides/CONFIGURATION.md _guides/configuration.md
  ]
  llm_pages = %w[docs/FEATURES.md docs/LLM_OBSERVABILITY.md]
  pages = (health_pages + breadcrumb_pages).uniq

  link = %r{\]\((?:\.\./)*bin/benchmark\)|\]\(https://github\.com/AnjanJ/rails_error_dashboard/blob/main/bin/benchmark\)}
  runner = /AMD EPYC|Intel Xeon/
  figure = /\d(?:\.\d+)?\s?(?:µs|μs|ms\b|microseconds?\b)/
  # What makes a time on a line a cost, not a threshold or a line of sample output
  cost = /overhead|hot path|per breadcrumb|per error|median|sub-?millisecond/i

  # Lines outside fenced code blocks
  prose = lambda do |page|
    fenced = false
    root.join(page).readlines.reject do |line|
      fence = line.lstrip.start_with?("```")
      fenced = !fenced if fence
      fenced || fence
    end
  end

  pages.each do |page|
    it "#{page} doesn't say there's no benchmark, or that one ships in the gem (overhead-benchmark/REQ-10)" do
      text = root.join(page).read

      expect(text).not_to match(/no benchmark|benchmark script|benchmark is still to come|single-machine/i)
      expect(text).not_to match(/benchmark[^.\n]*ships with|ships with[^.\n]*benchmark/i)
    end

    it "#{page} links bin/benchmark (overhead-benchmark/REQ-10)" do
      expect(root.join(page).read).to match(link)
    end

    it "#{page} names the runner beside every overhead figure (overhead-benchmark/REQ-10)" do
      quoted = prose.call(page).select { |line| line.match?(figure) && line.match?(cost) }

      expect(quoted.reject { |line| line.match?(runner) }).to be_empty
    end
  end

  health_pages.each do |page|
    it "#{page} gives the health snapshot per CPU, not a flat promise (overhead-benchmark/REQ-10)" do
      text = root.join(page).read

      expect(text).to include(health)
      expect(text).not_to match(/sub-millisecond|completes? in < ?1 ?ms/i)
    end
  end

  breadcrumb_pages.each do |page|
    it "#{page} quotes the breadcrumb row in the same words (overhead-benchmark/REQ-10)" do
      expect(root.join(page).read).to include(breadcrumb)
    end
  end

  # The row times the sql.active_record subscriber, so it can't stand in for
  # the LLM path without saying so.
  llm_pages.each do |page|
    it "#{page} says the benchmark has no LLM row (overhead-benchmark/REQ-10)" do
      expect(root.join(page).read).to include("has no row for LLM breadcrumbs")
    end
  end

  it "quotes the storm rows on both CPUs that ran the final code (overhead-benchmark/REQ-10)" do
    overhead = prose.call("README.md").find { |line| line.start_with?("**Overhead:**") }

    expect(overhead).to include("AMD EPYC 9V45", "AMD EPYC 7763", "15µs budget", "Ruby 3.4.12", "Rails 8.1.4", "SQLite")
  end
end
