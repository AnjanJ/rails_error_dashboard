# frozen_string_literal: true

# ============================================================================
# CHAOS TEST PHASE Q: Host conditions (hardening-1-0-rc2, REQ-50)
# One error from two release directories gives one group, and a capture
# survives the host's database conditions: a transaction that rolls back,
# while_preventing_writes, and a connection pool run dry by other threads.
# bin/pre-release-test full_host_conditions runs it on SQLite, PostgreSQL or
# MySQL (HOST_DATABASE) under Rails 7.2, 8.0 or 8.1 (RAILS_VERSION).
#
# The conditions run sync and async. Async uses :inline, as the other async
# apps do: the capture job then runs on the reporting thread, so a capture
# kept here was really written, and a job that can't schedule its retry
# (NotImplementedError from :inline) would reach this script.
#
# Run with: bin/rails runner test/pre_release/chaos/phase_q_host_conditions.rb
# ============================================================================

harness_path = File.expand_path("../lib/test_harness.rb", __dir__)
require harness_path
require "fileutils"
require "open3"

PreReleaseTestHarness.reset!
PreReleaseTestHarness.header("CHAOS TEST PHASE Q: HOST CONDITIONS")

# The app is the one asked for. Otherwise every CI row could pass on whatever
# Rails and database the runner happened to have.
PreReleaseTestHarness.section("Q0: The app runs the Rails and database asked for")
series = ENV["RAILS_VERSION"].to_s
unless series.empty?
  assert "Q0: Rails #{series} (#{Rails.version})", Rails.version.start_with?("#{series}.")
end
database = ENV.fetch("HOST_DATABASE", "sqlite")
adapter = ActiveRecord::Base.connection_db_config.adapter.to_s
expected = { "sqlite" => /sqlite/, "postgresql" => /postg/, "mysql" => /mysql|trilogy/ }[database]
assert "Q0: #{database} (#{adapter})", expected&.match?(adapter)
puts ""

# The host's own table, written inside its transactions. Created outside any
# transaction: on MySQL, DDL commits.
class ChaosHostRow < ActiveRecord::Base
  self.table_name = "red_chaos_host_rows"
end
ActiveRecord::Base.connection.create_table(ChaosHostRow.table_name, if_not_exists: true) { |t| t.string :name }

def captured(message)
  RailsErrorDashboard::ErrorLog.where(message: message).sum(:occurrence_count).to_i
end

# How a host reports an error it rescued. A new exception each time: Rails
# reports an exception object once.
def report_failure(message)
  raise RuntimeError, message
rescue => e
  Rails.error.report(e, handled: true, severity: :error)
end

def mono = Process.clock_gettime(Process::CLOCK_MONOTONIC)

# As assert_no_crash, for any error RED could let out: a ScriptError such as
# NotImplementedError passes `rescue => e`, and would end the script instead.
def without_raising(label)
  yield
  assert label, true
rescue StandardError, ScriptError => e
  assert label, false, "#{e.class}: #{e.message}"
end

config = RailsErrorDashboard.configuration
# Nothing else in this process takes a connection or runs a job in the
# background: no webhook to a closed port, no baseline alert, and :inline
# for every job.
config.enable_webhook_notifications = false
config.enable_baseline_alerts = false
ActiveJob::Base.queue_adapter = :inline

