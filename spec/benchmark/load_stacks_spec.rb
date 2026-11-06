# frozen_string_literal: true

require "rails_helper"
require "open3"
require "yaml"
require_relative "../../benchmark/load/stacks"

# The stacks, benchmark/load/stacks.rb: the database and queue the load test's
# app and the rows run on, beside the shape they're held to.
RSpec.describe RedBenchmark::Load::Stacks do
  let(:script) { File.join(__dir__, "../../benchmark/load/stacks.rb") }

  def stack(name)
    described_class.fetch(name)
  end

  it "has the default stack and three variants, and Ruby 3.4 or 4.0 (deploy-shape-benchmark/REQ-16)" do
    expect(described_class.names).to eq(%w[postgres-solid-queue postgres-sidekiq mysql-solid-queue sqlite-solid-queue])
    expect(described_class::DEFAULT).to eq("postgres-solid-queue")
    expect(described_class::RUBIES).to eq(%w[3.4 4.0])
    expect(described_class::DEFAULT_RUBY).to eq("3.4")
  end

  it "refuses a stack it doesn't have, and names the ones it does (deploy-shape-benchmark/REQ-16)" do
    expect { stack("oracle-resque") }.to raise_error(KeyError,
      "No stack oracle-resque: postgres-solid-queue, postgres-sidekiq, mysql-solid-queue, sqlite-solid-queue")
  end

  it "lays a compose file for its database and one for its queue over compose.yml (deploy-shape-benchmark/REQ-16)" do
    load_folder = File.expand_path("../../benchmark/load", __dir__)

    expect(described_class::ALL.to_h { |each| [ each.name, each.compose_files ] }).to eq(
      "postgres-solid-queue" => %w[compose.yml stacks/postgres.yml stacks/solid-queue.yml],
      "postgres-sidekiq" => %w[compose.yml stacks/postgres.yml stacks/sidekiq.yml],
      "mysql-solid-queue" => %w[compose.yml stacks/mysql.yml stacks/solid-queue.yml],
      "sqlite-solid-queue" => %w[compose.yml stacks/sqlite.yml stacks/solid-queue.yml]
    ).and(satisfy { |files| files.values.flatten.uniq.all? { |file| File.file?(File.join(load_folder, file)) } })
    expect(stack("mysql-solid-queue").compose_args).to eq([
      "--file", File.join(load_folder, "compose.yml"), "--file", File.join(load_folder, "stacks/mysql.yml"),
      "--file", File.join(load_folder, "stacks/solid-queue.yml")
    ])
  end

  it "puts a network database, and Redis, across the network, and SQLite nowhere (deploy-shape-benchmark/REQ-17)" do
    expect(described_class::ALL.to_h { |each| [ each.name, each.network ] }).to eq(
      "postgres-solid-queue" => { "Database" => [ "db", 5432 ] },
      "postgres-sidekiq" => { "Database" => [ "db", 5432 ], "Redis" => [ "redis", 6379 ] },
      "mysql-solid-queue" => { "Database" => [ "db", 3306 ] },
      "sqlite-solid-queue" => {}
    )
  end

  describe "the rows" do
    it "run on the stack's database and queue, at the addresses given (deploy-shape-benchmark/REQ-16)" do
      expect(described_class::ALL.to_h { |each| [ each.name, each.rows_env("10.0.0.2", "10.0.0.3") ] }).to eq(
        "postgres-solid-queue" => [ "--env", "BENCHMARK_QUEUE=solid_queue",
          "--env", "BENCHMARK_DATABASE_URL=postgres://red:red@10.0.0.2:5432/red_benchmark?pool=10" ],
        "postgres-sidekiq" => [ "--env", "BENCHMARK_QUEUE=sidekiq",
          "--env", "BENCHMARK_DATABASE_URL=postgres://red:red@10.0.0.2:5432/red_benchmark?pool=10",
          "--env", "REDIS_URL=redis://10.0.0.3:6379/0" ],
        "mysql-solid-queue" => [ "--env", "BENCHMARK_QUEUE=solid_queue",
          "--env", "BENCHMARK_DATABASE_URL=trilogy://root:red@10.0.0.2:3306/red_benchmark?pool=10" ],
        # bin/benchmark's own scratch SQLite file, in the container
        "sqlite-solid-queue" => [ "--env", "BENCHMARK_QUEUE=solid_queue" ]
      )
    end

    it "are told the stack from a workflow's shell, one docker run option to a line (deploy-shape-benchmark/REQ-16)" do
      output, status = Open3.capture2e(RbConfig.ruby, script, "--rows", "postgres-sidekiq", "10.0.0.2", "10.0.0.3")

      expect(status).to be_success
      expect(output.lines(chomp: true)).to eq(stack("postgres-sidekiq").rows_env("10.0.0.2", "10.0.0.3"))

      # A stack with nothing across the network is given empty addresses
      output, status = Open3.capture2e(RbConfig.ruby, script, "--rows", "sqlite-solid-queue", "", "")
      expect(status).to be_success
      expect(output.lines(chomp: true)).to eq([ "--env", "BENCHMARK_QUEUE=solid_queue" ])
    end

    it "refuse a stack it doesn't have, a missing address, and a wrong call (deploy-shape-benchmark/REQ-16)" do
      [
        [ [ "--rows", "oracle-resque", "", "" ], "No stack oracle-resque" ],
        [ [ "--rows", "postgres-sidekiq", "10.0.0.2", "" ], "postgres-sidekiq needs Redis's address" ],
        [ [ "--rows", "mysql-solid-queue", "", "" ], "mysql-solid-queue needs Database's address" ],
        [ [ "--rows", "postgres-solid-queue" ], described_class::USAGE ],
        [ [ "postgres-solid-queue" ], described_class::USAGE ]
      ].each do |arguments, message|
        output, status = Open3.capture2e(RbConfig.ruby, script, *arguments)

        expect(status).not_to be_success, arguments.inspect
        expect(output).to include(message), arguments.inspect
      end
    end
  end
end
