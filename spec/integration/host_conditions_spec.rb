# frozen_string_literal: true

require "rails_helper"

# The host's own writes inside its transactions. The dummy app has no table of
# its own, so the group below creates one and drops it again.
module HostConditionsSpec
  class Row < ActiveRecord::Base
    self.table_name = "red_host_conditions_rows"
  end
end

# hardening-1-0-rc2: REQ-17, REQ-18, REQ-19, REQ-20, REQ-22, REQ-51, REQ-52 and
# REQ-53. design.md: "Captures wait for the host's transaction, on the shared
# connection (from spike S1)", with its 2026-11-25 amendment.
#
# rc.1 lost a capture reported inside a transaction or savepoint that rolled
# back, and one reported while the host prevented writes or read from a
# replica. With the pool run dry it waited the pool's checkout_timeout
# (.shipkit/research/host-conditions-spike.md). Each case runs the three ways a
# capture is written: sync, async outside a request (a job, a console, a rake
# task), and async in a request whose server runs rack.response_finished
# callbacks after the response.
#
# Every example runs on committed rows (:non_transactional). The host's
# transactions are then real ones, not savepoints inside the test's, and other
# threads can take the pool's connections.
#
# The test adapter keeps an enqueued job in memory, so a rolled-back enqueue
# still looks queued here, where a queue in the host's database (Solid Queue)
# loses it. So the async examples check where the enqueue ran: outside any host
# transaction, in the writing role, with writes allowed. Then they run the job
# and count what was stored.
RSpec.describe "Captures under the host's database conditions", :non_transactional do
  self.use_transactional_tests = false

  let(:logs) { RailsErrorDashboard::ErrorLog }
  let(:job_class) { RailsErrorDashboard::AsyncErrorLoggingJob }
  let(:host_pool) { ActiveRecord::Base.connection_pool }
  let(:timeout) { RailsErrorDashboard.configuration.capture_connection_timeout }
  # Where an enqueue that kept the capture ran.
  let(:outside_the_host) { { in_transaction: false, role: ActiveRecord.writing_role, preventing_writes: false } }

  before(:all) do
    ActiveRecord::Base.lease_connection.create_table(HostConditionsSpec::Row.table_name, if_not_exists: true) do |t|
      t.string :name
    end
    HostConditionsSpec::Row.reset_column_information
  end

  after(:all) do
    ActiveRecord::Base.lease_connection.drop_table(HostConditionsSpec::Row.table_name, if_exists: true)
  end

  before do
    RailsErrorDashboard.reset_configuration!
    config = RailsErrorDashboard.configuration
    config.enable_storm_protection = false
    config.sampling_rate = 1.0
    allow(RailsErrorDashboard::Services::ErrorBroadcaster).to receive(:available?).and_return(false)
    Thread.current[:rails_error_dashboard_request_env] = nil
    @enqueues = []
  end

  after do
    Thread.current[:rails_error_dashboard_request_env] = nil
    Thread.current[:rails_error_dashboard_reported_errors] = nil
    RailsErrorDashboard.reset_configuration!
  end

  def mono = Process.clock_gettime(Process::CLOCK_MONOTONIC_RAW)

  def elapsed
    started = mono
    yield
    mono - started
  end

  def failure(message = "host conditions probe")
    RuntimeError.new(message).tap { |error| error.set_backtrace([ "#{Rails.root}/app/models/order.rb:12:in 'save'" ]) }
  end

  # How a host reports an error it rescued. RED skips handled warnings.
  def report(error = failure)
    Rails.error.report(error, handled: true, severity: :error)
  end

  def touch_host
    HostConditionsSpec::Row.create!(name: "host")
  end

  def occurrences
    logs.sum(:occurrence_count).to_i
  end

  def sqlite?
    ActiveRecord::Base.connection_db_config.adapter.to_s.start_with?("sqlite")
  end

  def use_mode(mode)
    RailsErrorDashboard.configuration.async_logging = mode != :sync
    watch_enqueues unless mode == :sync
  end

  # Records where each capture job was enqueued from. With queue_in_database,
  # the enqueue first takes a connection from the host's pool, as Solid Queue
  # in the host's database does; otherwise it needs none, as Sidekiq doesn't.
  def watch_enqueues(queue_in_database: false)
    allow(job_class).to receive(:perform_later).and_wrap_original do |original, *args|
      @enqueues << {
        in_transaction: ActiveRecord::Base.current_transaction.open?,
        role: ActiveRecord::Base.current_role,
        preventing_writes: ActiveRecord::Base.current_preventing_writes
      }
      ActiveRecord::Base.connection_pool.with_connection { |connection| connection.select_value("SELECT 1") } if queue_in_database
      original.call(*args)
    end
  end

  # As a host's request runs. In :async_in_request the server's
  # rack.response_finished callbacks run once the block has returned, outside
  # its transaction and role, as Puma runs them after the response.
  def as_host(mode)
    return yield unless mode == :async_in_request

    env = Rack::MockRequest.env_for("/orders/1")
    env["rack.response_finished"] = []
    begin
      Thread.current[:rails_error_dashboard_request_env] = env
      yield
    ensure
      Thread.current[:rails_error_dashboard_request_env] = nil
    end
    finish_response(env)
  end

  def finish_response(env)
    env["rack.response_finished"].reverse_each { |callable| callable.call(env, 500, {}, nil) }
  end

  # The capture was written count times, outside the host's transaction, role
  # and write prevention.
  def expect_kept(mode, count = 1)
    unless mode == :sync
      expect(@enqueues.size).to eq(count)
      expect(@enqueues.uniq).to eq([ outside_the_host ])
      perform_enqueued_jobs(only: job_class)
    end
    expect(occurrences).to eq(count)
  end

  # A reading role on ActiveRecord::Base, as DatabaseSelector switches to: the
  # same database, refused as a replica is (replica: true), and read-only in the
  # database too where the adapter has a setting for it.
  def in_reading_role(&block)
    primary = ActiveRecord::Base.connection_db_config
    replica = primary.configuration_hash.merge(replica: true)
    case primary.adapter.to_s
    when /postg/ then replica[:variables] = { default_transaction_read_only: "on" }
    when /mysql|trilogy/ then replica[:variables] = { transaction_read_only: 1 }
    end
    config = ActiveRecord::DatabaseConfigurations::HashConfig.new(primary.env_name, "primary_replica", replica)
    ActiveRecord::Base.connection_handler.establish_connection(config, owner_name: ActiveRecord::Base, role: ActiveRecord.reading_role)
    ActiveRecord::Base.connected_to(role: ActiveRecord.reading_role, prevent_writes: true, &block)
  ensure
    ActiveRecord::Base.connection_handler.remove_connection_pool(ActiveRecord::Base.name, role: ActiveRecord.reading_role)
  end

  # Every connection of the pool checked out by other threads, and none held by
  # this one: the pool has run dry. Checkouts are counted from here on.
  def with_pool_drained(pool)
    ActiveRecord::Base.connection_handler.clear_active_connections!(:all)
    ready = Queue.new
    release = Queue.new
    holders = Array.new(pool.size) do
      Thread.new do
        connection = pool.checkout
        ready << true
        release.pop
        pool.checkin(connection)
      end
    end
    pool.size.times { ready.pop }
    # A process's first lease prepends the checkout bound. The spy below keeps
    # the checkout it finds when it is set, so the bound goes in first, or an
    # example run on its own would time the pool's own wait.
    RailsErrorDashboard::Services::CaptureWriteGuard.lease { nil }
    allow(pool).to receive(:checkout).and_call_original
    yield
  ensure
    holders&.size&.times { release << true }
    holders&.each(&:join)
  end

  # Where a capture is reported, and the requirements each case covers.
  host_cases = {
    "a transaction that rolls back" => [
      "REQ-17", proc { ActiveRecord::Base.transaction { touch_host; report; raise ActiveRecord::Rollback } }
    ],
    "a savepoint that rolls back, inside a transaction that commits" => [
      "REQ-17, REQ-51", proc {
        ActiveRecord::Base.transaction do
          touch_host
          ActiveRecord::Base.transaction(requires_new: true) { report; raise ActiveRecord::Rollback }
        end
      }
    ],
    "a savepoint that rolls back, inside a transaction that then rolls back" => [
      "REQ-17, REQ-51", proc {
        ActiveRecord::Base.transaction do
          touch_host
          ActiveRecord::Base.transaction(requires_new: true) { report; raise ActiveRecord::Rollback }
          raise ActiveRecord::Rollback
        end
      }
    ],
    "a savepoint that commits, inside a transaction that rolls back" => [
      "REQ-17, REQ-51", proc {
        ActiveRecord::Base.transaction do
          touch_host
          ActiveRecord::Base.transaction(requires_new: true) { report }
          raise ActiveRecord::Rollback
        end
      }
    ],
    "while_preventing_writes" => [
      "REQ-18", proc { ActiveRecord::Base.while_preventing_writes { report } }
    ],
    "a reading role that prevents writes" => [
      "REQ-18", proc { in_reading_role { report } }
    ]
  }

  modes = %i[sync async async_in_request]

  modes.each do |mode|
    context "with #{mode} capture" do
      before { use_mode(mode) }

      it "keeps a capture reported outside any transaction (the control)" do
        as_host(mode) { report }

        expect_kept(mode)
      end

      host_cases.each do |name, (reqs, host_code)|
        it "keeps a capture reported in #{name}, once (#{reqs})" do
          as_host(mode) { instance_exec(&host_code) }

          expect_kept(mode)
        end
      end

      it "writes a capture from a committed transaction after the commit, at the time it was reported (REQ-51)" do
        reported_at = nil
        before_commit = nil
        as_host(mode) do
          ActiveRecord::Base.transaction do
            touch_host
            reported_at = Time.current
            report
            before_commit = { stored: occurrences, enqueued: @enqueues.size }
            travel 10.minutes
          end
        end

        expect(before_commit).to eq(stored: 0, enqueued: 0)
        expect_kept(mode)
        expect(logs.last.occurred_at).to be_within(1.second).of(reported_at)
      ensure
        travel_back
      end

      it "keeps the first 100 captures reported inside one transaction and drops the rest without raising (REQ-52)" do
        expect {
          as_host(mode) do
            ActiveRecord::Base.transaction do
              touch_host
              101.times { report }
            end
          end
        }.not_to raise_error

        expect_kept(mode, 100)
      end

      # The maintainer's 2026-11-24 decision: a capture that waits is
      # snapshotted when it is reported, so a later capture in the same
      # transaction, or the transaction's later queries, don't change it.
      it "keeps the breadcrumbs of the moment each waiting capture was reported" do
        collector = RailsErrorDashboard::Services::BreadcrumbCollector
        RailsErrorDashboard.configuration.enable_breadcrumbs = true
        collector.init_buffer
        as_host(mode) do
          ActiveRecord::Base.transaction do
            touch_host
            collector.add("custom", "before the first error")
            report(failure("first failure"))
            collector.add("custom", "before the second error")
            report(failure("second failure"))
            collector.add("custom", "after both errors")
          end
        end

        expect_kept(mode, 2)
        # By message: in a request the server runs its callbacks last first.
        trails = logs.all.to_h { |log| [ log.message, JSON.parse(log.breadcrumbs).select { |crumb| crumb["c"] == "custom" }.map { |crumb| crumb["m"] } ] }
        expect(trails).to eq("first failure" => [ "before the first error" ], "second failure" => [ "before the second error" ])
      ensure
        collector.clear_buffer
      end

      it "keeps the system health of the moment a waiting capture was reported" do
        RailsErrorDashboard.configuration.enable_system_health = true
        snapshots = 0
        allow(RailsErrorDashboard::Services::SystemHealthSnapshot).to receive(:capture) { { "snapshot" => snapshots += 1 } }
        as_host(mode) do
          ActiveRecord::Base.transaction do
            touch_host
            report
            RailsErrorDashboard::Services::SystemHealthSnapshot.capture
          end
        end

        expect_kept(mode)
        expect(JSON.parse(logs.last.system_health)).to eq("snapshot" => 1)
      end

      it "takes no snapshot for a capture the storm gate sheds to lite" do
        config = RailsErrorDashboard.configuration
        config.enable_breadcrumbs = true
        config.enable_system_health = true
        RailsErrorDashboard::Services::BreadcrumbCollector.init_buffer
        RailsErrorDashboard::Services::BreadcrumbCollector.add("custom", "left alone")
        allow(RailsErrorDashboard::Services::StormProtection::Gate).to receive(:admit!).and_return(:lite)
        allow(RailsErrorDashboard::Services::SystemHealthSnapshot).to receive(:capture).and_call_original

        as_host(mode) { ActiveRecord::Base.transaction { touch_host; report } }

        expect_kept(mode)
        expect(RailsErrorDashboard::Services::SystemHealthSnapshot).not_to have_received(:capture)
        expect(RailsErrorDashboard::Services::BreadcrumbCollector.current_buffer.to_a.select { |crumb| crumb[:c] == "custom" }.map { |crumb| crumb[:m] }).to eq([ "left alone" ])
      ensure
        RailsErrorDashboard::Services::BreadcrumbCollector.clear_buffer
      end
    end
  end

  # REQ-22: the switch off is rc.1, case by case. A sync write lands inside the
  # host's condition and is lost with it; an async enqueue outside a request
  # runs inside it; one in a request already ran after the response.
  context "with isolate_capture_writes = false (REQ-22)" do
    before { RailsErrorDashboard.configuration.isolate_capture_writes = false }

    modes.each do |mode|
      context "with #{mode} capture" do
        before { use_mode(mode) }

        host_cases.each do |name, (_reqs, host_code)|
          it "does as rc.1 did with a capture reported in #{name}" do
            as_host(mode) { instance_exec(&host_code) }

            case mode
            when :sync
              expect(occurrences).to eq(0)
            when :async
              expect(@enqueues.size).to eq(1)
              expect(@enqueues.first).not_to eq(outside_the_host)
            else
              expect_kept(mode)
            end
          end
        end
      end
    end

    it "waits the pool's own checkout_timeout when the pool has run dry" do
      use_mode(:sync)
      was = host_pool.checkout_timeout
      host_pool.checkout_timeout = 0.5

      took = with_pool_drained(host_pool) { elapsed { report(ActiveRecord::ConnectionTimeoutError.new("pool ran dry")) } }

      expect(took).to be >= 0.5
    ensure
      host_pool.checkout_timeout = was
    end
  end

  # REQ-19. The refusal arrives inside the host's commit when the capture
  # waited for it, and must not reach the host there either.
  describe "when the database refuses RED's write (REQ-19)" do
    [ ActiveRecord::StatementInvalid, ActiveRecord::ReadOnlyError ].each do |refusal|
      %i[sync async].each do |mode|
        it "drops a #{mode} capture whose write raises #{refusal.name.demodulize}, outside and inside a host transaction" do
          use_mode(mode)
          allow(job_class).to receive(:perform_later).and_raise(refusal, "refused") if mode == :async
          allow(logs).to receive(:find_or_increment_by_hash).and_raise(refusal, "refused")

          expect {
            report
            ActiveRecord::Base.transaction { touch_host; report }
          }.not_to raise_error

          expect(HostConditionsSpec::Row.count).to eq(1)
          expect(occurrences).to eq(0)
        end
      end
    end
  end

  # REQ-20 and REQ-53. checkout_timeout is 1 s here, ten times the capture's
  # timeout, so a wait on the pool's own timeout can't pass for the bounded one.
  # The lower bound has 5 ms of slack: Rails times its wait on another clock.
  describe "with the pool run dry by other threads (REQ-20, REQ-53)" do
    let(:dry) { ActiveRecord::ConnectionTimeoutError.new("could not obtain a connection from the pool") }

    around do |example|
      was = host_pool.checkout_timeout
      host_pool.checkout_timeout = 1.0
      example.run
    ensure
      host_pool.checkout_timeout = was
    end

    it "holds one connection of RED's pool for the whole sync write, on a thread that holds none (REQ-20)" do
      use_mode(:sync)
      ActiveRecord::Base.connection_handler.clear_active_connections!(:all)
      allow(host_pool).to receive(:checkout).and_call_original

      report

      expect(host_pool).to have_received(:checkout).once
      expect(occurrences).to eq(1)
    end

    it "gives a sync capture up after one wait of capture_connection_timeout, storing nothing (REQ-20)" do
      use_mode(:sync)

      with_pool_drained(host_pool) do
        took = elapsed { report(dry) }

        expect(took).to be_between(timeout - 0.005, timeout + 0.05)
        expect(host_pool).to have_received(:checkout).once
      end
      expect(occurrences).to eq(0)
    end

    it "gives an async enqueue to a queue in the host's database up after one wait, enqueueing nothing (REQ-20)" do
      use_mode(:async)
      watch_enqueues(queue_in_database: true)

      with_pool_drained(host_pool) do
        took = elapsed { report(dry) }

        expect(took).to be_between(timeout - 0.005, timeout + 0.05)
        expect(host_pool).to have_received(:checkout).once
      end
      expect(job_class.queue_adapter.enqueued_jobs.count { |job| job[:job] == job_class }).to eq(0)
      expect(occurrences).to eq(0)
    end

    it "enqueues at once, with no checkout, when the queue needs no database connection (REQ-20)" do
      use_mode(:async)

      with_pool_drained(host_pool) do
        took = elapsed { report(dry) }

        expect(took).to be < 0.05
        expect(host_pool).not_to have_received(:checkout)
      end
      expect(@enqueues.size).to eq(1)
    end

    it "makes no checkout on the request thread, and one bounded wait after the response (REQ-53, REQ-20)" do
      use_mode(:async)
      watch_enqueues(queue_in_database: true)
      env = Rack::MockRequest.env_for("/orders/1")
      env["rack.response_finished"] = []

      with_pool_drained(host_pool) do
        on_request = elapsed do
          Thread.current[:rails_error_dashboard_request_env] = env
          report(dry)
        ensure
          Thread.current[:rails_error_dashboard_request_env] = nil
        end

        expect(on_request).to be < 0.05
        expect(host_pool).not_to have_received(:checkout)

        after_response = elapsed { finish_response(env) }

        expect(after_response).to be_between(timeout - 0.005, timeout + 0.05)
        expect(host_pool).to have_received(:checkout).once
      end
      expect(job_class.queue_adapter.enqueued_jobs.count { |job| job[:job] == job_class }).to eq(0)
    end

    # The maintainer's 2026-11-24 decision: RED's own job is not the host's
    # request. A connection timeout there is retried, so it keeps the pool's
    # own wait and raises for retry_on rather than giving up after the
    # capture's timeout.
    it "leaves RED's own capture job to the pool's wait and a retry" do
      job = job_class.new({ class_name: "RuntimeError", message: "queued capture", backtrace: [] }, {})

      took = with_pool_drained(host_pool) { elapsed { job.perform_now } }

      expect(took).to be >= host_pool.checkout_timeout
      retries = job_class.queue_adapter.enqueued_jobs.select { |queued| queued[:job] == job_class && queued[:at] }
      expect(retries.size).to eq(1)
      expect(occurrences).to eq(0)
    end
  end

  # :inline runs the capture job inside perform_later, on the thread that
  # reported the error, and its enqueue_at raises NotImplementedError when
  # retry_on schedules a retry, as adapters with no scheduler do. That is a
  # ScriptError, so it passed every `rescue => e` up to the host, on rc.1 too
  # (reproduced 2026-11-26; design.md, the S1 decision's amendments). The job
  # runs as it is enqueued (perform_enqueued_jobs with a block), and the
  # adapter's enqueue_at is stubbed, not swapped (tasks/lessons.md, 2026-11-23).
  describe "with a queue adapter that runs the job on the reporting thread and can't schedule a retry (REQ-19, REQ-20)" do
    around do |example|
      was = host_pool.checkout_timeout
      host_pool.checkout_timeout = 1.0
      example.run
    ensure
      host_pool.checkout_timeout = was
    end

    before do
      use_mode(:async)
      allow(job_class.queue_adapter).to receive(:enqueue_at)
        .and_raise(NotImplementedError, "Use a queueing backend to enqueue jobs in the future.")
    end

    def performed
      job_class.queue_adapter.performed_jobs.count { |job| job[:job] == job_class }
    end

    it "drops a capture whose write the database refuses, without raising, outside and inside a host transaction (REQ-19)" do
      allow(logs).to receive(:find_or_increment_by_hash).and_raise(ActiveRecord::StatementInvalid, "refused")

      expect {
        perform_enqueued_jobs(only: job_class) do
          report
          RailsErrorDashboard::Commands::LogError.call(failure("reported through LogError"), {})
          ActiveRecord::Base.transaction { touch_host; report }
        end
      }.not_to raise_error

      expect(performed).to eq(3)
      expect(job_class.queue_adapter).to have_received(:enqueue_at).exactly(3).times
      expect(HostConditionsSpec::Row.count).to eq(1)
      expect(occurrences).to eq(0)
    end

    # The first capture down this path in a process took 0.09 to 0.29 s more
    # than the next ones (measured 2026-11-26, one checkout each), so the
    # second one is timed. Two exceptions: Rails reports an exception once.
    it "gives up after one wait of capture_connection_timeout when the pool has run dry, without raising (REQ-20)" do
      with_pool_drained(host_pool) do
        perform_enqueued_jobs(only: job_class) { report(failure("first")) }
        took = elapsed do
          expect { perform_enqueued_jobs(only: job_class) { report(failure("second")) } }.not_to raise_error
        end

        expect(took).to be_between(timeout - 0.005, timeout + 0.05)
        expect(host_pool).to have_received(:checkout).twice
      end
      expect(performed).to eq(2)
      expect(occurrences).to eq(0)
    end

    # The outer layers, for whatever else raises an error that isn't a
    # StandardError on the way.
    it "lets no ScriptError out of LogError.call" do
      allow(job_class).to receive(:perform_later).and_raise(NotImplementedError, "no scheduled jobs")

      expect(RailsErrorDashboard::Commands::LogError.call(failure, {})).to be_nil
    end

    it "lets no ScriptError out of Rails.error.report" do
      allow(RailsErrorDashboard::Commands::LogError).to receive(:call).and_raise(LoadError, "cannot load such file")

      expect { report }.not_to raise_error
    end
  end

  # With use_separate_database. On SQLite RED's tables go to a second file, so
  # the host's write lock can't hold RED's write up. On PostgreSQL and MySQL
  # they get a second pool on the same database, which is what keeps RED's
  # write apart from the host's transaction there.
  context "with RED's tables in their own database (use_separate_database)" do
    around do |example|
      primary = ActiveRecord::Base.connection_db_config
      settings = primary.configuration_hash.merge(pool: 2)
      if sqlite?
        separate_file = File.join(Dir.tmpdir, "red_host_conditions_#{Process.pid}.sqlite3")
        FileUtils.rm_f([ separate_file, "#{separate_file}-wal", "#{separate_file}-shm" ])
        ActiveRecord::Base.lease_connection.execute("VACUUM INTO '#{separate_file}'")
        settings = settings.merge(database: separate_file)
      end
      config = ActiveRecord::DatabaseConfigurations::HashConfig.new(primary.env_name, "error_dashboard", settings)
      RailsErrorDashboard::ErrorLogsRecord.connects_to(database: { writing: config, reading: config })
      example.run
    ensure
      handler = ActiveRecord::Base.connection_handler
      [ ActiveRecord.writing_role, ActiveRecord.reading_role ].each do |role|
        handler.remove_connection_pool(RailsErrorDashboard::ErrorLogsRecord.name, role: role)
      end
      RailsErrorDashboard::ErrorLogsRecord.connection_specification_name = nil
      RailsErrorDashboard::ErrorLogsRecord.connection_class = false
      FileUtils.rm_f([ separate_file, "#{separate_file}-wal", "#{separate_file}-shm" ]) if separate_file
    end

    before { RailsErrorDashboard.configuration.use_separate_database = true }

    let(:red_pool) { RailsErrorDashboard::ErrorLogsRecord.connection_pool }

    it "really writes through a pool of its own" do
      expect(red_pool).not_to equal(host_pool)
    end

    modes.each do |mode|
      context "with #{mode} capture" do
        before { use_mode(mode) }

        host_cases.each do |name, (reqs, host_code)|
          it "keeps a capture reported in #{name}, once (#{reqs})" do
            as_host(mode) { instance_exec(&host_code) }

            expect_kept(mode)
          end
        end
      end
    end

    describe "with a pool run dry by other threads (REQ-20)" do
      let(:dry) { ActiveRecord::ConnectionTimeoutError.new("could not obtain a connection from the pool") }

      around do |example|
        was = red_pool.checkout_timeout
        red_pool.checkout_timeout = 1.0
        example.run
      ensure
        red_pool.checkout_timeout = was
      end

      it "gives a sync capture up after one wait when RED's own pool has run dry" do
        use_mode(:sync)

        with_pool_drained(red_pool) do
          took = elapsed { report(dry) }

          expect(took).to be_between(timeout - 0.005, timeout + 0.05)
          expect(red_pool).to have_received(:checkout).once
        end
        expect(occurrences).to eq(0)
      end

      it "stores a sync capture when only the host's pool has run dry, without touching it" do
        use_mode(:sync)

        with_pool_drained(host_pool) do
          report(dry)

          expect(host_pool).not_to have_received(:checkout)
        end
        expect(occurrences).to eq(1)
      end
    end
  end
end
