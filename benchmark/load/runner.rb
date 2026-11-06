# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"
require_relative "../harness"
require_relative "compare"
require_relative "load_report"
require_relative "shapes"
require_relative "stacks"

module RedBenchmark
  # The load test (.shipkit/specs/deploy-shape-benchmark/): what RED adds to a
  # real Rails app under load, with RED off and on. bin/benchmark-load runs it.
  module Load
    # A failure the run can't go on from. bin/benchmark-load prints its message.
    class Error < StandardError; end

    USAGE = "Usage: bin/benchmark-load [--rate N] [--shape NAME] [--stack NAME] [--ruby VERSION] [--json FILE] [--summary FILE]\n" \
      "       bin/benchmark-load --compare FIRST.json SECOND.json [--summary FILE]"

    # Works the stack through a driver. ComposeDriver runs it in Docker, and the
    # specs pass a fake. A driver answers these calls:
    #
    #   up                          build the app, and start it and its database
    #   environment                 bin/benchmark's environment block, as the app has it
    #   start(red:)                 restart the app with RED on or off, and wait until it answers
    #   run(rate:, mix:, seconds:)  k6's summary of traffic.js's mix at that rate
    #   cpu_ticks                   the machine's CPU ticks, as Harness.cpu_ticks reads them
    #   throttling                  { times:, usec: } the app's CPU quota held it back, or nil
    #   down                        remove the stack
    class Runner
      # With no rate given, the windows run at half the app's capacity with RED
      # off (REQ-10): the most requests a second it holds. The search doubles
      # the rate from FIRST_PROBE until the app doesn't hold one, then halves the
      # gap until the rate that held and the one that didn't are within
      # PRECISION of each other. The capacity is the one that held.
      FIRST_PROBE = 10
      MOST = 10_000
      PRECISION = 0.1

      # Each probe restarts the app with RED off, warms it at the probe's rate
      # and throws that away, then measures. Past its capacity an app falls
      # further behind every second, until k6 has no free VU to start a request
      # with and drops it, so a longer probe catches a smaller overload.
      PROBE = { warmup: 30, seconds: 60 }.freeze
      HEALTHY = "healthy"

      # The windows (REQ-11): RED off and on in turn, all at the one rate, in
      # pairs whose order alternates, ABBA: off then on, on then off, and so on,
      # so a steady drift in the runner's speed falls on both sides alike. Each
      # window restarts the app, so neither side inherits the other's warm-up,
      # and throws its warm-up away.
      MIXES = %w[healthy failing storm].freeze
      PAIRS = 5
      WINDOW = { warmup: 60, seconds: 120 }.freeze

      # One window: its mix, its pair, whether RED was on, k6's summary of its
      # measured run, the share of the machine's CPU time stolen during that run
      # (REQ-14), how often and how long the app's CPU quota held it back during
      # that run (REQ-16), and why it didn't hold its rate, judged as a probe is,
      # or nil (REQ-15).
      Window = Data.define(:mix, :pair, :red, :summary, :steal, :throttled, :shortfall)

      # How long each window warms the app, and measures it
      attr_reader :window

      def initialize(driver, rate: nil, probe: PROBE, window: WINDOW, log: $stderr)
        @driver = driver
        @given = rate
        @probe = probe
        @window = window
        @log = log
      end

      # The rate every window runs at: the one given, or half the capacity.
      def rate
        @rate ||= @given || [ capacity / 2, 1 ].max
      end

      # The most requests a second the app held with RED off, or nil when a
      # rate was given and nothing was measured.
      def capacity
        @capacity ||= search unless @given
      end

      # Every window, in the order they ran: each mix in turn, PAIRS pairs of it.
      def windows
        @windows ||= begin
          @log.puts "Windows at #{rate} requests a second: #{PAIRS} pairs of RED off and on for each mix, each " \
            "window a restart, #{@window[:warmup]} s of warm-up and #{@window[:seconds]} s measured."
          MIXES.flat_map { |mix| (1..PAIRS).flat_map { |pair| pair_of(mix, pair) } }
        end
      end

      # Why a k6 run didn't hold its rate, or nil when it did. It didn't if k6
      # dropped requests because the app was too far behind to take them, if a
      # request got a status its kind doesn't expect, or if fewer requests
      # finished than k6 starts at that rate in that time: R × D, and one more.
      # k6 leaves a metric out of its summary when nothing counted towards it.
      def self.shortfall(summary, rate, seconds)
        metrics = summary.fetch("metrics", {})
        dropped = metrics.dig("dropped_iterations", "values", "count").to_i
        failed = metrics.dig("http_req_failed", "values", "passes").to_i
        finished = metrics.dig("iterations", "values", "count").to_i

        reasons = []
        reasons << "#{dropped} dropped" if dropped.positive?
        reasons << "#{failed} with an unexpected status" if failed.positive?
        reasons << "#{finished} of #{rate * seconds} finished" if finished + dropped < rate * seconds
        reasons.join(", ") unless reasons.empty?
      end

      # How often, and for how long, the app's CPU quota held it back between two
      # of the driver's readings. A shape with no quota reads 0 times.
      def self.throttled(before, after)
        return "not available" unless before && after

        times = after[:times] - before[:times]
        format("%d %s, %.2f s", times, times == 1 ? "time" : "times", (after[:usec] - before[:usec]) / 1_000_000.0)
      end

      private

      def search
        @log.puts "Measuring the app's capacity with RED off: #{@probe[:seconds]} s at each rate, " \
          "after a restart and #{@probe[:warmup]} s of warm-up."
        held = 0
        failed = nil
        probe = FIRST_PROBE
        loop do
          if holds?(probe)
            held = probe
          else
            failed = probe
          end
          break if failed && failed - held <= [ held * PRECISION, 1 ].max
          raise Error, "With RED off, the app held #{MOST} requests a second, the most this tries." if held == MOST

          probe = failed ? (held + failed) / 2 : [ probe * 2, MOST ].min
        end
        raise Error, "With RED off, the app held no rate, down to 1 request a second." if held.zero?

        held
      end

      def holds?(rate)
        summary, = measure(red: false, rate: rate, mix: HEALTHY, **@probe)
        shortfall = self.class.shortfall(summary, rate, @probe[:seconds])
        @log.puts "  #{rate} a second: #{shortfall ? "didn't hold (#{shortfall})" : "held"}"
        shortfall.nil?
      end

      # An odd pair runs RED off then on, and an even one on then off.
      def pair_of(mix, pair)
        (pair.odd? ? [ false, true ] : [ true, false ]).map do |red|
          @log.puts "  #{mix}, pair #{pair} of #{PAIRS}, RED #{red ? "on" : "off"}"
          summary, steal, throttled = measure(red: red, rate: rate, mix: mix, **@window)
          Window.new(mix: mix, pair: pair, red: red, summary: summary, steal: steal, throttled: throttled,
            shortfall: self.class.shortfall(summary, rate, @window[:seconds]))
        end
      end

      # Restarts the app with RED on or off, warms it at the rate and throws that
      # away, then runs it again. Returns k6's summary of that run, the share of
      # the machine's CPU time stolen while it went, and how the app's CPU quota
      # held it back.
      def measure(red:, rate:, mix:, warmup:, seconds:)
        @driver.start(red: red)
        @driver.run(rate: rate, mix: mix, seconds: warmup)
        ticks = @driver.cpu_ticks
        throttling = @driver.throttling
        summary = @driver.run(rate: rate, mix: mix, seconds: seconds)
        [ summary, Harness.stolen_share(ticks, @driver.cpu_ticks), self.class.throttled(throttling, @driver.throttling) ]
      end
    end

    # bin/benchmark-load, given what makes the stack's driver for a shape, or
    # for none, a stack and a Ruby. Returns the exit status.
    def self.main(argv, driver:, out: $stdout, log: $stderr)
      options = parse_options(argv)
      return compare(options, out) if options[:compare]

      shape = options[:shape] && Shapes.fetch(options[:shape])
      stack = Stacks.fetch(options.fetch(:stack, Stacks::DEFAULT))
      driver = driver.call(shape: shape, stack: stack, ruby: options.fetch(:ruby, Stacks::DEFAULT_RUBY))
      report = begin
        driver.up
        environment = driver.environment
        runner = Runner.new(driver, rate: options[:rate], log: log)
        log.puts LoadReport.rate_line(runner.rate, runner.capacity)
        LoadReport.build(environment: environment, rate: runner.rate, capacity: runner.capacity,
          window: runner.window, windows: runner.windows, shape: shape)
      ensure
        driver.down
      end
      publish(report, options, out)
      0
    rescue OptionParser::ParseError => error
      log.puts error.message, USAGE
      1
    rescue Error => error
      log.puts error.message
      1
    end

    # --rate is a whole number above 0, because k6 starts whole requests.
    # --shape is one of Shapes', --stack one of Stacks' and --ruby one of its
    # Rubies. --compare takes two reports and nothing that measures, as it
    # starts no stack (REQ-20).
    def self.parse_options(argv)
      options = {}
      parser = OptionParser.new(USAGE)
      parser.on("--rate N", Integer) { |value| options[:rate] = value }
      parser.on("--shape NAME", Shapes.names) { |value| options[:shape] = value }
      parser.on("--stack NAME", Stacks.names) { |value| options[:stack] = value }
      parser.on("--ruby VERSION", Stacks::RUBIES) { |value| options[:ruby] = value }
      parser.on("--json FILE") { |value| options[:json] = value }
      parser.on("--summary FILE") { |value| options[:summary] = value }
      parser.on("--compare") { options[:compare] = true }
      extra = parser.parse(argv)
      if options[:compare]
        raise OptionParser::InvalidArgument, "--compare needs two reports" unless extra.size == 2
        measuring = (options.keys & [ :rate, :shape, :stack, :ruby, :json ]).map { |name| "--#{name}" }
        raise OptionParser::InvalidArgument, "--compare with #{measuring.join(", ")}" unless measuring.empty?

        options[:reports] = extra
        return options
      end
      raise OptionParser::NeedlessArgument, extra.join(" ") unless extra.empty?
      raise OptionParser::InvalidArgument, "--rate #{options[:rate]}" unless options.fetch(:rate, 1).positive?

      options
    end

    # Two reports side by side, on stdout, and added to a summary file when
    # asked (REQ-20). It reads both before it prints anything.
    def self.compare(options, out)
      first, second = options[:reports].map { |path| Compare.read(path) }
      markdown = Compare.markdown(first, second, names: options[:reports])
      out.puts markdown
      File.open(options[:summary], "a") { |file| file.puts(markdown) } if options[:summary]
      0
    end

    # The report's figures as JSON when asked, and the report as Markdown on
    # stdout, and added to a summary file when asked, as bin/benchmark does.
    def self.publish(report, options, out)
      if options[:json]
        FileUtils.mkdir_p(File.dirname(options[:json]))
        File.write(options[:json], "#{JSON.pretty_generate(report)}\n")
      end
      markdown = LoadReport.markdown(report)
      out.puts markdown
      File.open(options[:summary], "a") { |file| file.puts(markdown) } if options[:summary]
    end
    private_class_method :parse_options, :compare, :publish
  end
end
