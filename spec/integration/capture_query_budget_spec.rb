# frozen_string_literal: true

require "rails_helper"

# Capturing an error runs inside the HOST app's request thread (sync mode) or
# its job worker. Whatever the dashboard does as a side effect of a capture --
# cache invalidation, live stats, spike detection -- must therefore cost a
# small, bounded amount of work that does not grow with the number of distinct
# error types already stored. This spec is the guard for that budget.
RSpec.describe "Capture query budget" do
  let!(:application) { create(:application) }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:exception) do
    raise ArgumentError, "budget probe"
  rescue => e
    e
  end

  before do
    RailsErrorDashboard.configure do |config|
      config.async_logging = false
      config.sampling_rate = 1.0
    end

    allow(Rails).to receive(:cache).and_return(cache)

    # 200 distinct error types, a handful of them with baselines: the shape
    # that made the per-(type, platform) baseline loop expensive.
    200.times do |i|
      create(:error_log, application: application, error_type: "BudgetError#{i}", platform: "API",
             occurred_at: 2.hours.ago)
    end
    5.times do |i|
      create(:error_baseline, error_type: "BudgetError#{i}", platform: "API",
             baseline_type: "hourly", period_start: 2.weeks.ago, period_end: 1.hour.ago)
    end

    # Live updates on: the stats broadcast is part of the cost being measured.
    allow(RailsErrorDashboard::Services::ErrorBroadcaster).to receive(:available?).and_return(true)
    stub_const("Turbo::StreamsChannel", Class.new) unless defined?(Turbo::StreamsChannel)
    %i[broadcast_prepend_to broadcast_replace_to].each do |name|
      allow(Turbo::StreamsChannel).to receive(name)
    end
  end

  after { RailsErrorDashboard.reset_configuration! }

  def count_queries
    statements = []
    counter = lambda do |_name, _start, _finish, _id, payload|
      next if %w[SCHEMA TRANSACTION].include?(payload[:name])
      next if payload[:sql].match?(/\A\s*(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT|BEGIN|COMMIT)/i)

      statements << payload[:sql]
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    statements
  end

  it "captures a recurrence of a known error in fewer than 40 queries" do
    pending "3663 queries at 39f281a; goes green once caches, broadcast and spike detection are bounded"

    # First capture creates the group; the measured one takes the update path.
    RailsErrorDashboard::Commands::LogError.call(exception, {})

    # Worst case: the stats cache is cold (it expires every minute), so this
    # capture pays for the whole stats broadcast, spike detection included,
    # and it is the one capture in the window that is allowed to broadcast.
    cache.clear
    RailsErrorDashboard::Services::ErrorBroadcaster.reset_throttle!

    statements = count_queries { RailsErrorDashboard::Commands::LogError.call(exception, {}) }

    expect(statements.size).to be < 40,
      "capture issued #{statements.size} queries:\n" + statements.first(60).join("\n")
  end

  it "never sweeps the host's cache keyspace during a capture" do
    RailsErrorDashboard::Commands::LogError.call(exception, {})
    allow(cache).to receive(:delete_matched).and_call_original

    RailsErrorDashboard::Commands::LogError.call(exception, {})

    expect(cache).not_to have_received(:delete_matched)
  end
end
