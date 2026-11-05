# frozen_string_literal: true

require "socket"

module RedBenchmark
  module Load
    # The deploy shapes (.shipkit/specs/deploy-shape-benchmark/, REQ-16): the
    # CPUs, CPU quota and memory the app is held to, so it sees the machine a
    # deploy target of that size would give it. Each is named for its size,
    # never for a product. A runner has 4 CPUs: the app gets 0 and 1, or just 0,
    # and its database, its queue and k6 get 2 and 3, so neither eats into the
    # other. Swap is off, as on a small plan's machine.
    #
    # A shape also puts its database across a network (REQ-17): tc netem delays
    # what the database sends by the shape's delay_ms. 1 ms is a chosen value,
    # since nothing published gives a typical app-to-database round trip, so a
    # report states the round trip it measured beside it.
    #
    #   ruby benchmark/load/shapes.rb NAME
    #       print NAME's docker run limits, one to a line
    #   ruby benchmark/load/shapes.rb --delay SHAPE CONTAINER HOST PORT
    #       delay CONTAINER's network by SHAPE's delay, and print the round trip
    #       to HOST:PORT measured before and after it
    module Shapes
      # The CPUs everything but the app runs on
      REST = "2,3"

      # tc comes from iproute2, which the database's own image doesn't have, so
      # it runs in this one, in the database container's network. Pinned, as k6 is.
      NETEM_IMAGE = "alpine:3.20@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc"

      # TCP connects whose median is the round trip: a connect takes exactly one
      CONNECTS = 20

      USAGE = "Usage: ruby benchmark/load/shapes.rb --delay SHAPE CONTAINER HOST PORT"

      # cpus: the app's CPUs. quota: how much of them it may use, in CPUs, or nil.
      # memory: its memory, with no swap. delay_ms: what the network adds to the
      # database's replies. runner: the hosted runner it runs on.
      Shape = Data.define(:name, :cpus, :quota, :memory, :delay_ms, :runner, :size_of) do
        # The variables compose.yml holds the app and the rest to. compose reads
        # an empty quota as none.
        def compose_env
          { "APP_CPUSET" => cpus, "APP_CPUS" => quota.to_s, "APP_MEMORY" => memory, "REST_CPUSET" => REST }
        end

        # The same limits, for a container docker run starts
        def docker_args
          args = [ "--cpuset-cpus=#{cpus}", "--memory=#{memory}", "--memory-swap=#{memory}" ]
          quota ? args << "--cpus=#{quota}" : args
        end
      end

      ALL = [
        Shape.new(name: "medium", cpus: "0,1", quota: nil, memory: "4g", delay_ms: 1, runner: "ubuntu-24.04",
          size_of: "a 2 vCPU, 4 GB plan"),
        Shape.new(name: "small", cpus: "0", quota: nil, memory: "1g", delay_ms: 1, runner: "ubuntu-24.04",
          size_of: "a 1 vCPU, 1 GB plan"),
        Shape.new(name: "medium-throttled", cpus: "0,1", quota: "0.4", memory: "4g", delay_ms: 1, runner: "ubuntu-24.04",
          size_of: "a burstable plan at a 20% per-vCPU baseline"),
        Shape.new(name: "medium-arm", cpus: "0,1", quota: nil, memory: "4g", delay_ms: 1, runner: "ubuntu-24.04-arm",
          size_of: "a 2 vCPU, 4 GB ARM plan")
      ].freeze

      def self.names
        ALL.map(&:name)
      end

      def self.fetch(name)
        ALL.find { |shape| shape.name == name } or raise KeyError, "No shape #{name}: #{names.join(", ")}"
      end

      # The command that delays everything the container sends by ms
      def self.netem(container, ms)
        [ "docker", "run", "--rm", "--network", "container:#{container}", "--cap-add", "NET_ADMIN", NETEM_IMAGE,
          "sh", "-c", "apk add --no-cache --quiet iproute2 && tc qdisc add dev eth0 root netem delay #{ms}ms" ]
      end

      # The median time in ms to open a TCP connection to host:port, or nil when
      # nothing answers there. TCPSocket, because Socket.tcp with a timeout
      # returned a socket for a refused connect on macOS (Ruby 3.4.5).
      def self.round_trip(host, port, connects: CONNECTS)
        times = Array.new(connects) do
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          TCPSocket.new(host, port, connect_timeout: 2).close
          (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
        end
        times.sort[times.size / 2]
      rescue SystemCallError, SocketError, IOError
        nil
      end

      # The round trip measured after any delay, how much of it the delay added,
      # and the delay set
      def self.round_trip_line(before, after, delay_ms)
        return format("%.2f ms, nothing added", after) if after && delay_ms.nil?
        return "not available" unless before && after

        format("%.2f ms, %.2f ms of it added (%d ms set)", after, after - before, delay_ms)
      end
    end
  end
end

# Run as a script, not piped into ruby -, as the load test's driver does
if __FILE__ == $PROGRAM_NAME && File.file?(__FILE__)
  shapes = RedBenchmark::Load::Shapes
  begin
    if ARGV.first == "--delay"
      abort shapes::USAGE unless ARGV.size == 5
      _, name, container, host, port = ARGV
      shape = shapes.fetch(name)
      before = shapes.round_trip(host, Integer(port))
      system(*shapes.netem(container, shape.delay_ms)) or abort "Couldn't delay #{container}'s network"
      puts "Rows' database round trip: #{shapes.round_trip_line(before, shapes.round_trip(host, Integer(port)), shape.delay_ms)}"
    else
      puts shapes.fetch(ARGV.fetch(0, "")).docker_args
    end
  rescue KeyError => error
    abort error.message
  end
end
