# frozen_string_literal: true

require "rails_helper"
require "json"
require "open3"
require "yaml"

# The app's Puma, database and job settings are the generator's, so they aren't
# in this repo to read. These examples hold the things that could move them: the
# Rails version that writes them, and anything of ours that might override them.
# Booting the app shows the values themselves.
RSpec.describe "the load test's app" do
  load_folder = File.expand_path("../../benchmark/load", __dir__)

  let(:dockerfile) { File.read(File.join(load_folder, "Dockerfile")) }
  let(:template) { File.read(File.join(load_folder, "app/template.rb")) }
  let(:compose) { YAML.load_file(File.join(load_folder, "compose.yml")) }
  let(:app_settings) { compose.dig("services", "app", "environment") }
  let(:our_files) { [ dockerfile, template, compose.to_yaml ] }

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
    expect(dockerfile).to include("rails new . --name=shop --database=postgresql --template=/template.rb\n")
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
    expect(template).not_to include("queue_adapter", "config/queue.yml")
    expect(app_settings).to include("SOLID_QUEUE_IN_PUMA" => "true")
  end

  it "leaves the database settings as generated (deploy-shape-benchmark/REQ-8)" do
    expect(template).not_to include("config/database.yml")
    expect(app_settings.keys.grep(/DATABASE_URL/)).to be_empty
  end

  it "fails a request 60 frames down, as bin/benchmark does (deploy-shape-benchmark/REQ-8)" do
    expect(template).to match(/FRAMES = 60$/)
  end

  # Booting the image shows what reading the files can't: what Puma runs, and
  # what RED does with RED on and off. It needs Docker and a few minutes, so it
  # runs only when asked:
  #
  #   LOAD_APP_BOOT=1 bundle exec rspec spec/benchmark/load_app_spec.rb
  describe "booted in compose", if: ENV["LOAD_APP_BOOT"] == "1" do
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
    after(:all) { system(*compose, "down", "--volumes", out: File::NULL, err: File::NULL) }

    it "runs Puma in production, one process with 3 threads, with jemalloc and Solid Queue inside it (deploy-shape-benchmark/REQ-8)" do
      expect(run!(*compose, "logs", "app")).to include(
        "Puma starting in single mode", "Min threads: 3", "Max threads: 3", "Environment: production"
      )

      processes = run!(*compose, "exec", "-T", "app", "sh", "-c",
        'for p in /proc/[0-9]*; do printf "%s|%s\n" "$(tr "\0" " " < $p/cmdline)" "$(grep -c jemalloc $p/maps)"; done')
      puma = processes.lines.find { |line| line.start_with?("puma ") }
      expect(puma.to_s.split("|").last.to_i).to be_positive # jemalloc is mapped into Puma
      expect(processes).to include("solid-queue-fork-supervisor")
    end

    it "records a failing request in RED's table, through Solid Queue (deploy-shape-benchmark/REQ-8)" do
      expect(loaded_in("app", loaded_check)).to include("routes" => 1, "middleware" => 1, "subscribers" => 1)
      rows = red_rows
      jobs = red_jobs

      expect(status_of("app", "/orders/42")).to eq("200")
      expect(status_of("app", "/orders/42/charge")).to eq("500")
      wait_for(30) { red_rows == rows + 1 }
      expect(red_jobs).to eq(jobs + 1)
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
      sleep 5
      expect([ red_rows, red_jobs ]).to eq([ rows, jobs ])
    ensure
      system("docker", "rm", "--force", off, out: File::NULL, err: File::NULL)
    end

    def compose
      [ "docker", "compose", "--file", File.expand_path("../../benchmark/load/compose.yml", __dir__) ]
    end

    def run!(*command, stdin: "")
      output, status = Open3.capture2e(*command, stdin_data: stdin)
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

    def sql(database, query)
      run!(*compose, "exec", "-T", "db", "psql", "--username", "shop", "--dbname", database,
        "--tuples-only", "--no-align", "--command", query).strip
    end

    def red_rows
      sql("shop_production", "select count(*) from rails_error_dashboard_error_logs").to_i
    end

    def red_jobs
      sql("shop_production_queue", "select count(*) from solid_queue_jobs where class_name like 'RailsErrorDashboard%'").to_i
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
