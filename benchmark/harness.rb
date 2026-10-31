# frozen_string_literal: true

require "etc"
require "fileutils"

module RedBenchmark
  ROOT = File.expand_path("..", __dir__)

  # The Active Job adapter the benchmark runs with. It serialises each job, as
  # every real backend does before it stores one, and then drops it: what the
  # benchmark measures is RED's cost on the request thread, not a queue's.
  class NullJobAdapter < (defined?(ActiveJob::QueueAdapters::AbstractAdapter) ? ActiveJob::QueueAdapters::AbstractAdapter : Object)
    def enqueue(job)
      job.serialize
      nil
    end

    def enqueue_at(job, _timestamp)
      enqueue(job)
    end

    # Rails 7.2+ asks the adapter whether to wait for the surrounding
    # transaction; there is nothing to wait for.
    def enqueue_after_transaction_commit?
      false
    end
  end

  # Boots spec/dummy the way a host app runs in production: classes eager
  # loaded, no code reloading, warnings-only logging, YJIT on. It reads RED's settings
  # from benchmark/initializers/ (the installer's defaults), not from the
  # dummy app's test initializer, and it writes to its own SQLite file under
  # tmp/, so it never touches spec/dummy/db/test.sqlite3 and can't collide
  # with an rspec run.
  #
  # BENCHMARK_DATABASE_URL points it at another database, which it empties and
  # rebuilds from db/migrate: schema.rb is hand-kept for SQLite, and a host gets
  # its PostgreSQL-only indexes from the migrations. BENCHMARK_QUEUE enqueues
  # through a real adapter instead of NullJobAdapter.
  module Harness
    DATABASE = File.join(ROOT, "tmp", "benchmark", "benchmark.sqlite3")
    SCHEMA = File.join(ROOT, "spec", "dummy", "db", "schema.rb")
    CGROUP = "/sys/fs/cgroup"
    PROC_STAT = "/proc/stat"
    PROC_CGROUP = "/proc/self/cgroup"
    # Plain characters only. SQLite opens a file: URI's file and ignores what
    # follows a ? or #, so a looser check would take "production.sqlite3?benchmark".
    BENCHMARK_NAME = /\A[\w.-]*benchmark[\w.-]*\z/
    QUEUES = %w[solid_queue sidekiq].freeze
    SOLID_QUEUE_SCHEMA = "lib/generators/solid_queue/install/templates/db/queue_schema.rb"

    module_function

    def boot!
      database_url = ENV["BENCHMARK_DATABASE_URL"].to_s
      queue = ENV["BENCHMARK_QUEUE"].to_s
      refuse_unknown_queue(queue) unless queue.empty?
      ENV["RAILS_ENV"] = "benchmark"
      ENV["DATABASE_URL"] = database_url.empty? ? fresh_scratch_url : database_url

      require File.join(ROOT, "spec", "dummy", "config", "application")
      refuse_unreadable_url(database_url) unless database_url.empty?
      configure(Rails.application.config, queue)
      Rails.application.initialize!
      refuse_unless_named_for_benchmarking
      database_url.empty? ? load_schema : rebuild_from_migrations
      load_solid_queue_schema if queue == "solid_queue"
      # New Rails apps run production with YJIT on, and it moves these numbers
      # by half, so neither the shell nor the Rails version gets to decide it.
      RubyVM::YJIT.enable if defined?(RubyVM::YJIT.enable)
      Rails.application
    end

    # Building the database drops tables, so one mistyped variable could empty a
    # real one. This asks Rails what it resolved rather than reading the URL:
    # Rails lets a query name another database, and PRIMARY_DATABASE_URL beats
    # DATABASE_URL. It's the file or database itself that counts, never a folder
    # or a host, and it prints only that name, because the URL holds a password.
    def refuse_unless_named_for_benchmarking
      name = File.basename(ActiveRecord::Base.connection_db_config.database.to_s)
      return if name.match?(BENCHMARK_NAME)

      abort "bin/benchmark empties the database it runs on, so it only runs on one with \"benchmark\" " \
        "in a plain name. This run would open #{name.empty? ? 'no database' : name.inspect}."
    end

    # Rails puts a URL it can't read in its error message, password and all, and
    # this runs in CI's logs. It asks Rails' own parser, so the two can't disagree.
    # Whether it's safe to run on is still the check above.
    def refuse_unreadable_url(url)
      require "active_record/database_configurations"
      ActiveRecord::DatabaseConfigurations::ConnectionUrlResolver.new(url).to_hash
    rescue URI::Error
      abort "BENCHMARK_DATABASE_URL can't be read as a URL."
    end

    # A typo must not fall back to the null adapter and pass as a real queue.
    def refuse_unknown_queue(queue)
      return if QUEUES.include?(queue)

      abort "BENCHMARK_QUEUE is #{queue.inspect}, and bin/benchmark only knows #{QUEUES.join(' and ')}."
    end

    def fresh_scratch_url
      FileUtils.mkdir_p(File.dirname(DATABASE))
      FileUtils.rm_f(Dir["#{DATABASE}*"])
      "sqlite3:#{DATABASE}"
    end

    def load_schema
      ActiveRecord::Migration.suppress_messages { load SCHEMA }
    end

    def rebuild_from_migrations
      require File.join(ROOT, "spec", "support", "test_schema")

      connection = ActiveRecord::Base.connection
      connection.disable_referential_integrity do
        connection.tables.each { |table| connection.drop_table(table, force: :cascade) }
      end
      RailsErrorDashboard::TestSchema.migrate!
    end

    # In the same database as RED's tables, as a new Rails app's Solid Queue is
    # when it shares one. The file is the gem's own, and it's only ever loaded here.
    def load_solid_queue_schema
      schema = File.join(Gem.loaded_specs.fetch("solid_queue").full_gem_path, SOLID_QUEUE_SCHEMA)
      ActiveRecord::Migration.suppress_messages { load schema }
    end

    def configure(config, queue = "")
      config.eager_load = true
      config.cache_classes = true # Rails 7.1+ reads this as enable_reloading = false
      config.logger = ActiveSupport::Logger.new($stderr, level: :warn)
      config.log_level = :warn
      config.active_job.queue_adapter = job_adapter(queue)
      config.paths["config/initializers"] = File.join(__dir__, "initializers")
    end

    def job_adapter(queue)
      return NullJobAdapter.new if queue.empty?

      require queue
      queue.to_sym
    end

    # What the harness set up, for `bin/benchmark --list` and its spec.
    def facts
      app = Rails.application.config
      {
        "Eager loading" => app.eager_load ? "on" : "off",
        "Code reloading" => app.cache_classes ? "off" : "on",
        "Scratch database" => scratch_database,
        "Job adapter" => ActiveJob::Base.queue_adapter.class.name
      }
    end

    # SQLite's database is a path, and a server's is a name.
    def scratch_database
      config = ActiveRecord::Base.connection_db_config
      config.adapter.start_with?("sqlite") ? File.expand_path(config.database, Rails.root) : config.database
    end

    # Where the numbers came from: printed above every results table.
    def environment
      uname = Etc.uname
      {
        "Ruby" => RUBY_VERSION,
        "YJIT" => yjit,
        "Rails" => Rails.version,
        "Database" => ActiveRecord::Base.connection_db_config.adapter,
        "CPU" => cpu_model,
        "Architecture" => uname[:machine],
        "CPUs" => Etc.nprocessors.to_s,
        "CPU limit" => cpu_limit,
        "Memory limit" => memory_limit,
        "OS" => "#{uname[:sysname]} #{uname[:release]}",
        "RED commit" => commit
      }
    end

    def yjit
      return "not available" unless defined?(RubyVM::YJIT.enable)

      RubyVM::YJIT.enabled? ? "on" : "off"
    end

    def cpu_model
      cpuinfo = File.readable?("/proc/cpuinfo") ? File.read("/proc/cpuinfo") : ""
      named_cpu(cpuinfo, command_output("lscpu"), command_output("sysctl", "-n", "machdep.cpu.brand_string"))
    end

    # x86 Linux gives a `model name`. ARM Linux usually doesn't, so lscpu decodes
    # the part number there, and prints "-" for a part it doesn't know. macOS has
    # neither, and has sysctl.
    def named_cpu(cpuinfo, lscpu, sysctl = "")
      names = [
        cpuinfo[/^model name\s*:\s*(.+)$/, 1],
        lscpu[/^Model name:\s*(.+)$/, 1],
        arm_part(cpuinfo),
        sysctl
      ]
      names.map { |name| name.to_s.strip }.find { |name| !name.empty? && name != "-" } || "unknown"
    end

    def arm_part(cpuinfo)
      implementer = cpuinfo[/^CPU implementer\s*:\s*(\S+)$/, 1]
      part = cpuinfo[/^CPU part\s*:\s*(\S+)$/, 1]
      "ARM implementer #{implementer}, part #{part}" if implementer && part
    end

    # A cgroup v2 quota is "<microseconds> <period>", or "max <period>" for none.
    def cpu_limit(cgroup = CGROUP, own = own_cgroup)
      return "not available" unless cgroup_visible?(cgroup, own)

      quotas = cgroup_chain(cgroup, own, "cpu.max").filter_map do |line|
        quota, period = line.split
        quota.to_f / period.to_f unless quota == "max"
      end
      quotas.empty? ? "none" : format("%.2f CPU", quotas.min)
    end

    def memory_limit(cgroup = CGROUP, own = own_cgroup)
      return "not available" unless cgroup_visible?(cgroup, own)

      limits = cgroup_chain(cgroup, own, "memory.max").reject { |limit| limit == "max" }.map(&:to_f)
      limits.empty? ? "none" : format("%.2f GB", limits.min / 1024**3)
    end

    # The process's cgroup, from the kernel's cgroup v2 line. A container with its
    # own namespace sees "/", and its limits are at the root of what it can see.
    def own_cgroup(lines = File.readable?(PROC_CGROUP) ? File.read(PROC_CGROUP) : "")
      lines[%r{^0::(/\S*)$}, 1] || "/"
    end

    # A path with ".." means the process is outside what this mount shows, so
    # finding no limit there would say nothing about the limits it's under.
    def cgroup_visible?(cgroup, own)
      File.exist?(File.join(cgroup, "cgroup.controllers")) && !own.include?("/..")
    end

    # The file's value in the process's cgroup and each one above it, since any
    # of them can limit it. The root has no limit files, so it adds nothing.
    def cgroup_chain(cgroup, own, file)
      parts = own.split("/").reject(&:empty?)
      (0..parts.size).filter_map { |depth| read_cgroup(File.join(cgroup, *parts.first(depth)), file) }
    end

    def read_cgroup(cgroup, name)
      path = File.join(cgroup, name)
      File.read(path).strip if File.readable?(path)
    end

    # The whole machine's CPU ticks, read before and after a run, or nil where
    # there's no /proc/stat. The eight fields summed leave out guest time, which
    # the kernel already counts in user.
    def cpu_ticks(stat = File.readable?(PROC_STAT) ? File.read(PROC_STAT) : "")
      fields = stat[/^cpu\s+(.+)$/, 1]&.split&.map(&:to_i)
      { steal: fields[7].to_i, total: fields.first(8).sum } if fields
    end

    def stolen_share(before, after)
      return "not available" unless before && after

      total = after[:total] - before[:total]
      format("%.2f%%", total.positive? ? 100.0 * (after[:steal] - before[:steal]) / total : 0)
    end

    def commit
      sha = command_output("git", "-C", ROOT, "rev-parse", "--short", "HEAD").strip
      sha.empty? ? "unknown" : sha
    end

    def command_output(*command)
      IO.popen(command, err: File::NULL, &:read)
    rescue SystemCallError
      ""
    end
  end
end
