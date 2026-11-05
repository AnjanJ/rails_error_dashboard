# frozen_string_literal: true

module RedBenchmark
  module Load
    # The deploy shapes (.shipkit/specs/deploy-shape-benchmark/, REQ-16): the
    # CPUs, CPU quota and memory the app is held to, so it sees the machine a
    # deploy target of that size would give it. Each is named for its size,
    # never for a product. A runner has 4 CPUs: the app gets 0 and 1, or just 0,
    # and its database, its queue and k6 get 2 and 3, so neither eats into the
    # other. Swap is off, as on a small plan's machine.
    #
    #   ruby benchmark/load/shapes.rb NAME    print NAME's docker run limits, one to a line
    module Shapes
      # The CPUs everything but the app runs on
      REST = "2,3"

      # cpus: the app's CPUs. quota: how much of them it may use, in CPUs, or nil.
      # memory: its memory, with no swap. runner: the hosted runner it runs on.
      Shape = Data.define(:name, :cpus, :quota, :memory, :runner, :size_of) do
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
        Shape.new(name: "medium", cpus: "0,1", quota: nil, memory: "4g", runner: "ubuntu-24.04",
          size_of: "a 2 vCPU, 4 GB plan"),
        Shape.new(name: "small", cpus: "0", quota: nil, memory: "1g", runner: "ubuntu-24.04",
          size_of: "a 1 vCPU, 1 GB plan"),
        Shape.new(name: "medium-throttled", cpus: "0,1", quota: "0.4", memory: "4g", runner: "ubuntu-24.04",
          size_of: "a burstable plan at a 20% per-vCPU baseline"),
        Shape.new(name: "medium-arm", cpus: "0,1", quota: nil, memory: "4g", runner: "ubuntu-24.04-arm",
          size_of: "a 2 vCPU, 4 GB ARM plan")
      ].freeze

      def self.names
        ALL.map(&:name)
      end

      def self.fetch(name)
        ALL.find { |shape| shape.name == name } or raise KeyError, "No shape #{name}: #{names.join(", ")}"
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    puts RedBenchmark::Load::Shapes.fetch(ARGV.fetch(0, "")).docker_args
  rescue KeyError => error
    abort error.message
  end
end
