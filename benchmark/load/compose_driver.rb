# frozen_string_literal: true

require "json"
require "open3"
require_relative "runner"
require_relative "stacks"

module RedBenchmark
  module Load
    # The stack Runner works, in Docker: compose.yml's app and k6, with the
    # stack's database and queue laid over it from stacks/ (REQ-16), on the Ruby
    # asked for. compose hands RED to the app, which leaves RED out when it's
    # "off". Given a shape, every command passes on its limits, which the
    # compose files hold the app and the rest to (REQ-16), and whatever the
    # stack has across the network gets the shape's delay (REQ-17).
    class ComposeDriver
      HARNESS = File.expand_path("../harness.rb", __dir__)
      SHAPES = File.join(__dir__, "shapes.rb")
      # Seconds to wait for the app to answer after a start. Its healthcheck
      # gives a new container 120 s before a failed check counts.
      WAIT = 300
      # What the report says of the round trip on a stack with no database server
      NO_NETWORK = "none: SQLite is a file in the app's container"

      # The shape's limits and delay, or none, the stack, and the Ruby
      def initialize(shape: nil, stack: Stacks.fetch(Stacks::DEFAULT), ruby: Stacks::DEFAULT_RUBY)
        @stack = stack
        @env = (shape ? shape.compose_env : {}).merge("APP_RUBY" => ruby)
        @delay = shape&.delay_ms
      end

      # Builds the app's image from this checkout, and starts the stack with RED
      # on. A new database needs RED on to be prepared: one of RED's migrations
      # reads RED's models, which RED off doesn't load. Then, with a shape, it
      # delays the network of each part across it, the database and any Redis,
      # once the app's round trip to each has been measured without the delay.
      # They outlive every restart of the app, so the delay holds for the whole
      # run.
      def up
        compose!({ "RED" => "on" }, "up", "--build", "--wait", "--wait-timeout", WAIT.to_s)
        @round_trips_before = round_trips
        delay_network if @delay
      end

      # bin/benchmark's environment block, read inside the app's container by the
      # same code, so the Ruby, CPUs and limits are the ones the app has. The
      # container has no git, so the commit is this checkout's. Then the stack,
      # and the app's round trip to each part across the network, measured
      # again, after any delay.
      def environment
        script = "#{File.read(HARNESS)}\nputs JSON.generate(RedBenchmark::Harness.environment)\n"
        output = compose!({}, "exec", "-T", "app", "bin/rails", "runner", "-", stdin: script)
        line = output.lines.reverse.find { |each| each.start_with?("{") }
        raise Error, "The app printed no environment:\n#{output}" unless line

        JSON.parse(line).merge("RED commit" => Harness.commit, "Stack" => @stack.name).merge(round_trip_lines)
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
        system(@env, *command, "down", "--volumes", out: File::NULL, err: File::NULL)
      end

      private

      def command
        [ "docker", "compose", *@stack.compose_args ]
      end

      # "<Label> round trip" for each part across the network, or the one line
      # that says there's none
      def round_trip_lines
        return { "Database round trip" => NO_NETWORK } if @stack.network.empty?

        after = round_trips
        @stack.network.keys.to_h do |label|
          [ "#{label} round trip", Shapes.round_trip_line(@round_trips_before[label], after[label], @delay) ]
        end
      end

      # The app's round trip in ms to each part across the network, by label,
      # measured inside its container by Shapes' own code, or nil where it can't be.
      def round_trips
        @stack.network.transform_values do |(service, port)|
          script = "#{File.read(SHAPES)}\nprint RedBenchmark::Load::Shapes.round_trip(#{service.dump}, #{port})\n"
          begin
            Float(compose!({}, "exec", "-T", "app", "ruby", "-", stdin: script).strip)
          rescue Error, ArgumentError
            nil
          end
        end
      end

      # A run without the delay it was asked for would be wrong, so it stops.
      def delay_network
        @stack.network.each do |label, (service, _port)|
          container = compose!({}, "ps", "--quiet", service).strip
          capture!({}, *Shapes.netem(container, @delay), what: "Delaying the network of #{label}")
        end
      end

      def compose!(env, *arguments, stdin: "")
        capture!(@env.merge(env), *command, *arguments, stdin: stdin, what: "docker compose #{arguments.first}")
      end

      def capture!(env, *argv, what:, stdin: "")
        output, errors, status = Open3.capture3(env, *argv, stdin_data: stdin)
        raise Error, "#{what} failed:\n#{errors}#{output}" unless status.success?

        output
      end
    end
  end
end
