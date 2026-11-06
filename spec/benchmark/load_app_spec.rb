# frozen_string_literal: true

require "rails_helper"
require "json"
require "open3"
require "yaml"
require_relative "compose_files"

# The app's Puma, database and job settings are the generator's, so they aren't
# in this repo to read. These examples hold the things that could move them: the
# Rails version that writes them, and anything of ours that might override them.
# Booting the app shows the values themselves.
RSpec.describe "the load test's app" do
  load_folder = File.expand_path("../../benchmark/load", __dir__)
  stacks = RedBenchmark::Load::Stacks

  let(:dockerfile) { File.read(File.join(load_folder, "Dockerfile")) }
  let(:template) { File.read(File.join(load_folder, "app/template.rb")) }
  # The default stack, as compose makes it of its files
  let(:compose) { ComposeFiles.merged(stacks.fetch(stacks::DEFAULT)) }
  let(:app_settings) { compose.dig("services", "app", "environment") }
  let(:stack_files) { Dir[File.join(load_folder, "compose.yml"), File.join(load_folder, "stacks/*.yml")].map { |file| File.read(file) } }
  let(:our_files) { [ dockerfile, template, *stack_files ] }

  def merged(name)
    ComposeFiles.merged(RedBenchmark::Load::Stacks.fetch(name))
  end

  it "runs in production mode (deploy-shape-benchmark/REQ-8)" do
    expect(dockerfile).to match(/^ENV RAILS_ENV="production"/)
    expect(app_settings).not_to have_key("RAILS_ENV")
  end

  it "serves through Puma, behind the proxy the generator puts in front of it (deploy-shape-benchmark/REQ-8)" do
    expect(dockerfile).to include('CMD ["./bin/thrust", "./bin/rails", "server"]')
    expect(template).not_to include("config/puma.rb")
  end

  it "loads jemalloc as the generator's Dockerfile does (deploy-shape-benchmark/REQ-8)" do
    expect(dockerfile).to include("libjemalloc2", 'LD_PRELOAD="/usr/local/lib/libjemalloc.so"')
  end

  it "leaves Puma on one process and 3 threads (deploy-shape-benchmark/REQ-8)" do
    expect(dockerfile).to match(/^ARG RAILS_VERSION=8\.1\.4$/)
    our_files.each { |file| expect(file).not_to include("WEB_CONCURRENCY", "RAILS_MAX_THREADS") }
  end

  it "takes everything from the generator but the database (deploy-shape-benchmark/REQ-8)" do
    # Out of the generator's environment: Solid Cache's installer reads a
    # DATABASE variable as its database's name, and wrote "database: postgresql"
    expect(dockerfile).to include(%(RUN env -u DATABASE rails new . --name=shop --database="$DATABASE" --template=/template.rb\n))
    expect(dockerfile).to match(/^ARG DATABASE=postgresql$/)
  end

  it "adds RED with its installer, not by hand (deploy-shape-benchmark/REQ-8)" do
    expect(template).to include('generate "rails_error_dashboard:install", "--no-interactive"')
    expect(template).not_to include("RailsErrorDashboard.configure")
    # The one thing it writes into an initializer is RED off's switch.
    expect(template.lines.grep(%r{config/initializers})).to all(include(%(return if ENV["RED"] == "off")))
  end

  it "leaves RED out when RED=off: not required, and its initializer and mount skipped (deploy-shape-benchmark/REQ-8)" do
    expect(template.lines.grep(/gem "rails_error_dashboard"/)).to contain_exactly(include(%(require: ENV["RED"] != "off")))
    expect(template.lines.grep(%r{config/initializers/rails_error_dashboard\.rb})).to contain_exactly(include(%(return if ENV["RED"] == "off")))
    expect(template.lines.grep(%r{config/routes\.rb})).to contain_exactly(include(%(unless ENV["RED"] == "off")))
  end

  it "leaves the job queue on the generator's Solid Queue, inside Puma as its deploy file does (deploy-shape-benchmark/REQ-8)" do
    expect(template).not_to include("config/queue.yml")
    # The one change to the queue is Sidekiq's stack's
    expect(template.lines.grep(/queue_adapter/)).to all(end_with(" if sidekiq\n"))
    expect(app_settings).to include("SOLID_QUEUE_IN_PUMA" => "true")
  end

  it "leaves the database settings as generated (deploy-shape-benchmark/REQ-8)" do
    expect(template).not_to include("config/database.yml")
    expect(app_settings.keys.grep(/DATABASE_URL/)).to be_empty
  end

  it "fails a request 60 frames down, as bin/benchmark does (deploy-shape-benchmark/REQ-8)" do
    expect(template).to match(/FRAMES = 60$/)
  end

  describe "on each stack" do
    it "is built on the Ruby asked for, 3.4 unless told (deploy-shape-benchmark/REQ-16)" do
      expect(dockerfile).to match(/^ARG RUBY_VERSION=3\.4$/)
      expect(dockerfile.scan(/^FROM .*$/).grep(/ruby:/)).to all(include("ruby:$RUBY_VERSION-slim")).and(have_attributes(size: 2))
      expect(compose.dig("services", "app", "build", "args")).to include("RUBY_VERSION" => "${APP_RUBY:-3.4}")
    end

    # The packages are the ones Rails 8.1's generator puts in its own Dockerfile
    # for each database: one the app runs with, and one its gems build against.
    it "is made for the stack's database, with the packages the generator installs for it (deploy-shape-benchmark/REQ-16)" do
      args = stacks.names.to_h { |name| [ name, merged(name).dig("services", "app", "build", "args").except("RUBY_VERSION") ] }

      expect(args).to eq(
        "postgres-solid-queue" => { "DATABASE" => "postgresql", "DATABASE_PACKAGE" => "postgresql-client", "DATABASE_BUILD_PACKAGE" => "libpq-dev" },
        "postgres-sidekiq" => { "DATABASE" => "postgresql", "DATABASE_PACKAGE" => "postgresql-client", "DATABASE_BUILD_PACKAGE" => "libpq-dev",
          "QUEUE" => "sidekiq" },
        "mysql-solid-queue" => { "DATABASE" => "mysql", "DATABASE_PACKAGE" => "default-mysql-client",
          "DATABASE_BUILD_PACKAGE" => "default-libmysqlclient-dev" },
        "sqlite-solid-queue" => { "DATABASE" => "sqlite3", "DATABASE_PACKAGE" => "sqlite3", "DATABASE_BUILD_PACKAGE" => "" }
      )
      installs = dockerfile.scan(/apt-get install [^&]+/)
      expect(installs.size).to eq(3)
      expect(installs.grep(/build-essential/)).to all(include("$DATABASE_BUILD_PACKAGE")).and(have_attributes(size: 2))
      expect(installs.grep(/libjemalloc2/)).to contain_exactly(include("$DATABASE_PACKAGE "))
      # Named only by the stack, never in an install line
      expect(installs.join).not_to include("libpq-dev", "postgresql-client")
    end

    it "reaches a network database in its own container, off the app's CPUs, and keeps SQLite in a volume (deploy-shape-benchmark/REQ-16)" do
      databases = stacks.names.to_h do |name|
        services = merged(name).fetch("services")
        [ name, services["db"]&.slice("image", "cpuset") ]
      end

      expect(databases).to eq(
        "postgres-solid-queue" => { "image" => "postgres:16", "cpuset" => "${REST_CPUSET:-}" },
        "postgres-sidekiq" => { "image" => "postgres:16", "cpuset" => "${REST_CPUSET:-}" },
        "mysql-solid-queue" => { "image" => "mysql:8.4", "cpuset" => "${REST_CPUSET:-}" },
        "sqlite-solid-queue" => nil
      )
      # Where the generated database settings look for the host and password
      expect(merged("postgres-sidekiq").dig("services", "app", "environment")).to include("PGHOST" => "db", "SHOP_DATABASE_PASSWORD" => "benchmark")
      expect(merged("mysql-solid-queue").dig("services", "app", "environment")).to include("DB_HOST" => "db", "SHOP_DATABASE_PASSWORD" => "benchmark")
      expect(merged("mysql-solid-queue").dig("services", "app", "depends_on")).to eq("db" => { "condition" => "service_healthy" })
      # MySQL's own user can make the four databases the generator's production settings name
      expect(merged("mysql-solid-queue").dig("configs", "shop-databases", "content"))
        .to eq("GRANT ALL ON `shop\\_production%`.* TO 'shop'@'%';\n")
      # SQLite's files outlive each restart of the app, as its database server would
      sqlite = merged("sqlite-solid-queue")
      expect(sqlite.dig("services", "app", "volumes")).to eq([ "storage:/rails/storage" ])
      expect(sqlite.dig("services", "app")).not_to have_key("depends_on")
      expect(sqlite.fetch("volumes")).to have_key("storage")
    end

    it "runs Solid Queue inside Puma, or Sidekiq beside Puma in the app's container and its limits (deploy-shape-benchmark/REQ-16)" do
      stacks.names.grep(/-solid-queue\z/).each do |name|
        app = merged(name).dig("services", "app")
        expect(app.fetch("environment")).to include("SOLID_QUEUE_IN_PUMA" => "true"), name
        expect(app).not_to have_key("command"), name
      end

      sidekiq = merged("postgres-sidekiq")
      app = sidekiq.dig("services", "app")
      expect(app.fetch("environment")).not_to have_key("SOLID_QUEUE_IN_PUMA")
      expect(app.fetch("environment")).to include("REDIS_URL" => "redis://redis:6379/0")
      # The generator's command last, as its entrypoint prepares the database
      # only for that, and Sidekiq stopped with Puma, by the init process
      expect(app.fetch("command")).to eq([ "sh", "-c", 'bundle exec sidekiq & exec "$$@"', "sh", "./bin/thrust", "./bin/rails", "server" ])
      expect(app).to include("init" => true)
      expect(app.fetch("environment")).to include("TINI_KILL_PROCESS_GROUP" => "1")
      expect(sidekiq.dig("services", "redis")).to include("image" => "redis:7", "cpuset" => "${REST_CPUSET:-}")
      expect(app.fetch("depends_on")).to include("redis" => { "condition" => "service_healthy" })
    end

    it "adds Sidekiq and hands it Active Job only on Sidekiq's stack (deploy-shape-benchmark/REQ-16)" do
      expect(dockerfile).to match(/^ARG QUEUE=solid_queue$/)
      expect(template).to include(%(sidekiq = ENV["QUEUE"] == "sidekiq"\n), %(gem "sidekiq" if sidekiq\n),
        %(gsub_file! "config/environments/production.rb", "queue_adapter = :solid_queue", "queue_adapter = :sidekiq" if sidekiq\n))
    end
  end

  # Booting the image shows what reading the files can't: what Puma runs, and
  # what RED does with RED on and off. It needs Docker and a few minutes, so it
  # runs only when asked, on the default stack and Ruby unless told another:
  #
  #   LOAD_APP_BOOT=1 bundle exec rspec spec/benchmark/load_app_spec.rb
  #   LOAD_APP_BOOT=1 LOAD_APP_STACK=mysql-solid-queue LOAD_APP_RUBY=4.0 bundle exec rspec spec/benchmark/load_app_spec.rb
  describe "booted in compose", if: ENV["LOAD_APP_BOOT"] == "1" do
    stack = stacks.fetch(ENV.fetch("LOAD_APP_STACK", stacks::DEFAULT))
    ruby = ENV.fetch("LOAD_APP_RUBY", stacks::DEFAULT_RUBY)
    database = stack.name[/\A[^-]+/]
    sidekiq = stack.name.end_with?("-sidekiq")

    # Prints, as JSON, how much of RED the process has loaded. It reads names
    # through Module#name itself, because a class can define its own `name`.
    loaded_check = <<~'RUBY'
      real_name = Module.instance_method(:name)
      names = ObjectSpace.each_object(Module).filter_map { |mod| real_name.bind_call(mod) }
      puts JSON.generate(
        modules: names.grep(/\ARailsErrorDashboard(::|\z)/).sort,
        files: $LOADED_FEATURES.grep(%r{\A/red/}),
        routes: Rails.application.routes.routes.count { |route| route.path.spec.to_s.start_with?("/red") },
        middleware: Rails.application.middleware.map(&:inspect).grep(/RailsErrorDashboard/).size,
        subscribers: Rails.error.instance_variable_get(:@subscribers).map { |s| s.class.name }.grep(/RailsErrorDashboard/).size
      )
    RUBY

    before(:all) { run!(*compose, "up", "--build", "--wait", "--wait-timeout", "300") }
    after(:all) { system(compose_env, *compose, "down", "--volumes", out: File::NULL, err: File::NULL) }

    it "runs Puma in production, one process with 3 threads, with jemalloc and the stack's queue (deploy-shape-benchmark/REQ-8, REQ-16)" do
      expect(run!(*compose, "logs", "app")).to include(
        "Puma starting in single mode", "Min threads: 3", "Max threads: 3", "Environment: production"
      )

      processes = run!(*compose, "exec", "-T", "app", "sh", "-c",
        'for p in /proc/[0-9]*; do printf "%s|%s\n" "$(tr "\0" " " < $p/cmdline)" "$(grep -c jemalloc $p/maps)"; done')
      puma = processes.lines.find { |line| line.start_with?("puma ") }
      expect(puma.to_s.split("|").last.to_i).to be_positive # jemalloc is mapped into Puma
      if sidekiq
        expect(processes.lines.grep(/\Asidekiq /).size).to eq(1)
        expect(processes).not_to include("solid-queue-fork-supervisor")
      else
        expect(processes).to include("solid-queue-fork-supervisor")
      end
    end

    it "runs on the Ruby and database the stack asks for (deploy-shape-benchmark/REQ-16)" do
      expect(run!(*compose, "exec", "-T", "app", "ruby", "-e", "print RUBY_VERSION")).to start_with("#{ruby}.")
      adapter = run!(*compose, "exec", "-T", "app", "bin/rails", "runner", "print ActiveRecord::Base.connection_db_config.adapter")
      expect(adapter.lines.last).to eq({ "postgres" => "postgresql", "mysql" => "mysql2", "sqlite" => "sqlite3" }.fetch(database))
    end

    it "records a failing request in RED's table, through the stack's queue (deploy-shape-benchmark/REQ-8, REQ-16)" do
      expect(loaded_in("app", loaded_check)).to include("routes" => 1, "middleware" => 1, "subscribers" => 1)
      rows = red_rows
      jobs = red_jobs

      expect(status_of("app", "/orders/42")).to eq("200")
      expect(status_of("app", "/orders/42/charge")).to eq("500")
      wait_for(30) { red_rows == rows + 1 }
      # Sidekiq counts what it ran every few seconds, not as it runs it
      wait_for(30) { red_jobs == jobs + 1 }
    end

    it "loads no RED class and records nothing with RED=off (deploy-shape-benchmark/REQ-8)" do
      off = "red-load-off-#{Process.pid}"
      run!(*compose, "run", "--detach", "--name", off, "--env", "RED=off", "app")
      wait_for(120) do
        system("docker", "exec", off, "curl", "--fail", "--silent", "--output", "/dev/null", "http://localhost/up",
          out: File::NULL, err: File::NULL)
      end

      # Bundler reads a path gem's gemspec at boot, and RED's requires
      # version.rb, so the namespace and its VERSION are all that may load.
      expect(loaded_in(off, loaded_check)).to eq(
        "modules" => [ "RailsErrorDashboard" ], "files" => [ "/red/lib/rails_error_dashboard/version.rb" ],
        "routes" => 0, "middleware" => 0, "subscribers" => 0
      )

      rows = red_rows
      jobs = red_jobs
      expect(status_of(off, "/red")).to eq("404")
      expect(status_of(off, "/orders/42/charge")).to eq("500")
      sleep(sidekiq ? 15 : 5)
      expect([ red_rows, red_jobs ]).to eq([ rows, jobs ])
    ensure
      system("docker", "rm", "--force", off, out: File::NULL, err: File::NULL)
    end

    define_method(:compose) { [ "docker", "compose", *stack.compose_args ] }
    define_method(:compose_env) { { "APP_RUBY" => ruby } }
    define_method(:database) { database }
    define_method(:sidekiq?) { sidekiq }

    def run!(*command, stdin: "")
      output, status = Open3.capture2e(compose_env, *command, stdin_data: stdin)
      raise "#{command.join(" ")} failed:\n#{output}" unless status.success?

      output
    end

    # The app container for the compose service, or a container by name
    def container_for(name)
      name == "app" ? run!(*compose, "ps", "--quiet", "app").strip : name
    end

    def status_of(container, path)
      run!("docker", "exec", container_for(container), "curl", "--silent", "--output", "/dev/null",
        "--write-out", "%{http_code}", "http://localhost#{path}")
    end

    def loaded_in(container, check)
      output = run!("docker", "exec", "--interactive", container_for(container), "bin/rails", "runner", "-", stdin: check)
      JSON.parse(output.lines.reverse.find { |line| line.start_with?("{") })
    end

    # A count from one of the app's databases, in that database's own client:
    # "" for the primary, or "_queue" for Solid Queue's
    def count(suffix, query)
      command = case database
      when "postgres"
        [ "db", "psql", "--username", "shop", "--dbname", "shop_production#{suffix}", "--tuples-only", "--no-align", "--command", query ]
      when "mysql"
        [ "db", "mysql", "--user", "shop", "--password=benchmark", "--skip-column-names", "--database", "shop_production#{suffix}", "--execute", query ]
      else
        [ "app", "sqlite3", "storage/production#{suffix}.sqlite3", query ]
      end
      run!(*compose, "exec", "-T", *command).lines.last.to_i
    end

    def red_rows
      count("", "select count(*) from rails_error_dashboard_error_logs")
    end

    # The jobs RED queued, as Solid Queue keeps them, or as Sidekiq counts the
    # jobs it ran, all of them RED's here
    def red_jobs
      return run!(*compose, "exec", "-T", "redis", "redis-cli", "get", "stat:processed").to_i if sidekiq?

      count("_queue", "select count(*) from solid_queue_jobs where class_name like 'RailsErrorDashboard%'")
    end

    def wait_for(seconds)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
      until yield
        raise "still waiting after #{seconds} s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        sleep 0.5
      end
    end
  end
end
