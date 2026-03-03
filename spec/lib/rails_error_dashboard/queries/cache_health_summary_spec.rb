# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::CacheHealthSummary do
  def breadcrumbs_json(*crumbs)
    crumbs.to_json
  end

  def cache_read_crumb(key, hit:, duration: 0.5)
    { "c" => "cache", "m" => "cache read: #{key}", "d" => duration, "meta" => { "hit" => hit } }
  end

  def cache_write_crumb(key, duration: 0.3)
    { "c" => "cache", "m" => "cache write: #{key}", "d" => duration }
  end

  def sql_crumb(message)
    { "c" => "sql", "m" => message, "d" => 1.2 }
  end

  describe ".call" do
    it "returns empty entries when no errors exist" do
      result = described_class.call(30)
      expect(result[:entries]).to eq([])
    end

    it "returns empty entries when errors have no breadcrumbs" do
      create(:error_log, breadcrumbs: nil, occurred_at: 1.day.ago)
      result = described_class.call(30)
      expect(result[:entries]).to eq([])
    end

    it "returns empty entries when no cache breadcrumbs exist" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(sql_crumb("SELECT 1")),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:entries]).to eq([])
    end

    it "extracts cache stats from breadcrumbs" do
      error = create(:error_log,
        breadcrumbs: breadcrumbs_json(
          cache_read_crumb("users/1", hit: true, duration: 1.0),
          cache_read_crumb("users/2", hit: false, duration: 2.0),
          cache_write_crumb("users/3", duration: 0.5)
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:entries].size).to eq(1)

      entry = result[:entries].first
      expect(entry[:error_id]).to eq(error.id)
      expect(entry[:reads]).to eq(2)
      expect(entry[:writes]).to eq(1)
      expect(entry[:hits]).to eq(1)
      expect(entry[:misses]).to eq(1)
      expect(entry[:hit_rate]).to eq(50.0)
    end

    it "collects per-error results (not grouped)" do
      3.times do
        create(:error_log,
          breadcrumbs: breadcrumbs_json(
            cache_read_crumb("key", hit: true)
          ),
          occurred_at: 1.day.ago)
      end

      result = described_class.call(30)
      expect(result[:entries].size).to eq(3)
    end

    it "sorts by hit_rate ascending (worst first), nil last" do
      error_bad = create(:error_log,
        breadcrumbs: breadcrumbs_json(
          cache_read_crumb("a", hit: false),
          cache_read_crumb("b", hit: false)
        ),
        occurred_at: 1.day.ago)

      error_good = create(:error_log,
        breadcrumbs: breadcrumbs_json(
          cache_read_crumb("c", hit: true),
          cache_read_crumb("d", hit: true)
        ),
        occurred_at: 1.day.ago)

      error_nil = create(:error_log,
        breadcrumbs: breadcrumbs_json(
          cache_write_crumb("e")
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      ids = result[:entries].map { |e| e[:error_id] }
      expect(ids).to eq([ error_bad.id, error_good.id, error_nil.id ])
    end

    it "respects time range" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(cache_read_crumb("old", hit: true)),
        occurred_at: 40.days.ago)

      create(:error_log,
        breadcrumbs: breadcrumbs_json(cache_read_crumb("recent", hit: true)),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:entries].size).to eq(1)
      expect(result[:entries].first[:hit_rate]).to eq(100.0)
    end

    it "filters by application_id" do
      app1 = create(:application, name: "App1")
      app2 = create(:application, name: "App2")

      create(:error_log,
        application: app1,
        breadcrumbs: breadcrumbs_json(cache_read_crumb("a", hit: true)),
        occurred_at: 1.day.ago)

      create(:error_log,
        application: app2,
        breadcrumbs: breadcrumbs_json(cache_read_crumb("b", hit: false)),
        occurred_at: 1.day.ago)

      result = described_class.call(30, application_id: app1.id)
      expect(result[:entries].size).to eq(1)
      expect(result[:entries].first[:hit_rate]).to eq(100.0)
    end

    it "handles malformed JSON breadcrumbs gracefully" do
      create(:error_log,
        breadcrumbs: "not valid json {{{",
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:entries]).to eq([])
    end

    it "tracks slowest operation" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          cache_read_crumb("fast", hit: true, duration: 0.1),
          cache_read_crumb("slow", hit: true, duration: 10.5)
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      entry = result[:entries].first
      expect(entry[:slowest_message]).to include("slow")
      expect(entry[:slowest_duration_ms]).to eq(10.5)
    end

    it "tracks total_duration_ms" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          cache_read_crumb("a", hit: true, duration: 1.0),
          cache_read_crumb("b", hit: true, duration: 2.0),
          cache_write_crumb("c", duration: 3.0)
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:entries].first[:total_duration_ms]).to eq(6.0)
    end

    it "tracks occurred_at timestamp" do
      freeze_time do
        create(:error_log,
          breadcrumbs: breadcrumbs_json(cache_read_crumb("x", hit: true)),
          occurred_at: 2.days.ago)

        result = described_class.call(30)
        expect(result[:entries].first[:occurred_at]).to eq(2.days.ago)
      end
    end

    it "returns nil hit_rate when no reads with known hit status" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(cache_write_crumb("x")),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:entries].first[:hit_rate]).to be_nil
    end
  end
end
