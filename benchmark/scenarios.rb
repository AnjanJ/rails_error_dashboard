# frozen_string_literal: true

require "json"
require "rack/mock"

module RedBenchmark
  class BenchmarkError < StandardError; end

  # One measurement. `run` takes a Timer and returns its Result; `iterations`
  # is how many timed calls bin/benchmark gives it per round (the specs pass
  # their own small timer). A nil budget is a row that is reported, not gated.
  Scenario = Struct.new(:name, :budget, :iterations, :run, keyword_init: true)

  # What bin/benchmark measures. The budgets are the host-app-safety skill's
  # (.claude/skills/host-app-safety/SKILL.md); the reported-only rows are the
  # paths whose 0.17.0 decisions say they would reverse on these numbers.
  module Scenarios
    # High enough that the benchmark's own rate of identical errors never
    # moves the breaker or the per-fingerprint cap: the capture rows time the
    # full-fidelity path, and the storm rows time the gate on its own.
    CALM_STORM = {
      enable_storm_protection: true,
      storm_shedding_threshold_per_second: 1_000_000_000,
      storm_open_threshold_per_second: 1_000_000_000,
      storm_fingerprint_full_per_minute: 1_000_000_000
    }.freeze

    # On the CI job's runner, which is what a host's servers look like: about
    # 2.7x slower than an M3 Max. The design records why it isn't 5 µs.
    STORM_BUDGET = 15e-6

    # Calls per sample for the microsecond-scale rows (see Timer#measure).
    BATCH = 100

    # Real apps raise from deep stacks, and RED's backtrace handling scales
    # with depth, so every exception here is raised 60 frames down.
    STACK_DEPTH = 60

    GROUP_IDENTITY_INDEX = "index_error_logs_on_group_identity"

    # 400 characters, with the shapes the message filter rewrites.
    MESSAGE = ("PG::UniqueViolation: duplicate key value violates unique constraint " \
      "\"index_users_on_email\" DETAIL: Key (email)=(ada@example.com) already exists. " \
      "retry with password=hunter2 api_key=sk_live_51H8abc token: Bearer eyJhbGciOiJIUzI1NiJ9.e30 " \
      "while charging order_id=42 for customer_id=7 ").ljust(400, ".").freeze

    module_function

    def all
      [
        capture("Capture, async (installer default)", async: true, budget: 5e-3, iterations: 1_000),
        storm_calm,
        storm_shedding,
        storm_open,
        breadcrumb,
        health_snapshot,
        capture("Capture, sync", async: false, budget: nil, iterations: 200),
        message_filtering,
        request_params,
        reopen_collision
      ]
    end

    # The same failing request with and without RED in front of it. The
    # difference is what RED adds: ErrorCatcher, the Rails.error subscriber,
    # the storm gate, and then the enqueue (async) or the writes (sync).
    def capture(name, async:, budget:, iterations:)
      Scenario.new(name: name, budget: budget, iterations: iterations, run: lambda do |timer|
        with_config(**CALM_STORM, async_logging: async) do
          catcher = RailsErrorDashboard::Middleware::ErrorCatcher.new(RAISING_APP)
          env = request_env
          timer.measure_difference(name, budget: budget,
            with: -> { serve(catcher, env) },
            without: -> { serve(RAISING_APP, env) })
        end
      end)
    end

    def storm_calm
      Scenario.new(name: "Storm check, calm", budget: STORM_BUDGET, iterations: 1_000, run: lambda do |timer|
        with_config(**CALM_STORM) do
          exception = raised_exception
          timer.measure("Storm check, calm", budget: STORM_BUDGET, batch: BATCH) { gate.admit!(exception, {}) }
        end
      end)
    end

    # The gate's worst case: the bucket decision the calm row makes, then the
    # count the open row makes. A breaker only sheds once a bucket rolls, ten
    # seconds in, so the roll is brought forward rather than waited for. The
    # open threshold is out of reach, or the timed calls would trip the breaker
    # straight through this state.
    def storm_shedding
      Scenario.new(name: "Storm check, shedding", budget: STORM_BUDGET, iterations: 1_000, run: lambda do |timer|
        with_config(enable_storm_protection: true, storm_open_threshold_per_second: 1_000_000_000) do
          exception = raised_exception
          breaker = gate.breaker
          bucket = RailsErrorDashboard::Services::StormProtection::CircuitBreaker::BUCKET_SECONDS
          (2 * bucket * RailsErrorDashboard.configuration.storm_shedding_threshold_per_second).times { gate.admit!(exception, {}) }
          breaker.instance_variable_set(:@bucket_start, breaker.instance_variable_get(:@bucket_start) - bucket)
          raise "the breaker did not start shedding (state: #{gate.state})" unless gate.state == :shedding

          timer.measure("Storm check, shedding", budget: STORM_BUDGET, batch: BATCH) { gate.admit!(exception, {}) }
        end
      end)
    end

    # The defaults, driven past the open threshold first: every timed call is
    # the count-only path a real storm takes. The breaker trips open mid-bucket
    # once one bucket holds open_threshold * BUCKET_SECONDS calls.
    def storm_open
      Scenario.new(name: "Storm check, breaker open", budget: STORM_BUDGET, iterations: 1_000, run: lambda do |timer|
        with_config(enable_storm_protection: true) do
          exception = raised_exception
          trip = RailsErrorDashboard.configuration.storm_open_threshold_per_second *
            RailsErrorDashboard::Services::StormProtection::CircuitBreaker::BUCKET_SECONDS
          (trip + 1).times { gate.admit!(exception, {}) }
          raise "the breaker did not open (state: #{gate.state})" unless gate.state == :open

          timer.measure("Storm check, breaker open", budget: STORM_BUDGET, batch: BATCH) { gate.admit!(exception, {}) }
        end
      end)
    end

    # The body of RED's sql.active_record subscriber, which is what runs for
    # every query while breadcrumbs are on.
    def breadcrumb
      Scenario.new(name: "Breadcrumb callback", budget: 1e-5, iterations: 1_000, run: lambda do |timer|
        with_config(enable_breadcrumbs: true) do
          collector = RailsErrorDashboard::Services::BreadcrumbCollector
          subscriber = RailsErrorDashboard::Subscribers::BreadcrumbSubscriber
          collector.init_buffer
          payload = { sql: 'SELECT "orders".* FROM "orders" WHERE "orders"."id" = ? LIMIT ?', name: "Order Load", binds: [] }
          started = Time.now
          finished = started + 0.0004
          timer.measure("Breadcrumb callback", budget: 1e-5, batch: BATCH) do
            event = ActiveSupport::Notifications::Event.new("sql.active_record", started, finished, "1", payload)
            subscriber.send(:handle_sql, event)
          end
        ensure
          collector.clear_buffer
        end
      end)
    end

    def health_snapshot
      Scenario.new(name: "Health snapshot", budget: 1e-3, iterations: 1_000, run: lambda do |timer|
        timer.measure("Health snapshot", budget: 1e-3, batch: 10) { RailsErrorDashboard::Services::SystemHealthSnapshot.capture }
      end)
    end

    def message_filtering
      Scenario.new(name: "Message filtering, 400 characters", budget: nil, iterations: 1_000, run: lambda do |timer|
        with_config(filter_sensitive_data: true) do
          filter = RailsErrorDashboard::Services::SensitiveDataFilter
          timer.measure("Message filtering, 400 characters") { filter.filter_attributes(message: MESSAGE) }
        end
      end)
    end

    def request_params
      Scenario.new(name: "Request params, 1 MB body", budget: nil, iterations: 50, run: lambda do |timer|
        body = { order: { id: 42, lines: Array.new(50) { |i| { sku: "SKU-#{i}", qty: i } } },
                 attachment: "x" * 1_000_000 }.to_json
        timer.measure("Request params, 1 MB body") { RailsErrorDashboard::Services::CaptureLimits.request_params(body) }
      end)
    end

    # An old unresolved row holds the group identity, and a resolved row with
    # the same hash is found instead (the unresolved lookup only looks back
    # 24 hours). Reopening it violates the unique index, and the capture is
    # counted on the row the index names. The reopen rolls back, so every
    # iteration takes the same path.
    #
    # Only where that index exists: MySQL has no partial indexes, so a reopen
    # there never collides. bin/benchmark always runs on SQLite.
    def reopen_collision
      Scenario.new(name: "Reopen collision fallback", budget: nil, iterations: 200, run: lambda do |timer|
        unless RailsErrorDashboard::ErrorLog.connection.index_name_exists?(RailsErrorDashboard::ErrorLog.table_name, GROUP_IDENTITY_INDEX)
          raise "the reopen collision needs #{GROUP_IDENTITY_INDEX}, and this database does not have it"
        end

        error_hash = "red-benchmark-reopen-collision"
        application = RailsErrorDashboard::Application.find_or_create_by!(name: "red-benchmark")
        attributes = { application_id: application.id, environment: "production", occurred_at: Time.current }
        [ { resolved: false, status: "new" }, { resolved: true, status: "resolved" } ].each do |state|
          row = RailsErrorDashboard::ErrorLog.create!(
            application: application, error_type: BenchmarkError.name, message: "collision",
            error_hash: error_hash, environment: "production", occurred_at: 2.days.ago, **state
          )
          row.update_columns(group_window: nil, error_hash: error_hash)
        end

        timer.measure("Reopen collision fallback") do
          RailsErrorDashboard::Commands::FindOrIncrementError.call(error_hash, attributes)
        end
      end)
    end

    RAISING_APP = ->(_env) { Scenarios.raise_from(STACK_DEPTH) }

    def raise_from(depth)
      depth.zero? ? raise(BenchmarkError, "Order 42 could not be charged") : raise_from(depth - 1)
    end

    def raised_exception
      raise_from(STACK_DEPTH)
    rescue BenchmarkError => e
      e
    end

    # The host app's own rescue: the response it would render is not the
    # benchmark's concern, only the time to get there.
    def serve(app, env)
      app.call(env.dup)
    rescue BenchmarkError
      nil
    end

    def request_env
      Rack::MockRequest.env_for(
        "https://shop.example/orders/42/charge?coupon=SPRING",
        "REQUEST_METHOD" => "POST",
        "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Safari/605.1.15",
        "REMOTE_ADDR" => "203.0.113.7",
        input: "card_token=tok_visa&amount=4200"
      )
    end

    def gate
      RailsErrorDashboard::Services::StormProtection::Gate
    end

    # Sets the given options for the block and puts back what was there,
    # with the storm gate fresh on both sides.
    def with_config(**overrides)
      config = RailsErrorDashboard.configuration
      saved = overrides.keys.to_h { |key| [ key, config.public_send(key) ] }
      overrides.each { |key, value| config.public_send(:"#{key}=", value) }
      gate.reset!
      yield
    ensure
      saved&.each { |key, value| config.public_send(:"#{key}=", value) }
      gate.reset!
    end
  end
end
