# frozen_string_literal: true

require "json"
require "open3"
require_relative "runner"

module RedBenchmark
  module Load
    # The stack Runner works, in Docker: compose.yml's app and PostgreSQL, and
    # its k6 service for each run. compose hands RED to the app, which leaves
    # RED out when it's "off".
    class ComposeDriver
      FILE = File.join(__dir__, "compose.yml")
      # Seconds to wait for the app to answer after a start. Its healthcheck
      # gives a new container 120 s before a failed check counts.
      WAIT = 300

      # Builds the app's image from this checkout, and starts the stack with RED
      # on. A new database needs RED on to be prepared: one of RED's migrations
      # reads RED's models, which RED off doesn't load.
      def up
        compose!({ "RED" => "on" }, "up", "--build", "--wait", "--wait-timeout", WAIT.to_s)
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
        system(*command, "down", "--volumes", out: File::NULL, err: File::NULL)
      end

      private

      def command
        [ "docker", "compose", "--file", FILE ]
      end

      def compose!(env, *arguments)
        output, errors, status = Open3.capture3(env, *command, *arguments)
        raise Error, "docker compose #{arguments.first} failed:\n#{errors}#{output}" unless status.success?

        output
      end
    end
  end
end
