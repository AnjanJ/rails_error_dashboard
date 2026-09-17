# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::AnalyticsCacheManager do
  def with_cache(store)
    allow(Rails).to receive(:cache).and_return(store)
    store
  end

  describe ".generation" do
    it "is 0 before anything was cleared" do
      with_cache(ActiveSupport::Cache::MemoryStore.new)

      expect(described_class.generation).to eq(0)
    end

    it "returns 0 instead of raising when the cache is unreachable" do
      cache = with_cache(ActiveSupport::Cache::MemoryStore.new)
      allow(cache).to receive(:read).and_raise(RuntimeError, "connection lost")

      expect(described_class.generation).to eq(0)
    end
  end

  describe ".clear" do
    it "bumps the generation" do
      with_cache(ActiveSupport::Cache::MemoryStore.new)

      expect { described_class.clear }.to change(described_class, :generation)
      expect { described_class.clear }.to change(described_class, :generation).by(1)
    end

    # A generation bump is O(1) on every store. delete_matched is a SCAN of the
    # HOST app's Redis keyspace and NotImplementedError on memcached.
    it "never sweeps the keyspace" do
      cache = with_cache(ActiveSupport::Cache::MemoryStore.new)
      allow(cache).to receive(:delete_matched).and_call_original

      described_class.clear

      expect(cache).not_to have_received(:delete_matched)
    end

    # increment is unimplemented, nil-returning or INCRBY-on-a-serialized-entry
    # depending on the store; a plain write works on all of them.
    it "does not depend on the store implementing increment" do
      cache = with_cache(ActiveSupport::Cache::MemoryStore.new)
      allow(cache).to receive(:increment).and_raise(NotImplementedError)

      expect { described_class.clear }.to change(described_class, :generation)
      expect { described_class.clear }.to change(described_class, :generation)
    end

    it "does not restart at a low number when the store evicted the generation key" do
      cache = with_cache(ActiveSupport::Cache::MemoryStore.new)
      described_class.clear
      before_eviction = described_class.generation
      cache.delete(described_class::GENERATION_KEY)

      described_class.clear

      expect(described_class.generation).to be >= before_eviction
    end

    it "does not raise on a null store, where nothing is cached anyway" do
      with_cache(ActiveSupport::Cache::NullStore.new)

      expect { described_class.clear }.not_to raise_error
      expect(described_class.generation).to eq(0)
    end

    it "does not raise when the cache raises" do
      cache = with_cache(ActiveSupport::Cache::MemoryStore.new)
      allow(cache).to receive(:write).and_raise(RuntimeError, "connection lost")

      expect { described_class.clear }.not_to raise_error
    end
  end

  describe "what invalidates the dashboard caches" do
    let(:cache) { with_cache(ActiveSupport::Cache::MemoryStore.new) }
    let!(:application) { create(:application) }

    before { cache }

    it "is not a plain save of an error: captures rely on the TTL" do
      allow(described_class).to receive(:clear).and_call_original
      allow(cache).to receive(:delete_matched).and_call_original

      error = create(:error_log, application: application)
      error.update!(occurrence_count: 5)
      error.destroy!

      expect(described_class).not_to have_received(:clear)
      expect(cache).not_to have_received(:delete_matched)
    end

    it "serves DashboardStats from the cache inside the TTL even when a row changed" do
      error = create(:error_log, application: application, occurred_at: 1.hour.ago)
      first = RailsErrorDashboard::Queries::DashboardStats.call

      error.update!(occurrence_count: 50, updated_at: 1.minute.from_now)
      second = RailsErrorDashboard::Queries::DashboardStats.call

      expect(second[:total_today]).to eq(first[:total_today])
    end

    it "recomputes DashboardStats after clear" do
      error = create(:error_log, application: application, occurred_at: 1.hour.ago)
      first = RailsErrorDashboard::Queries::DashboardStats.call

      error.update!(occurrence_count: 50)
      described_class.clear

      expect(RailsErrorDashboard::Queries::DashboardStats.call[:total_today]).to eq(first[:total_today] + 49)
    end

    it "recomputes AnalyticsStats after clear, and not before" do
      create(:error_log, application: application, occurred_at: 1.hour.ago)
      first = RailsErrorDashboard::Queries::AnalyticsStats.call(30)

      create(:error_log, application: application, occurred_at: 1.hour.ago)
      expect(RailsErrorDashboard::Queries::AnalyticsStats.call(30)[:error_stats]).to eq(first[:error_stats])

      described_class.clear
      expect(RailsErrorDashboard::Queries::AnalyticsStats.call(30)[:error_stats]).not_to eq(first[:error_stats])
    end

    it "builds a cache key without querying the database" do
      queries = 0
      counter = ->(*, payload) { queries += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        RailsErrorDashboard::Queries::DashboardStats.new.cache_key
        RailsErrorDashboard::Queries::AnalyticsStats.new(30).cache_key
      end

      expect(queries).to eq(0)
    end
  end

  describe "user actions invalidate immediately" do
    let!(:application) { create(:application) }
    let(:error) { create(:error_log, application: application) }

    before { with_cache(ActiveSupport::Cache::MemoryStore.new) }

    {
      "ResolveError" => ->(e) { RailsErrorDashboard::Commands::ResolveError.call(e.id, resolved_by_name: "qa") },
      "UpdateErrorStatus" => ->(e) { RailsErrorDashboard::Commands::UpdateErrorStatus.call(e.id, status: "in_progress") },
      "BatchResolveErrors" => ->(e) { RailsErrorDashboard::Commands::BatchResolveErrors.call([ e.id ]) },
      "BatchDeleteErrors" => ->(e) { RailsErrorDashboard::Commands::BatchDeleteErrors.call([ e.id ]) },
      "BatchMuteErrors" => ->(e) { RailsErrorDashboard::Commands::BatchMuteErrors.call([ e.id ]) },
      "BatchUnmuteErrors" => ->(e) { RailsErrorDashboard::Commands::BatchUnmuteErrors.call([ e.id ]) },
      "MuteError" => ->(e) { RailsErrorDashboard::Commands::MuteError.call(e.id) },
      "UnmuteError" => ->(e) { RailsErrorDashboard::Commands::UnmuteError.call(e.id) }
    }.each do |name, action|
      it "#{name} bumps the generation" do
        error

        expect { action.call(error) }.to change(described_class, :generation)
      end
    end

    it "the retention job bumps the generation" do
      RailsErrorDashboard.configuration.retention_days = 30
      create(:error_log, application: application, occurred_at: 90.days.ago)

      expect { RailsErrorDashboard::RetentionCleanupJob.perform_now }.to change(described_class, :generation)
    ensure
      RailsErrorDashboard.reset_configuration!
    end

    it "shows a resolve on the stats cards straight away" do
      error
      before_resolve = RailsErrorDashboard::Queries::DashboardStats.call[:unresolved]

      RailsErrorDashboard::Commands::ResolveError.call(error.id, resolved_by_name: "qa")

      expect(RailsErrorDashboard::Queries::DashboardStats.call[:unresolved]).to eq(before_resolve - 1)
    end
  end
end
