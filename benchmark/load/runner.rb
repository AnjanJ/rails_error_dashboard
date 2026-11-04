# frozen_string_literal: true

require "optparse"

module RedBenchmark
  # The load test (.shipkit/specs/deploy-shape-benchmark/): what RED adds to a
  # real Rails app under load, with RED off and on. bin/benchmark-load runs it.
  module Load
    # A failure the run can't go on from. bin/benchmark-load prints its message.
    class Error < StandardError; end

    USAGE = "Usage: bin/benchmark-load [--rate N]"

    # Works the stack through a driver. ComposeDriver runs it in Docker, and the
    # specs pass a fake. A driver answers four calls:
    #
    #   up                          build the app, and start it and its database
    #   start(red:)                 restart the app with RED on or off, and wait until it answers
    #   run(rate:, mix:, seconds:)  k6's summary of traffic.js's mix at that rate
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

      def initialize(driver, rate: nil, probe: PROBE, log: $stderr)
        @driver = driver
        @given = rate
        @probe = probe
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
        reasons << "#{failed} failed" if failed.positive?
        reasons << "#{finished} of #{rate * seconds} finished" if finished + dropped < rate * seconds
        reasons.join(", ") unless reasons.empty?
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
        summary = measure(red: false, rate: rate, mix: HEALTHY, **@probe)
        shortfall = self.class.shortfall(summary, rate, @probe[:seconds])
        @log.puts "  #{rate} a second: #{shortfall ? "didn't hold (#{shortfall})" : "held"}"
        shortfall.nil?
      end

      # Restarts the app with RED on or off, warms it at the rate and throws that
      # away, and returns k6's summary of the run that follows.
      def measure(red:, rate:, mix:, warmup:, seconds:)
        @driver.start(red: red)
        @driver.run(rate: rate, mix: mix, seconds: warmup)
        @driver.run(rate: rate, mix: mix, seconds: seconds)
      end
    end

    # bin/benchmark-load, given the stack's driver. Returns the exit status.
    def self.main(argv, driver:, out: $stdout, log: $stderr)
      rate = rate_given(argv)
      begin
        driver.up
        runner = Runner.new(driver, rate: rate, log: log)
        runner.rate # the capacity search, when no rate was given
        out.puts rate_line(runner)
      ensure
        driver.down
      end
      0
    rescue OptionParser::ParseError => error
      log.puts error.message, USAGE
      1
    rescue Error => error
      log.puts error.message
      1
    end

    # The rate --rate gives, or nil. It's a whole number above 0, because k6
    # starts whole requests.
    def self.rate_given(argv)
      rate = nil
      extra = OptionParser.new(USAGE) { |parser| parser.on("--rate N", Integer) { |value| rate = value } }.parse(argv)
      raise OptionParser::NeedlessArgument, extra.join(" ") unless extra.empty?
      raise OptionParser::InvalidArgument, "--rate #{rate}" unless rate.nil? || rate.positive?

      rate
    end

    def self.rate_line(runner)
      if runner.capacity
        "Rate: #{runner.rate} requests a second, half the #{runner.capacity} the app held with RED off."
      else
        "Rate: #{runner.rate} requests a second, as given."
      end
    end
    private_class_method :rate_given, :rate_line
  end
end
