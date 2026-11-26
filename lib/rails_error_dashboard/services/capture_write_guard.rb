# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Keeps a capture's write apart from the host's own database state
    # (hardening-1-0-rc2, REQ-17 to REQ-20 and REQ-51 to REQ-53; spike S1,
    # .shipkit/research/host-conditions-spike.md). Commands::LogError uses its
    # three entry points while config.isolate_capture_writes is on:
    #
    # - defer: inside an open host transaction, a capture waits for it, and for
    #   every transaction around it, to end, committed or rolled back. A rollback
    #   can no longer take the capture with it. At most MAX_WAITING wait.
    # - allow_writes: the write runs in the writing role with writes allowed, so
    #   while_preventing_writes or a reading role no longer refuses it.
    # - lease: every connection checkout the thread makes during the step waits
    #   at most capture_connection_timeout, and the step holds one connection
    #   of RED's pool throughout. A pool run dry costs one short wait, not the
    #   pool's checkout_timeout, and a step that needs no connection (an
    #   enqueue to Redis) waits for none.
    #
    # None of them raises an error of its own. Internal: not public API.
    class CaptureWriteGuard
      # Captures waiting on one thread's open transaction. Further ones are
      # dropped (REQ-52): each holds its exception and context until the
      # transaction ends.
      MAX_WAITING = 100

      # capture_connection_timeout's default, used if the setting isn't a
      # positive number (Configuration#validate! refuses that at boot).
      DEFAULT_TIMEOUT = 0.1

      BUDGET_KEY = :rails_error_dashboard_checkout_budget
      WAITING_KEY = :rails_error_dashboard_waiting_captures
      DROPPING_KEY = :rails_error_dashboard_dropping_captures

      # Caps the wait of any checkout made while a lease is running on this
      # thread (or fiber, under fiber isolation, as Rails keys its leases).
      # Outside a lease it reads one value and calls Rails' own checkout. It is
      # prepended the first time a lease runs, so with isolate_capture_writes
      # off it never is.
      module CheckoutBudget
        def checkout(checkout_timeout = @checkout_timeout)
          budget = ActiveSupport::IsolatedExecutionState[BUDGET_KEY]
          return super unless budget

          super(checkout_timeout.is_a?(Numeric) && checkout_timeout < budget ? checkout_timeout : budget)
        end
      end

      # One capture waiting for the host's transactions to end.
      class Waiter
        def initialize(block)
          @block = block
          @done = false
        end

        # Rails runs exactly one of the two when the transaction ends. When a
        # savepoint commits, it hands both to the transaction around it.
        def wait_for(transaction)
          resume = proc { CaptureWriteGuard.resume(self) }
          transaction.after_commit(&resume)
          transaction.after_rollback(&resume)
        end

        def run
          return if @done

          @done = true
          CaptureWriteGuard.waiting.delete(self)
          CaptureWriteGuard.as_reporter(@block)
        end
      end

      class << self
        # Whether the host has a transaction open on this thread's connection.
        # Checks out no connection. A transaction Rails opens joinable: false
        # (a test's) doesn't count, as Rails itself doesn't offer it callbacks.
        def transaction_open?
          !open_transaction.nil?
        end

        # Runs the block now, or, inside an open host transaction, once it and
        # every transaction around it have ended (REQ-17, REQ-51). Returns the
        # block's value when it ran now, nil when it waits or was dropped. Run
        # now, its errors are the caller's; run later, inside the host's commit
        # or rollback, nothing it raises reaches the host.
        def defer(&block)
          transaction = open_transaction
          return yield unless transaction

          hold(block, transaction)
          nil
        end

        # Runs the block in the writing role with writes allowed (REQ-18). In a
        # reading role that sends the write to the writing database. The
        # block's errors are the caller's; if the role switch itself fails, the
        # block runs as it is.
        def allow_writes
          entered = false
          ActiveRecord::Base.connected_to(role: ActiveRecord.writing_role, prevent_writes: false) do
            entered = true
            yield
          end
        rescue StandardError => e
          raise if entered

          RailsErrorDashboard::Logger.error("[RailsErrorDashboard] Capture could not switch to the writing role (#{e.class})")
          yield
        end

        # Runs the block with every connection checkout on this thread waiting
        # at most capture_connection_timeout, holding one connection of
        # owner's pool throughout when an owner is given (REQ-20). Gives up,
        # returning nil without running the block, when that connection can't
        # be had in time. A checkout inside the block that runs out of time
        # raises ActiveRecord::ConnectionTimeoutError to the block's caller.
        def lease(owner = nil)
          install_checkout_budget
          state = ActiveSupport::IsolatedExecutionState
          outer = state[BUDGET_KEY]
          state[BUDGET_KEY] = connection_timeout
          begin
            pool = pool_of(owner)
            return yield unless pool

            held = false
            begin
              pool.with_connection(prevent_permanent_checkout: true) do
                held = true
                yield
              end
            rescue StandardError => e
              raise if held

              RailsErrorDashboard::Logger.error(
                "[RailsErrorDashboard] Capture gave up: no database connection within #{connection_timeout}s (#{e.class})"
              )
              nil
            end
          ensure
            state[BUDGET_KEY] = outer
          end
        end

        # A waiting capture's transaction has ended. If one around it is still
        # open, it waits for that one too; otherwise it runs now. Called from
        # inside the host's commit or rollback, so nothing may escape.
        def resume(waiter)
          transaction = open_transaction
          transaction ? waiter.wait_for(transaction) : waiter.run
        rescue StandardError, ScriptError => e
          RailsErrorDashboard::Logger.error("[RailsErrorDashboard] Capture after the host's transaction failed (#{e.class})")
          nil
        end

        # Captures waiting on this thread. Keys are weak: a waiter whose
        # transaction never ran its callbacks (a host after_commit callback
        # raised first) is collected and stops counting, where a counter would
        # stay full and drop every later capture on the thread.
        def waiting
          ActiveSupport::IsolatedExecutionState[WAITING_KEY] ||= ObjectSpace::WeakMap.new
        end

        # Runs a capture that waited as ErrorReporter runs one: with RED's
        # recursion guard set, so a failure inside it isn't captured again.
        def as_reporter(block)
          was = Thread.current[:rails_error_dashboard_logging]
          Thread.current[:rails_error_dashboard_logging] = true
          block.call
        ensure
          Thread.current[:rails_error_dashboard_logging] = was
        end

        private

        def open_transaction
          transaction = ActiveRecord::Base.current_transaction
          transaction if transaction.open?
        rescue StandardError => e
          RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] Transaction check failed (#{e.class})")
          nil
        end

        def hold(block, transaction)
          state = ActiveSupport::IsolatedExecutionState
          pending = waiting
          if pending.size >= MAX_WAITING
            unless state[DROPPING_KEY]
              state[DROPPING_KEY] = true
              RailsErrorDashboard::Logger.error(
                "[RailsErrorDashboard] #{MAX_WAITING} captures already wait for the host's transaction to end; dropping further ones"
              )
            end
            return
          end

          state[DROPPING_KEY] = nil
          waiter = Waiter.new(block)
          pending[waiter] = true
          begin
            waiter.wait_for(transaction)
          rescue StandardError => e
            # Rails refused the wait. Write now, as rc.1 did; a callback that
            # was registered finds the waiter done.
            RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] Could not wait for the host's transaction (#{e.class})")
            waiter.run
          end
        end

        def pool_of(owner)
          owner&.connection_pool
        rescue StandardError => e
          RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] No connection pool for #{owner} (#{e.class})")
          nil
        end

        def connection_timeout
          value = RailsErrorDashboard.configuration.capture_connection_timeout
          value.is_a?(Numeric) && value.positive? ? value : DEFAULT_TIMEOUT
        end

        def install_checkout_budget
          return if @checkout_budget_installed

          ActiveRecord::ConnectionAdapters::ConnectionPool.prepend(CheckoutBudget)
          @checkout_budget_installed = true
        end
      end
    end
  end
end
