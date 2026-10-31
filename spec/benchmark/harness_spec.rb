# frozen_string_literal: true

require "rails_helper"
require "open3"
require "sqlite3"
require "tempfile"
require_relative "../../benchmark/harness"
require_relative "../../benchmark/scenarios"

RSpec.describe "bin/benchmark harness" do
  root = File.expand_path("../..", __dir__)

  # Runs the real script. RUBYOPT keeps the parent's (bundle exec puts
  # bundler/setup there) and adds WebMock with every connection refused, so a
  # network call anywhere in the run fails it.
  define_method(:run_script) do |*arguments, env: {}|
    base = {
      "RUBYOPT" => "#{ENV['RUBYOPT']} -r#{File.join(root, 'spec/benchmark/offline.rb')}".strip,
      "RAILS_ENV" => nil,
      "DATABASE_URL" => nil,
      "PRIMARY_DATABASE_URL" => nil,
      "BENCHMARK_DATABASE_URL" => nil,
      "BENCHMARK_QUEUE" => nil,
      "RUBY_YJIT_ENABLE" => nil
    }
    Open3.capture3(base.merge(env), "ruby", File.join(root, "bin/benchmark"), *arguments, chdir: root)
  end

  define_method(:facts_from) do |output|
    output.lines.filter_map { |line| line.chomp.split(": ", 2) if line.include?(": ") }.to_h
  end

  # One boot of the real script, shared by the examples below: it takes a few
  # seconds.
  before(:all) do
    @output, @errors, @status = run_script("--list")
    @facts = facts_from(@output)
  end

  it "boots without touching the network (overhead-benchmark/REQ-1)" do
    expect(@status).to be_success, "bin/benchmark --list failed:\n#{@errors}"
  end

  it "runs the dummy app like production: eager loading on, reloading off (overhead-benchmark/REQ-5)" do
    expect(@facts["Eager loading"]).to eq("on")
    expect(@facts["Code reloading"]).to eq("off")
  end

  it "uses a scratch database under tmp/, never the suite's (overhead-benchmark/REQ-1)" do
    database = @facts.fetch("Scratch database")

    expect(database).to start_with(File.join(root, "tmp", ""))
    expect(database).not_to end_with("spec/dummy/db/test.sqlite3")
  end

  # A SQLite file stands in for a server: the script reaches both through the
  # same variable, and this needs no database running.
  describe "with BENCHMARK_DATABASE_URL" do
    around do |example|
      Dir.mktmpdir("red_benchmark_database") do |dir|
        @path = File.join(dir, "other_benchmark.sqlite3")
        example.run
      end
    end

    let(:env) { { "BENCHMARK_DATABASE_URL" => "sqlite3:#{@path}" } }
    let(:refusal) { /only runs on one with "benchmark"/ }

    def database_values(sql)
      database = SQLite3::Database.new(@path)
      database.execute(sql).flatten
    ensure
      database&.close
    end

    it "runs against that database (deploy-shape-benchmark/REQ-1)" do
      output, errors, status = run_script("--list", env: env)

      expect(status).to be_success, errors
      expect(facts_from(output)["Scratch database"]).to eq(@path)
      expect(database_values("SELECT name FROM sqlite_master WHERE type = 'table'")).to include("rails_error_dashboard_error_logs")
    end

    it "builds the schema from db/migrate, as a host does, not from schema.rb (deploy-shape-benchmark/REQ-1)" do
      _output, errors, status = run_script("--list", env: env)
      migrations = Dir[File.join(root, "db/migrate/*.rb")].map { |path| File.basename(path)[/\A\d+/] }

      expect(status).to be_success, errors
      expect(database_values("SELECT version FROM schema_migrations")).to match_array(migrations)
    end

    it "starts from an empty database, so an earlier run can't colour this one (deploy-shape-benchmark/REQ-1)" do
      database = SQLite3::Database.new(@path)
      database.execute("CREATE TABLE left_by_an_earlier_run (id INTEGER)")
      database.close

      _output, errors, status = run_script("--list", env: env)

      expect(status).to be_success, errors
      expect(database_values("SELECT name FROM sqlite_master WHERE type = 'table'")).not_to include("left_by_an_earlier_run")
    end

    # A run drops every table, so one mistyped variable could empty a real
    # database. What counts is the database Rails really opens: a URL can name
    # one and open another, and another variable can override it. The file sits
    # in a folder named benchmark, so a folder can't pass for its name.
    describe "when the database isn't named for benchmarking" do
      around do |example|
        Dir.mktmpdir("red_benchmark_refusal") do |dir|
          FileUtils.mkdir_p(File.join(dir, "benchmark"))
          @production = File.join(dir, "benchmark", "production.sqlite3")
          database = SQLite3::Database.new(@production)
          database.execute("CREATE TABLE orders (id INTEGER)")
          database.execute("INSERT INTO orders VALUES (42)")
          database.close
          example.run
        end
      end

      def expect_refused(env)
        before = File.binread(@production)

        output, errors, status = run_script("--list", env: env)

        expect(status).not_to be_success
        expect(errors).to match(refusal)
        expect(output).to be_empty
        expect(File.binread(@production)).to eq(before)
      end

      it "exits with an error and changes nothing (deploy-shape-benchmark/REQ-2)" do
        expect_refused("BENCHMARK_DATABASE_URL" => "sqlite3:#{@production}")
      end

      it "isn't fooled by a query that opens another database (deploy-shape-benchmark/REQ-2)" do
        expect_refused("BENCHMARK_DATABASE_URL" => "sqlite3:#{@path}?database=#{@production}")
      end

      it "isn't fooled by a fragment (deploy-shape-benchmark/REQ-2)" do
        expect_refused("BENCHMARK_DATABASE_URL" => "sqlite3:#{@production}#benchmark")
      end

      # SQLite opens the file, and ignores what follows it, while the name Rails
      # reports still has "benchmark" in it.
      it "isn't fooled by a query inside a SQLite file: URI (deploy-shape-benchmark/REQ-2)" do
        expect_refused("BENCHMARK_DATABASE_URL" => "sqlite3:file:#{@production}%3Fbenchmark=1")
      end

      it "isn't fooled by a fragment inside a SQLite file: URI (deploy-shape-benchmark/REQ-2)" do
        expect_refused("BENCHMARK_DATABASE_URL" => "sqlite3:file:#{@production}%23benchmark")
      end

      it "isn't fooled by a file: URI in a query (deploy-shape-benchmark/REQ-2)" do
        expect_refused("BENCHMARK_DATABASE_URL" => "sqlite3:#{@path}?database=file:#{@production}%3Fbenchmark=1")
      end

      it "isn't fooled by an encoded path (deploy-shape-benchmark/REQ-2)" do
        folder = File.dirname(@production)
        expect_refused("BENCHMARK_DATABASE_URL" => "sqlite3:file:#{folder}/benchmark%252F..%252Fproduction.sqlite3")
      end

      # After a slash, the end of a query or fragment looks like the file's name,
      # while SQLite still opens the file before it.
      it "isn't fooled by a slash after the file in a SQLite file: URI (deploy-shape-benchmark/REQ-2)" do
        [
          "file:#{@production}%3Fx=/benchmark",
          "file:#{@production}%23/benchmark",
          "file:#{@production}%3Fx=/red_benchmark.sqlite3",
          "file:#{@production}%3F/../benchmark",
          "file:#{@production}%3Fcache=shared%26x=/benchmark",
          "file://localhost#{@production}%3Fx=/benchmark",
          "#{@path}?database=file:#{@production}%3Fx=/benchmark"
        ].each { |url| expect_refused("BENCHMARK_DATABASE_URL" => "sqlite3:#{url}") }
      end

      # Rails lets PRIMARY_DATABASE_URL beat DATABASE_URL, so one left in a shell
      # would choose the database, and the harness would empty it.
      it "runs where BENCHMARK_DATABASE_URL says, whatever PRIMARY_DATABASE_URL says (deploy-shape-benchmark/REQ-2)" do
        before = File.binread(@production)

        output, errors, status = run_script("--list", env: { "BENCHMARK_DATABASE_URL" => "sqlite3:#{@path}", "PRIMARY_DATABASE_URL" => "sqlite3:#{@production}" })

        expect(status).to be_success, errors
        expect(facts_from(output)["Scratch database"]).to eq(@path)
        expect(File.binread(@production)).to eq(before)
      end

      it "keeps a default run on its scratch file, whatever PRIMARY_DATABASE_URL says (deploy-shape-benchmark/REQ-2)" do
        before = File.binread(@production)

        output, errors, status = run_script("--list", env: { "PRIMARY_DATABASE_URL" => "sqlite3:#{@production}" })

        expect(status).to be_success, errors
        expect(facts_from(output)["Scratch database"]).to start_with(File.join(root, "tmp", ""))
        expect(File.binread(@production)).to eq(before)
      end
    end

    it "judges a server's database by its own name, not its host (deploy-shape-benchmark/REQ-2)" do
      output, errors, status = run_script("--list", env: { "BENCHMARK_DATABASE_URL" => "postgres://red:s3cret@benchmark.internal/production" })

      expect(status).not_to be_success
      expect(errors).to match(refusal)
      expect(output).to be_empty
    end

    # A server's database has no folders, so the end of the path can't vouch for it.
    it "judges a server's database by its whole name (deploy-shape-benchmark/REQ-2)" do
      output, errors, status = run_script("--list", env: { "BENCHMARK_DATABASE_URL" => "postgres://127.0.0.1:1/production/benchmark" })

      expect(status).not_to be_success
      expect(errors).to match(refusal)
      expect(output).to be_empty
    end

    it "refuses a URL that names no database (deploy-shape-benchmark/REQ-2)" do
      output, errors, status = run_script("--list", env: { "BENCHMARK_DATABASE_URL" => "postgres://red@127.0.0.1" })

      expect(status).not_to be_success
      expect(errors).to match(refusal)
      expect(output).to be_empty
    end

    # The last group has a password with a slash in it, unescaped, so Rails takes
    # the rest of it for the database's name.
    it "never prints a password, even from a URL it can't read (deploy-shape-benchmark/REQ-2)" do
      [
        "postgres://red:s3cret@benchmark.internal/production",
        "postgres://red:s3cret@not a host/red_benchmark",
        "postgres://red:s3cret@my_db/red_benchmark",
        "trilogy://red:s3cret@db_1:3306/red_benchmark",
        "postgres://red:5432/s3cret@127.0.0.1",
        "postgres://red:/s3cret@127.0.0.1",
        "postgres://red:123/x/s3cret#y@127.0.0.1",
        "postgres://127.0.0.1:1/s3cret@x/red_benchmark"
      ].each do |url|
        output, errors, status = run_script("--list", env: { "BENCHMARK_DATABASE_URL" => url })

        expect(status).not_to be_success
        expect(output + errors).not_to include("s3cret")
      end
    end

    it "never prints a password from a PRIMARY_DATABASE_URL left in the shell (deploy-shape-benchmark/REQ-2)" do
      [
        "postgres://red:s3cret@my_db/red_benchmark",
        "postgres://red:s3cret@not a host/red_benchmark"
      ].each do |url|
        output, errors, = run_script("--list", env: { "PRIMARY_DATABASE_URL" => url })

        expect(output + errors).not_to include("s3cret")
      end
    end
  end

  describe "with BENCHMARK_QUEUE" do
    around do |example|
      Dir.mktmpdir("red_benchmark_queue") do |dir|
        @path = File.join(dir, "queue_benchmark.sqlite3")
        example.run
      end
    end

    it "enqueues through Solid Queue, into its real tables (deploy-shape-benchmark/REQ-3)" do
      skip "Solid Queue needs Rails 7.1+" if Gem::Specification.find_all_by_name("solid_queue").empty?

      env = { "BENCHMARK_QUEUE" => "solid_queue", "BENCHMARK_DATABASE_URL" => "sqlite3:#{@path}" }
      output, errors, = run_script("--list", env: env)
      _run_output, run_errors, run_status = run_script("--smoke", env: env)

      expect(facts_from(output)["Job adapter"]).to eq("ActiveJob::QueueAdapters::SolidQueueAdapter"), errors
      expect(run_status.exitstatus).to be_between(0, 1), run_errors
      database = SQLite3::Database.new(@path)
      expect(database.get_first_value("SELECT COUNT(*) FROM solid_queue_jobs")).to be_positive
      database.close
    end

    it "enqueues through Sidekiq (deploy-shape-benchmark/REQ-3)" do
      output, errors, status = run_script("--list", env: { "BENCHMARK_QUEUE" => "sidekiq" })

      expect(status).to be_success, errors
      expect(facts_from(output)["Job adapter"]).to match(/Sidekiq/)
    end

    it "refuses a queue it doesn't know, rather than quietly use the null adapter (deploy-shape-benchmark/REQ-3)" do
      output, errors, status = run_script("--list", env: { "BENCHMARK_QUEUE" => "solidqueue" })

      expect(status).not_to be_success
      expect(errors).to include("solidqueue", "solid_queue", "sidekiq")
      expect(output).to be_empty
    end
  end

  it "enqueues jobs into an adapter that drops them (overhead-benchmark/REQ-1)" do
    expect(@facts["Job adapter"]).to eq("RedBenchmark::NullJobAdapter")
  end

  it "records the environment the numbers came from (overhead-benchmark/REQ-6)" do
    expect(@facts["Ruby"]).to eq(RUBY_VERSION)
    expect(@facts["Rails"]).to eq(Rails.version)
    expect(@facts["Database"]).to eq("sqlite3")
    expect(@facts["CPU"]).to be_present
    expect(Integer(@facts["CPUs"])).to be_positive
    expect(@facts["OS"]).to be_present
    expect(@facts["RED commit"]).to match(/\A\h{7,}\z/)
  end

  it "names the machine's architecture (deploy-shape-benchmark/REQ-5)" do
    expect(@facts["Architecture"]).to eq(Etc.uname[:machine])
  end

  describe "naming the CPU" do
    harness = RedBenchmark::Harness
    # /proc/cpuinfo on an aarch64 runner: numbers, and no `model name`.
    arm_cpuinfo = "processor\t: 0\nBogoMIPS\t: 2000.00\nCPU implementer\t: 0x41\nCPU part\t: 0xd49\n"

    it "uses the model name where the platform gives one (deploy-shape-benchmark/REQ-5)" do
      cpuinfo = "processor\t: 0\nmodel name\t: AMD EPYC 7763 64-Core Processor\n"

      expect(harness.named_cpu(cpuinfo, "")).to eq("AMD EPYC 7763 64-Core Processor")
    end

    it "asks lscpu on ARM Linux, which has no model name (deploy-shape-benchmark/REQ-5)" do
      expect(harness.named_cpu(arm_cpuinfo, "Vendor ID:  ARM\nModel name:  Neoverse-N2\n")).to eq("Neoverse-N2")
    end

    it "falls back to the part number when lscpu can't name it (deploy-shape-benchmark/REQ-5)" do
      expect(harness.named_cpu(arm_cpuinfo, "Vendor ID:  ARM\nModel name:  -\n")).to eq("ARM implementer 0x41, part 0xd49")
      expect(harness.named_cpu(arm_cpuinfo, "")).to eq("ARM implementer 0x41, part 0xd49")
    end

    it "uses sysctl's name where there's no /proc/cpuinfo (deploy-shape-benchmark/REQ-5)" do
      expect(harness.named_cpu("", "", "Apple M3 Max")).to eq("Apple M3 Max")
    end

    it "says unknown rather than leaving the row blank (deploy-shape-benchmark/REQ-5)" do
      expect(harness.named_cpu("", "")).to eq("unknown")
    end
  end

  describe "the limits it runs under" do
    harness = RedBenchmark::Harness

    around do |example|
      Dir.mktmpdir("red_cgroup") do |dir|
        @cgroup = dir
        example.run
      end
    end

    def write_cgroup(name, content)
      path = File.join(@cgroup, name)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end

    describe "in a container, where its own cgroup looks like the root" do
      before { write_cgroup("cgroup.controllers", "cpu memory\n") }

      it "states a CPU quota in CPUs (deploy-shape-benchmark/REQ-6)" do
        write_cgroup("cpu.max", "40000 100000\n")

        expect(harness.cpu_limit(@cgroup, "/")).to eq("0.40 CPU")
      end

      it "says none found when the process has no CPU quota (deploy-shape-benchmark/REQ-6)" do
        write_cgroup("cpu.max", "max 100000\n")

        expect(harness.cpu_limit(@cgroup, "/")).to eq("none found")
      end

      it "states a memory limit in GB (deploy-shape-benchmark/REQ-6)" do
        write_cgroup("memory.max", "4294967296\n")

        expect(harness.memory_limit(@cgroup, "/")).to eq("4.00 GB")
      end

      it "says none found when the process has no memory limit (deploy-shape-benchmark/REQ-6)" do
        write_cgroup("memory.max", "max\n")

        expect(harness.memory_limit(@cgroup, "/")).to eq("none found")
      end
    end

    describe "at the real root, where the kernel has no limit files" do
      before { write_cgroup("cgroup.controllers", "cpu memory\n") }

      it "says none found (deploy-shape-benchmark/REQ-6)" do
        expect(harness.cpu_limit(@cgroup, "/")).to eq("none found")
        expect(harness.memory_limit(@cgroup, "/")).to eq("none found")
      end
    end

    describe "in a child cgroup, as under a systemd service" do
      before do
        write_cgroup("cgroup.controllers", "cpu memory\n")
        write_cgroup("system.slice/red.service/cgroup.controllers", "cpu memory\n")
      end

      let(:own) { "/system.slice/red.service" }

      it "reads the limits on its own cgroup, not the root's (deploy-shape-benchmark/REQ-6)" do
        write_cgroup("system.slice/red.service/cpu.max", "50000 100000\n")
        write_cgroup("system.slice/red.service/memory.max", "1073741824\n")

        expect(harness.cpu_limit(@cgroup, own)).to eq("0.50 CPU")
        expect(harness.memory_limit(@cgroup, own)).to eq("1.00 GB")
      end

      it "takes the tightest limit on the way up to the root (deploy-shape-benchmark/REQ-6)" do
        write_cgroup("system.slice/cpu.max", "20000 100000\n")
        write_cgroup("system.slice/memory.max", "1073741824\n")
        write_cgroup("system.slice/red.service/cpu.max", "max 100000\n")
        write_cgroup("system.slice/red.service/memory.max", "2147483648\n")

        expect(harness.cpu_limit(@cgroup, own)).to eq("0.20 CPU")
        expect(harness.memory_limit(@cgroup, own)).to eq("1.00 GB")
      end

      it "says none found when nothing on the way up limits it (deploy-shape-benchmark/REQ-6)" do
        write_cgroup("system.slice/red.service/cpu.max", "max 100000\n")
        write_cgroup("system.slice/red.service/memory.max", "max\n")

        expect(harness.cpu_limit(@cgroup, own)).to eq("none found")
        expect(harness.memory_limit(@cgroup, own)).to eq("none found")
      end

      it "says not available, not none found, when its cgroup is outside what it can see (deploy-shape-benchmark/REQ-6)" do
        expect(harness.cpu_limit(@cgroup, "/../elsewhere")).to eq("not available")
        expect(harness.memory_limit(@cgroup, "/../elsewhere")).to eq("not available")
      end

      it "says not available when this mount doesn't hold its cgroup (deploy-shape-benchmark/REQ-6)" do
        expect(harness.cpu_limit(@cgroup, "/other.slice/red.service")).to eq("not available")
        expect(harness.memory_limit(@cgroup, "/other.slice/red.service")).to eq("not available")
      end

      # The host's tree, bind-mounted into a container with its own namespace: the
      # process says "/", which on this mount is the host's root, not its cgroup.
      it "says not available when the mount isn't rooted where the process is (deploy-shape-benchmark/REQ-6)" do
        allow(harness).to receive(:cgroup_mount_root).and_return("/../..")

        expect(harness.cpu_limit(@cgroup, "/")).to eq("not available")
        expect(harness.memory_limit(@cgroup, "/")).to eq("not available")
      end
    end

    it "reads its own cgroup from the kernel's cgroup v2 line (deploy-shape-benchmark/REQ-6)" do
      expect(harness.own_cgroup("0::/system.slice/red.service\n")).to eq("/system.slice/red.service")
      expect(harness.own_cgroup("0::/\n")).to eq("/")
      expect(harness.own_cgroup("")).to eq("/")
    end

    it "keeps a cgroup name with a space or a tab whole (deploy-shape-benchmark/REQ-6)" do
      expect(harness.own_cgroup("0::/lab/a job/b\tc\n")).to eq("/lab/a job/b\tc")
    end

    it "reads the root of the cgroup mount from mountinfo (deploy-shape-benchmark/REQ-6)" do
      bound = <<~MOUNTS
        30 25 0:26 / /proc rw,nosuid - proc proc rw
        31 25 0:27 /../.. /sys/fs/cgroup ro,nosuid master:9 - cgroup2 cgroup2 rw
      MOUNTS

      expect(harness.cgroup_mount_root(bound)).to eq("/../..")
      expect(harness.cgroup_mount_root("31 25 0:27 / /sys/fs/cgroup ro - cgroup2 cgroup rw\n")).to eq("/")
      expect(harness.cgroup_mount_root("")).to eq("/")
    end

    it "says not available where the platform has no cgroup files (deploy-shape-benchmark/REQ-6)" do
      expect(harness.cpu_limit(@cgroup, "/")).to eq("not available")
      expect(harness.memory_limit(@cgroup, "/")).to eq("not available")
    end

    it "reports both with the environment (deploy-shape-benchmark/REQ-6)" do
      expect(@facts).to include("CPU limit", "Memory limit")
    end
  end

  describe "CPU time stolen during a run" do
    harness = RedBenchmark::Harness

    # /proc/stat's first line: user nice system idle iowait irq softirq steal
    # guest guest_nice. Guest time is already counted in user.
    define_method(:ticks) do |busy, idle, steal|
      harness.cpu_ticks("cpu  #{busy} 0 0 #{idle} 0 0 0 #{steal} 500 500\ncpu0 1 2 3 4 5 6 7 8 9 10\n")
    end

    it "gives the share of the CPU time between two readings (deploy-shape-benchmark/REQ-7)" do
      expect(harness.stolen_share(ticks(100, 100, 0), ticks(190, 190, 20))).to eq("10.00%")
    end

    it "says 0.00%, not a failure, when nothing was stolen (deploy-shape-benchmark/REQ-7)" do
      expect(harness.stolen_share(ticks(100, 100, 5), ticks(200, 200, 5))).to eq("0.00%")
    end

    it "copes with two readings of the same instant (deploy-shape-benchmark/REQ-7)" do
      expect(harness.stolen_share(ticks(100, 100, 5), ticks(100, 100, 5))).to eq("0.00%")
    end

    it "says not available where there's no /proc/stat, rather than a false 0 (deploy-shape-benchmark/REQ-7)" do
      expect(harness.cpu_ticks("")).to be_nil
      expect(harness.stolen_share(nil, nil)).to eq("not available")
    end
  end

  it "runs with YJIT on wherever this Ruby can turn it on, and records it (overhead-benchmark/REQ-6)" do
    expect(@facts["YJIT"]).to eq(defined?(RubyVM::YJIT.enable) ? "on" : "not available")
  end

  # The whole script, every scenario, once. In a few iterations a gated row can
  # go either way, so these examples hold the script to its own table rather
  # than to the budgets.
  describe "a run with --summary" do
    before(:all) do
      @summary = Tempfile.new("red_benchmark_summary")
      @summary.write("From an earlier step\n")
      @summary.close
      @run_output, @run_errors, @run_status = run_script("--smoke", "--summary", @summary.path)
      @written = File.read(@summary.path)
    end

    after(:all) { @summary.unlink }

    it "runs every scenario without touching the network (overhead-benchmark/REQ-1)" do
      expect(@run_status.exitstatus).to be_between(0, 1), "bin/benchmark failed:\n#{@run_errors}"
      expect(@run_output).to include(*RedBenchmark::Scenarios.all.map(&:name))
    end

    it "appends the table to the summary file, after what is already there (overhead-benchmark/REQ-9)" do
      expect(@written).to start_with("From an earlier step\n")
      expect(@written).to include("| Measurement | Median | p95 | Budget | Result |")
      expect(@written).to include(*RedBenchmark::Scenarios.all.map(&:name))
    end

    it "exits non-zero exactly when its table shows a FAIL (overhead-benchmark/REQ-7)" do
      expect(@run_status.exitstatus).to eq(@run_output.include?("| FAIL |") ? 1 : 0)
    end

    it "reports the CPU time stolen during the run (deploy-shape-benchmark/REQ-7)" do
      expect(@written).to match(/^\| CPU time stolen \| (\d+\.\d\d%|not available) \|$/)
    end

    it "says a smoke run's numbers mean nothing (overhead-benchmark/REQ-9)" do
      expect(@written).to include("Smoke run")
    end
  end

  describe RedBenchmark::NullJobAdapter do
    it "serialises each job, as a real backend does, and never runs it (overhead-benchmark/REQ-1)" do
      job = RailsErrorDashboard::AsyncErrorLoggingJob.new({ "class_name" => "RuntimeError" }, {})
      allow(job).to receive(:serialize).and_call_original
      expect(job).not_to receive(:perform_now)

      described_class.new.enqueue(job)
      described_class.new.enqueue_at(job, Time.now.to_f + 60)

      expect(job).to have_received(:serialize).twice
    end
  end
end
