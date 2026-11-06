# frozen_string_literal: true

module RedBenchmark
  module Load
    # The stacks the load test's app and the rows run on
    # (.shipkit/specs/deploy-shape-benchmark/, REQ-16), beside the shape they're
    # held to. The default is what a new Rails app gets and most apps run:
    # PostgreSQL, with Solid Queue inside Puma. The others swap one part, as
    # the apps that picked Sidekiq, MySQL or SQLite did. Ruby is 3.4 unless 4.0
    # is asked for.
    #
    # A stack's name is its two parts, the database and the queue, and each
    # part is a compose file in stacks/, laid over compose.yml. A part across
    # the network from the app gets the shape's delay (REQ-17): a database
    # server, and Sidekiq's Redis. SQLite is a file in the app's container.
    #
    #   ruby benchmark/load/stacks.rb --rows STACK DATABASE_IP REDIS_IP
    #       print the docker run options that point bin/benchmark's rows at
    #       STACK's database and queue, one to a line. An address the stack
    #       has no use for may be empty.
    module Stacks
      LOAD = __dir__

      DEFAULT = "postgres-solid-queue"
      RUBIES = %w[3.4 4.0].freeze
      DEFAULT_RUBY = "3.4"

      USAGE = "Usage: ruby benchmark/load/stacks.rb --rows STACK DATABASE_IP REDIS_IP"

      # network: what a report calls each part across the network, with its
      # compose service and port. queue: bin/benchmark's BENCHMARK_QUEUE.
      # rows_database: bin/benchmark's BENCHMARK_DATABASE_URL, with %s for
      # the address, or nil for its own scratch SQLite file. Its user,
      # password and database are the workflow's services'.
      Stack = Data.define(:name, :network, :queue, :rows_database) do
        # compose.yml, then the database's file and the queue's
        def compose_files
          [ "compose.yml", *name.split("-", 2).map { |part| "stacks/#{part}.yml" } ]
        end

        def compose_args
          compose_files.flat_map { |file| [ "--file", File.join(LOAD, file) ] }
        end

        # The rows' docker run options, given the addresses of the stack's
        # database and Redis
        def rows_env(database_ip, redis_ip)
          env = { "BENCHMARK_QUEUE" => queue }
          env["BENCHMARK_DATABASE_URL"] = format(rows_database, address("Database", database_ip)) if rows_database
          env["REDIS_URL"] = "redis://#{address("Redis", redis_ip)}:6379/0" if network.key?("Redis")
          env.flat_map { |key, value| [ "--env", "#{key}=#{value}" ] }
        end

        private

        def address(label, ip)
          ip.to_s.empty? ? raise(ArgumentError, "#{name} needs #{label}'s address") : ip
        end
      end

      ALL = [
        Stack.new(name: "postgres-solid-queue", network: { "Database" => [ "db", 5432 ] }, queue: "solid_queue",
          rows_database: "postgres://red:red@%s:5432/red_benchmark?pool=10"),
        Stack.new(name: "postgres-sidekiq", network: { "Database" => [ "db", 5432 ], "Redis" => [ "redis", 6379 ] },
          queue: "sidekiq", rows_database: "postgres://red:red@%s:5432/red_benchmark?pool=10"),
        Stack.new(name: "mysql-solid-queue", network: { "Database" => [ "db", 3306 ] }, queue: "solid_queue",
          rows_database: "trilogy://root:red@%s:3306/red_benchmark?pool=10"),
        Stack.new(name: "sqlite-solid-queue", network: {}, queue: "solid_queue", rows_database: nil)
      ].freeze

      def self.names
        ALL.map(&:name)
      end

      def self.fetch(name)
        ALL.find { |stack| stack.name == name } or raise KeyError, "No stack #{name}: #{names.join(", ")}"
      end
    end
  end
end

# Run as a script, from a workflow's shell
if __FILE__ == $PROGRAM_NAME && File.file?(__FILE__)
  stacks = RedBenchmark::Load::Stacks
  abort stacks::USAGE unless ARGV.size == 4 && ARGV.first == "--rows"
  begin
    _, name, database_ip, redis_ip = ARGV
    puts stacks.fetch(name).rows_env(database_ip, redis_ip)
  rescue KeyError, ArgumentError => error
    abort error.message
  end
end