begin
  # -------------------------------------------------------------------------
  # Q1: One error from two release directories (Capistrano's layout)
  # -------------------------------------------------------------------------
  PreReleaseTestHarness.section("Q1: One error from two release directories gives one group")

  message = "release probe 42 failed"
  releases_dir = Rails.root.dirname.join("#{Rails.root.basename}_releases")
  probe = <<~RUBY
    module ChaosReleaseProbe
      def self.explode
        raise ArgumentError, #{message.inspect}
      end
    end
  RUBY
  report = "RailsErrorDashboard.configuration.enable_webhook_notifications = false; " \
           "begin; ChaosReleaseProbe.explode; rescue => e; Rails.error.report(e, handled: true, severity: :error); end"

  %w[20261101000000 20261102000000].each do |stamp|
    release = releases_dir.join("releases", stamp)
    # The app's code, as a deploy unpacks a release: storage/ (the SQLite
    # database), tmp/ and log/ stay behind, as Capistrano shares them.
    FileUtils.mkdir_p([ release.join("tmp"), release.join("log") ])
    Dir.children(Rails.root).reject { |name| %w[storage tmp log].include?(name) }.each do |name|
      FileUtils.cp_r(Rails.root.join(name), release)
    end
    File.write(release.join("app/models/chaos_release_probe.rb"), probe)

    # The release's own bundle and boot, as a deploy runs it. The database is
    # the same: database.yml names it by absolute path or by URL.
    output, status = Bundler.with_unbundled_env do
      Open3.capture2e({ "BUNDLE_GEMFILE" => release.join("Gemfile").to_s }, "bin/rails", "runner", report, chdir: release.to_s)
    end
    assert "Q1: release #{stamp} reported the error", status.success?, output.lines.last(3).join.strip
  end

  rows = RailsErrorDashboard::ErrorLog.where(message: message)
  assert "Q1: both reports captured", captured(message) == 2, "got #{captured(message)}"
  assert "Q1: one group for the two releases", rows.count == 1, "got #{rows.count} groups"
  FileUtils.rm_rf(releases_dir)
  puts ""

  { sync: false, async: true }.each do |mode, async|
    config.async_logging = async

    # -----------------------------------------------------------------------
    # Q2: A report inside a transaction that rolls back (REQ-17)
    # -----------------------------------------------------------------------
    PreReleaseTestHarness.section("Q2 (#{mode}): A report in a transaction that rolls back is kept")

    message = "Q2 #{mode} rollback #{SecureRandom.hex(4)}"
    without_raising("Q2 (#{mode}): the report doesn't raise") do
      ActiveRecord::Base.transaction do
        ChaosHostRow.create!(name: message)
        report_failure(message)
        raise ActiveRecord::Rollback
      end
    end
    assert "Q2 (#{mode}): the host's own row rolled back", ChaosHostRow.where(name: message).none?
    assert "Q2 (#{mode}): the capture was kept, once", captured(message) == 1, "got #{captured(message)}"
    puts ""

    # -----------------------------------------------------------------------
    # Q3: A report under while_preventing_writes (REQ-18)
    # -----------------------------------------------------------------------
    PreReleaseTestHarness.section("Q3 (#{mode}): A report under while_preventing_writes is kept")

    message = "Q3 #{mode} prevented #{SecureRandom.hex(4)}"
    without_raising("Q3 (#{mode}): the report doesn't raise") do
      ActiveRecord::Base.while_preventing_writes { report_failure(message) }
    end
    assert "Q3 (#{mode}): the capture was kept, once", captured(message) == 1, "got #{captured(message)}"
    puts ""

    # -----------------------------------------------------------------------
    # Q4: A report with the pool held by other threads (REQ-20)
    # -----------------------------------------------------------------------
    PreReleaseTestHarness.section("Q4 (#{mode}): A report with the connection pool held returns fast")

    message = "Q4 #{mode} pool held #{SecureRandom.hex(4)}"
    pool = ActiveRecord::Base.connection_pool
    ActiveRecord::Base.connection_handler.clear_active_connections!(:all)
    ready = Queue.new
    release = Queue.new
    holders = Array.new(pool.size) do
      Thread.new do
        connection = pool.checkout
        ready << true
        release.pop
        pool.checkin(connection)
      rescue => e
        ready << e
      end
    end
    took = nil
    begin
      held = Array.new(pool.size) { ready.pop }
      assert "Q4 (#{mode}): other threads hold all #{pool.size} connections", held.all?(true), held.reject { |h| h == true }.first.inspect
      without_raising("Q4 (#{mode}): the report doesn't raise") do
        started = mono
        report_failure(message)
        took = mono - started
      end
    ensure
      holders.size.times { release << true }
      holders.each(&:join)
    end
    # rc.1 waited the pool's checkout_timeout (5 s here), more than once, and
    # has no capture_connection_timeout.
    bound = config.respond_to?(:capture_connection_timeout) ? "#{config.capture_connection_timeout} s" : "none"
    assert "Q4 (#{mode}): it returned in #{took ? format("%.3f", took) : "?"} s, under 1 s " \
           "(capture_connection_timeout #{bound}, checkout_timeout #{pool.checkout_timeout} s)",
           took && took < 1.0
    assert "Q4 (#{mode}): it gave up, storing nothing (REQ-20)", captured(message) == 0, "got #{captured(message)}"
    puts ""
  end
ensure
  config.async_logging = false
  ActiveRecord::Base.connection.drop_table(ChaosHostRow.table_name, if_exists: true)
end

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
exit_code = PreReleaseTestHarness.summary("PHASE Q")
exit(exit_code)
