# frozen_string_literal: true

require "rails_helper"

# hardening-1-0-rc2: REQ-17, REQ-18, REQ-20, REQ-51 and REQ-52, at the guard's
# three entry points. spec/integration/host_conditions_spec.rb covers the same
# requirements through a real capture.
RSpec.describe RailsErrorDashboard::Services::CaptureWriteGuard do
  let(:guard) { described_class }

  after { RailsErrorDashboard.reset_configuration! }

  def mono = Process.clock_gettime(Process::CLOCK_MONOTONIC_RAW)

  def elapsed
    started = mono
    yield
    mono - started
  end

  describe ".defer" do
    it "runs the block at once, returning its value, when no host transaction is open" do
      expect(guard.transaction_open?).to be(false)
      expect(guard.defer { :ran }).to eq(:ran)
    end

    it "inside a transaction, runs the block once, after the commit and not before (REQ-51)" do
      runs = []
      ActiveRecord::Base.transaction do
        expect(guard.transaction_open?).to be(true)
        expect(guard.defer { runs << :ran }).to be_nil
        expect(runs).to be_empty
      end

      expect(runs).to eq([ :ran ])
    end

    it "runs the block once after a rollback too (REQ-17)" do
      runs = []
      ActiveRecord::Base.transaction do
        guard.defer { runs << :ran }
        raise ActiveRecord::Rollback
      end

      expect(runs).to eq([ :ran ])
    end

    it "makes a savepoint's block wait for the transaction around it (REQ-51)" do
      runs = []
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.transaction(requires_new: true) do
          guard.defer { runs << :ran }
          raise ActiveRecord::Rollback
        end
        expect(runs).to be_empty
      end

      expect(runs).to eq([ :ran ])
    end

    it "lets 100 blocks wait on one transaction and drops the rest without raising (REQ-52)" do
      runs = 0
      expect {
        ActiveRecord::Base.transaction do
          101.times { guard.defer { runs += 1 } }
        end
      }.not_to raise_error

      expect(runs).to eq(described_class::MAX_WAITING)
      expect(described_class::MAX_WAITING).to eq(100)
    end

    it "says once each time it reaches the limit that it is dropping captures, not once per capture" do
      allow(RailsErrorDashboard::Logger).to receive(:error)

      2.times { ActiveRecord::Base.transaction { 150.times { guard.defer { nil } } } }

      expect(RailsErrorDashboard::Logger).to have_received(:error).with(/dropping further ones/).twice
    end

    it "gives the next transaction its own 100 (REQ-52)" do
      runs = 0
      2.times do
        ActiveRecord::Base.transaction { 100.times { guard.defer { runs += 1 } } }
      end

      expect(runs).to eq(200)
    end

    # A host after_commit callback that raises stops Rails running the rest, so
    # the blocks waiting behind it never run. They must not go on counting
    # against the limit for every later transaction on this thread.
    it "stops counting blocks Rails never ran once they are collected (REQ-52)" do
      lost = lambda do
        ActiveRecord::Base.transaction do
          ActiveRecord::Base.current_transaction.after_commit { raise "the host's callback failed" }
          100.times { guard.defer { nil } }
        end
      end
      expect(&lost).to raise_error(RuntimeError, "the host's callback failed")
      3.times { GC.start(full_mark: true, immediate_sweep: true) }

      runs = 0
      ActiveRecord::Base.transaction { guard.defer { runs += 1 } }

      expect(runs).to eq(1)
    end

    it "never raises into the host's commit, whatever the block raises" do
      [ RuntimeError.new("write failed"), NotImplementedError.new("adapter can't schedule") ].each do |error|
        expect {
          ActiveRecord::Base.transaction { guard.defer { raise error } }
        }.not_to raise_error
      end
    end

    it "runs a waiting block with RED's recursion guard set, and restores it" do
      seen = nil
      ActiveRecord::Base.transaction do
        guard.defer { seen = Thread.current[:rails_error_dashboard_logging] }
      end

      expect(seen).to be(true)
      expect(Thread.current[:rails_error_dashboard_logging]).to be_nil
    end

    it "runs the block at once when the transaction check fails" do
      allow(ActiveRecord::Base).to receive(:current_transaction).and_raise(ActiveRecord::ConnectionNotEstablished)

      expect(guard.transaction_open?).to be(false)
      expect(guard.defer { :ran }).to eq(:ran)
    end

    it "runs the block at once, and only once, when Rails refuses the wait" do
      runs = []
      ActiveRecord::Base.transaction do
        allow_any_instance_of(ActiveRecord::Transaction).to receive(:after_rollback).and_raise(ActiveRecord::ActiveRecordError)
        guard.defer { runs << :ran }
        expect(runs).to eq([ :ran ])
      end

      expect(runs).to eq([ :ran ])
    end
  end

  describe ".allow_writes (REQ-18)" do
    it "runs the block in the writing role with writes allowed, inside while_preventing_writes" do
      seen = ActiveRecord::Base.while_preventing_writes do
        guard.allow_writes { [ ActiveRecord::Base.current_role, ActiveRecord::Base.current_preventing_writes ] }
      end

      expect(seen).to eq([ ActiveRecord.writing_role, false ])
    end

    it "leaves the block's own errors to the caller, running it once" do
      runs = 0

      expect { guard.allow_writes { runs += 1; raise ArgumentError, "the block's" } }.to raise_error(ArgumentError, "the block's")
      expect(runs).to eq(1)
    end

    it "runs the block as it is when the role switch fails, without raising" do
      allow(ActiveRecord::Base).to receive(:connected_to).and_raise(ArgumentError, "no such role")

      expect(guard.allow_writes { :ran }).to eq(:ran)
    end
  end

  describe ".lease (REQ-20)", :non_transactional do
    self.use_transactional_tests = false

    let(:pool) { ActiveRecord::Base.connection_pool }

    around do |example|
      was = pool.checkout_timeout
      pool.checkout_timeout = 0.5
      example.run
    ensure
      pool.checkout_timeout = was
    end

    def with_pool_drained
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
      yield
    ensure
      holders&.size&.times { release << true }
      holders&.each(&:join)
    end

    it "holds one connection from the owner's pool for the whole block, then gives it back" do
      ActiveRecord::Base.connection_handler.clear_active_connections!(:all)

      # Even one the block asks to keep: the thread held none before.
      inside = guard.lease(RailsErrorDashboard::ErrorLogsRecord) do
        [ pool.active_connection, RailsErrorDashboard::ErrorLog.count, RailsErrorDashboard::ErrorLogsRecord.lease_connection ]
      end

      expect(inside.first).not_to be_nil
      expect(inside.last).to equal(inside.first)
      expect(pool.active_connection?).to be_falsey
    end

    it "gives up without raising, and without running the block, when the owner's pool has run dry" do
      ran = false
      result = nil

      took = with_pool_drained do
        elapsed { result = guard.lease(RailsErrorDashboard::ErrorLogsRecord) { ran = true } }
      end

      expect(took).to be_between(0.095, 0.15)
      expect(result).to be_nil
      expect(ran).to be(false)
    end

    it "bounds any checkout the block makes to capture_connection_timeout" do
      RailsErrorDashboard.configuration.capture_connection_timeout = 0.2
      took = nil

      with_pool_drained do
        guard.lease do
          took = elapsed do
            expect { pool.with_connection { nil } }.to raise_error(ActiveRecord::ConnectionTimeoutError)
          end
        end
      end

      expect(took).to be_between(0.195, 0.25)
    end

    it "never waits longer than the pool's own checkout_timeout" do
      RailsErrorDashboard.configuration.capture_connection_timeout = 0.4
      pool.checkout_timeout = 0.1
      took = nil

      with_pool_drained do
        guard.lease do
          took = elapsed { expect { pool.with_connection { nil } }.to raise_error(ActiveRecord::ConnectionTimeoutError) }
        end
      end

      expect(took).to be_between(0.095, 0.15)
    end

    it "bounds at 0.1 s when capture_connection_timeout isn't a positive number" do
      RailsErrorDashboard.configuration.capture_connection_timeout = nil
      took = nil

      with_pool_drained do
        guard.lease do
          took = elapsed { expect { pool.with_connection { nil } }.to raise_error(ActiveRecord::ConnectionTimeoutError) }
        end
      end

      expect(took).to be_between(0.095, 0.15)
    end

    it "leaves the block's own errors to the caller" do
      expect {
        guard.lease(RailsErrorDashboard::ErrorLogsRecord) { raise ArgumentError, "the block's" }
      }.to raise_error(ArgumentError, "the block's")
    end

    it "does nothing to a checkout outside it, after it has been used" do
      guard.lease { nil }
      took = nil

      with_pool_drained do
        took = elapsed { expect { pool.with_connection { nil } }.to raise_error(ActiveRecord::ConnectionTimeoutError) }
      end

      expect(took).to be >= 0.495
    end

    it "puts back the bound of a lease around it" do
      RailsErrorDashboard.configuration.capture_connection_timeout = 0.2
      took = nil

      with_pool_drained do
        guard.lease do
          RailsErrorDashboard.configuration.capture_connection_timeout = 0.1
          guard.lease { nil }
          took = elapsed { expect { pool.with_connection { nil } }.to raise_error(ActiveRecord::ConnectionTimeoutError) }
        end
      end

      expect(took).to be_between(0.195, 0.25)
    end

    it "keeps only the bound when the owner's pool can't be found" do
      owner = Class.new { def self.connection_pool = raise(ActiveRecord::ConnectionNotEstablished, "no pool") }

      expect(guard.lease(owner) { :ran }).to eq(:ran)
    end
  end

  describe "configuration" do
    it "isolates capture writes by default, with a 0.1 s connection timeout" do
      config = RailsErrorDashboard::Configuration.new

      expect(config.isolate_capture_writes).to be(true)
      expect(config.capture_connection_timeout).to eq(0.1)
    end

    it "refuses a capture_connection_timeout that isn't a positive number while capture writes are isolated" do
      [ 0, -1, nil, "0.1" ].each do |bad|
        config = RailsErrorDashboard::Configuration.new
        config.capture_connection_timeout = bad

        expect { config.validate! }.to raise_error(RailsErrorDashboard::ConfigurationError, /capture_connection_timeout/)
      end
    end

    it "ignores capture_connection_timeout when capture writes aren't isolated" do
      config = RailsErrorDashboard::Configuration.new
      config.isolate_capture_writes = false
      config.capture_connection_timeout = nil

      expect { config.validate! }.not_to raise_error
    end
  end
end
