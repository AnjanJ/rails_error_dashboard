# frozen_string_literal: true

require "json"
require "open3"
require_relative "runner"

module RedBenchmark
  module Load
    # The stack Runner works, in Docker: compose.yml's app and PostgreSQL, and
    # its k6 service for each run. compose hands RED to the app, which leaves
    # RED out when it's "off". Given a shape, every command passes on its
    # limits, which compose.yml holds the app and the rest to (REQ-16), and the
    # database's network gets the shape's delay (REQ-17).
    class ComposeDriver
      FILE = File.join(__dir__, "compose.yml")
      HARNESS = File.expand_path("../harness.rb", __dir__)
      SHAPES = File.join(__dir__, "shapes.rb")
      # Seconds to wait for the app to answer after a start. Its healthcheck
      # gives a new container 120 s before a failed check counts.
      WAIT = 300

      # The shape's limits and delay, or none
      def initialize(shape: nil)
        @limits = shape ? shape.compose_env : {}
        @delay = shape&.delay_ms
      end

      # Builds the app's image from this checkout, and starts the stack with RED
      # on. A new database needs RED on to be prepared: one of RED's migrations
      # reads RED's models, which RED off doesn't load. Then, with a shape, it
      # delays the database's network, once the app's round trip to it has been
      # measured without the delay. The database outlives every restart of the
      # app, so the delay holds for the whole run.
      def up
        compose!({ "RED" => "on" }, "up", "--build", "--wait", "--wait-timeout", WAIT.to_s)
        @round_trip_before = round_trip
        delay_database if @delay
      end

      # bin/benchmark's environment block, read inside the app's container by the
      # same code, so the Ruby, CPUs and limits are the ones the app has. The
      # container has no git, so the commit is this checkout's. The app's round
      # trip to the database is measured again, after any delay.
      def environment
        script = "#{File.read(HARNESS)}\nputs JSON.generate(RedBenchmark::Harness.environment)\n"
        output = compose!({}, "exec", "-T", "app", "bin/rails", "runner", "-", stdin: script)
        line = output.lines.reverse.find { |each| each.start_with?("{") }
        raise Error, "The app printed no environment:\n#{output}" unless line

        JSON.parse(line).merge("RED commit" => Harness.commit,
          "Database round trip" => Shapes.round_trip_line(@round_trip_before, round_trip, @delay))
      end

      # The machine's CPU ticks, for the share stolen during a window. On a
      # runner, its containers share them.
      def cpu_ticks
        Harness.cpu_ticks
      end

      # How often, and for how many microseconds in all, the app's CPU quota has
      # held it back since its container started, from its cgroup's cpu.stat
      # (REQ-16). nil where the container has no such file, as under cgroup v1.
      def throttling
        stat = compose!({}, "exec", "-T", "app", "cat", "/sys/fs/cgroup/cpu.stat")
        times = stat[/^nr_throttled (\d+)$/, 1]
        usec = stat[/^throttled_usec (\d+)$/, 1]
        { times: times.to_i, usec: usec.to_i } if times && usec
      rescue Error
        nil
      end

      # A new app container, with RED on or off, once it answers. The database,
      # and what's in it, stay.
      def start(red:)
        compose!({ "RED" => red ? "on" : "off" }, "up", "--wait", "--wait-timeout", WAIT.to_s,
          "--force-recreate", "--no-deps", "app")
      end

      # k6's summary of traffic.js's mix at the rate, for that many seconds,
      # which the script prints as JSON on stdout.
      def run(rate:, mix:, seconds:)
        output = compose!({}, "run", "--rm", "--env", "RATE=#{rate}", "--env", "MIX=#{mix}",
          "--env", "DURATION=#{seconds}s", "k6", "run", "--quiet", "/scripts/traffic.js")
        summary = output.index("{") or raise Error, "k6 printed no summary:\n#{output}"
        JSON.parse(output[summary..])
      end

      # Removes the stack, volumes and all. Quietly, because it runs however the
      # run ended, and mustn't hide why.
      def down
        system(@limits, *command, "down", "--volumes", out: File::NULL, err: File::NULL)
      end

      private

      def command
        [ "docker", "compose", "--file", FILE ]
      end

      # The app's round trip to the database in ms, measured inside its
      # container by Shapes' own code, or nil where it can't be.
      def round_trip
        script = "#{File.read(SHAPES)}\nprint RedBenchmark::Load::Shapes.round_trip(\"db\", 5432)\n"
        Float(compose!({}, "exec", "-T", "app", "ruby", "-", stdin: script).strip)
      rescue Error, ArgumentError
        nil
      end

      # A run without the delay it was asked for would be wrong, so it stops.
      def delay_database
        database = compose!({}, "ps", "--quiet", "db").strip
        capture!({}, *Shapes.netem(database, @delay), what: "Delaying the database's network")
      end

      def compose!(env, *arguments, stdin: "")
        capture!(@limits.merge(env), *command, *arguments, stdin: stdin, what: "docker compose #{arguments.first}")
      end

      def capture!(env, *argv, what:, stdin: "")
        output, errors, status = Open3.capture3(env, *argv, stdin_data: stdin)
        raise Error, "#{what} failed:\n#{errors}#{output}" unless status.success?

        output
      end
    end
  end
end
