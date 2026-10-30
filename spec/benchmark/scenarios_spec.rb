# frozen_string_literal: true

require "rails_helper"
require_relative "../../benchmark/timer"
require_relative "../../benchmark/scenarios"

# Each scenario runs here for a handful of iterations, to prove it times the
# code path its name claims. The numbers themselves come from bin/benchmark.
RSpec.describe RedBenchmark::Scenarios do
  let(:timer) { RedBenchmark::Timer.new(rounds: 1, iterations: 3, warmup: 1) }

  def scenario(name)
    described_class.all.find { |s| s.name == name } or raise "no scenario named #{name.inspect}"
  end

  after do
    RailsErrorDashboard::Services::StormProtection::Gate.reset!
    RailsErrorDashboard::Services::BreadcrumbCollector.clear_buffer
  end

  it "gates the four budgets and reports the four paths 0.17 decisions wait on (overhead-benchmark/REQ-2, overhead-benchmark/REQ-3)" do
    budgets = described_class.all.to_h { |s| [ s.name, s.budget ] }

    expect(budgets).to eq(
      "Capture, async (installer default)" => 5e-3,
      "Storm check, calm" => 15e-6,
      "Storm check, shedding" => 15e-6,
      "Storm check, breaker open" => 15e-6,
      "Breadcrumb callback" => 1e-5,
      "Health snapshot" => 1e-3,
      "Capture, sync" => nil,
      "Message filtering, 400 characters" => nil,
      "Request params, 1 MB body" => nil,
      "Reopen collision fallback" => nil
    )
  end

  it "times capture through the middleware and the subscriber, ending in an enqueue (overhead-benchmark/REQ-2)" do
    reporter = Rails.error.instance_variable_get(:@subscribers).find { |s| s.is_a?(RailsErrorDashboard::ErrorReporter) }
    expect(reporter).to be_present, "RED's Rails.error subscriber is not registered"
    allow(reporter).to receive(:report).and_call_original

    result = scenario("Capture, async (installer default)").run.call(timer)

    expect(reporter).to have_received(:report).at_least(4).times # 1 warm-up + 3 timed
    expect(RailsErrorDashboard::AsyncErrorLoggingJob).to have_been_enqueued.at_least(4).times
    expect(result.budget).to eq(5e-3)
  end

  it "times the storm check with the breaker closed (overhead-benchmark/REQ-2)" do
    gate = RailsErrorDashboard::Services::StormProtection::Gate
    states = []
    allow(gate).to receive(:admit!).and_wrap_original { |original, *args| original.call(*args).tap { states << gate.state } }

    scenario("Storm check, calm").run.call(timer)

    expect(states.size).to be >= 4
    expect(states.uniq).to eq([ :closed ])
  end

  it "times the storm check while shedding, which decides and counts (overhead-benchmark/REQ-2)" do
    gate = RailsErrorDashboard::Services::StormProtection::Gate
    states = []
    decisions = []
    allow(gate).to receive(:admit!).and_wrap_original do |original, *args|
      original.call(*args).tap do |decision|
        states << gate.state
        decisions << decision
      end
    end

    scenario("Storm check, shedding").run.call(timer)

    expect(states.last(4).uniq).to eq([ :shedding ])
    expect(decisions.last(4)).to include(:count_only)
  end

  it "times the storm check with the breaker open (overhead-benchmark/REQ-2)" do
    gate = RailsErrorDashboard::Services::StormProtection::Gate
    states = []
    allow(gate).to receive(:admit!).and_wrap_original { |original, *args| original.call(*args).tap { states << gate.state } }

    scenario("Storm check, breaker open").run.call(timer)

    expect(states.last(4).uniq).to eq([ :open ])
  end

  it "times RED's own breadcrumb callback, which records a crumb (overhead-benchmark/REQ-2)" do
    allow(RailsErrorDashboard::Services::BreadcrumbCollector).to receive(:add).and_call_original

    scenario("Breadcrumb callback").run.call(timer)

    expect(RailsErrorDashboard::Services::BreadcrumbCollector).to have_received(:add).with("sql", anything, any_args).at_least(4).times
  end

  it "times one health snapshot (overhead-benchmark/REQ-2)" do
    allow(RailsErrorDashboard::Services::SystemHealthSnapshot).to receive(:capture).and_call_original

    scenario("Health snapshot").run.call(timer)

    expect(RailsErrorDashboard::Services::SystemHealthSnapshot).to have_received(:capture).at_least(4).times
  end

  it "times sync capture, which writes the error (overhead-benchmark/REQ-3)" do
    scenario("Capture, sync").run.call(timer)

    error = RailsErrorDashboard::ErrorLog.find_by(error_type: "RedBenchmark::BenchmarkError")
    expect(error).to be_present
    expect(error.occurrence_count).to be >= 4
  end

  it "times message filtering on a message under 500 characters (overhead-benchmark/REQ-3)" do
    filter = RailsErrorDashboard::Services::SensitiveDataFilter
    messages = []
    allow(filter).to receive(:filter_message).and_wrap_original { |original, f, message| messages << message; original.call(f, message) }

    scenario("Message filtering, 400 characters").run.call(timer)

    expect(messages.size).to be >= 4
    expect(messages.map(&:length).uniq).to eq([ 400 ])
  end

  it "times fitting a 1 MB body into the params limit (overhead-benchmark/REQ-3)" do
    sizes = []
    allow(RailsErrorDashboard::Services::CaptureLimits).to receive(:request_params).and_wrap_original do |original, params|
      sizes << params.bytesize
      original.call(params).tap { |fitted| expect(fitted.bytesize).to be <= RailsErrorDashboard::Services::CaptureLimits::REQUEST_PARAMS_LIMIT }
    end

    scenario("Request params, 1 MB body").run.call(timer)

    expect(sizes.size).to be >= 4
    expect(sizes.uniq.first).to be >= 1_000_000
  end

  it "times a reopen that collides and falls back to the row the index names (overhead-benchmark/REQ-3)" do
    # Keyed on the adapter, not the index: a renamed index has to fail here on
    # SQLite and PostgreSQL, not skip. bin/benchmark itself only runs on SQLite.
    skip "MySQL has no partial indexes, so a reopen cannot collide" if RailsErrorDashboard::ErrorLog.connection.adapter_name.match?(/mysql|trilogy/i)

    claimed = 0
    allow_any_instance_of(RailsErrorDashboard::Commands::FindOrIncrementError)
      .to receive(:claim_conflicting_row).and_wrap_original { |original, **kwargs| original.call(**kwargs).tap { |row| claimed += 1 if row } }

    scenario("Reopen collision fallback").run.call(timer)

    expect(claimed).to be >= 4
  end

  it "refuses to time a reopen that cannot collide, rather than report a plain reopen as the fallback (overhead-benchmark/REQ-3)" do
    allow(RailsErrorDashboard::ErrorLog.connection).to receive(:index_name_exists?).and_return(false)

    expect { scenario("Reopen collision fallback").run.call(timer) }
      .to raise_error(/index_error_logs_on_group_identity/)
  end
end
