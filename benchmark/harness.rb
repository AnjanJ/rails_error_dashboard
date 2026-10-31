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
  module Harness
    DATABASE = File.join(ROOT, "tmp", "benchmark", "benchmark.sqlite3")
    SCHEMA = File.join(ROOT, "spec", "dummy", "db", "schema.rb")

    module_function

    def boot!
      FileUtils.mkdir_p(File.dirname(DATABASE))
      FileUtils.rm_f(Dir["#{DATABASE}*"])
      ENV["RAILS_ENV"] = "benchmark"
      ENV["DATABASE_URL"] = "sqlite3:#{DATABASE}"

      require File.join(ROOT, "spec", "dummy", "config", "application")
      configure(Rails.application.config)
      Rails.application.initialize!
      ActiveRecord::Migration.suppress_messages { load SCHEMA }
      # New Rails apps run production with YJIT on, and it moves these numbers
      # by half, so neither the shell nor the Rails version gets to decide it.
      RubyVM::YJIT.enable if defined?(RubyVM::YJIT.enable)
      Rails.application
    end

    def configure(config)
      config.eager_load = true
      config.cache_classes = true # Rails 7.1+ reads this as enable_reloading = false
      config.logger = ActiveSupport::Logger.new($stderr, level: :warn)
      config.log_level = :warn
      config.active_job.queue_adapter = NullJobAdapter.new
      config.paths["config/initializers"] = File.join(__dir__, "initializers")
    end

    # What the harness set up, for `bin/benchmark --list` and its spec.
    def facts
      app = Rails.application.config
      {
        "Eager loading" => app.eager_load ? "on" : "off",
        "Code reloading" => app.cache_classes ? "off" : "on",
        "Scratch database" => File.expand_path(ActiveRecord::Base.connection_db_config.database, Rails.root),
        "Job adapter" => ActiveJob::Base.queue_adapter.class.name
      }
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
