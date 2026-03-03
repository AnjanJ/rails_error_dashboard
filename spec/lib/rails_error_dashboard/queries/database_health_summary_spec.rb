# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::DatabaseHealthSummary do
  def system_health_json(connection_pool:)
    {
      "gc" => { "heap_live_slots" => 100_000 },
      "process_memory_mb" => 256,
      "thread_count" => 10,
      "connection_pool" => connection_pool,
      "captured_at" => Time.current.iso8601
    }.to_json
  end

  describe ".call" do
    it "returns empty entries when no errors exist" do
      result = described_class.call(30)
      expect(result[:entries]).to eq([])
    end

    it "returns empty entries when errors have no system_health" do
      create(:error_log, system_health: nil, occurred_at: 1.day.ago)
      result = described_class.call(30)
      expect(result[:entries]).to eq([])
    end

    it "returns empty entries when system_health has no connection_pool key" do
      create(:error_log,
        system_health: { "gc" => {}, "process_memory_mb" => 256 }.to_json,
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:entries]).to eq([])
    end

    it "extracts connection pool stats" do
      error = create(:error_log,
        error_type: "ActiveRecord::ConnectionTimeoutError",
        system_health: system_health_json(connection_pool: {
          "size" => 10, "busy" => 8, "dead" => 1, "idle" => 1, "waiting" => 2
        }),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:entries].size).to eq(1)

      entry = result[:entries].first
      expect(entry[:error_id]).to eq(error.id)
      expect(entry[:error_type]).to eq("ActiveRecord::ConnectionTimeoutError")
      expect(entry[:size]).to eq(10)
      expect(entry[:busy]).to eq(8)
      expect(entry[:dead]).to eq(1)
      expect(entry[:idle]).to eq(1)
      expect(entry[:waiting]).to eq(2)
    end

    it "computes utilization correctly" do
      create(:error_log,
        system_health: system_health_json(connection_pool: {
          "size" => 10, "busy" => 8, "dead" => 0, "idle" => 2, "waiting" => 0
        }),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      entry = result[:entries].first
      expect(entry[:utilization]).to eq(80.0)
    end

    it "handles zero pool size gracefully" do
      create(:error_log,
        system_health: system_health_json(connection_pool: {
          "size" => 0, "busy" => 0, "dead" => 0, "idle" => 0, "waiting" => 0
        }),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      entry = result[:entries].first
      expect(entry[:utilization]).to eq(0.0)
    end

    it "respects time range" do
      create(:error_log,
        system_health: system_health_json(connection_pool: {
          "size" => 5, "busy" => 1, "dead" => 0, "idle" => 4, "waiting" => 0
        }),
        occurred_at: 40.days.ago)

      create(:error_log,
        system_health: system_health_json(connection_pool: {
          "size" => 10, "busy" => 8, "dead" => 0, "idle" => 2, "waiting" => 0
        }),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:entries].size).to eq(1)
      expect(result[:entries].first[:busy]).to eq(8)
    end

    it "filters by application_id" do
      app1 = create(:application, name: "App1")
      app2 = create(:application, name: "App2")

      create(:error_log,
        application: app1,
        system_health: system_health_json(connection_pool: {
          "size" => 5, "busy" => 2, "dead" => 0, "idle" => 3, "waiting" => 0
        }),
        occurred_at: 1.day.ago)

      create(:error_log,
        application: app2,
        system_health: system_health_json(connection_pool: {
          "size" => 10, "busy" => 9, "dead" => 0, "idle" => 1, "waiting" => 0
        }),
        occurred_at: 1.day.ago)

      result = described_class.call(30, application_id: app1.id)
      expect(result[:entries].size).to eq(1)
      expect(result[:entries].first[:busy]).to eq(2)
    end

    it "handles malformed JSON system_health gracefully" do
      create(:error_log,
        system_health: "not valid json {{{",
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:entries]).to eq([])
    end

    it "sorts by stress score descending (worst first)" do
      error_stressed = create(:error_log,
        system_health: system_health_json(connection_pool: {
          "size" => 10, "busy" => 8, "dead" => 2, "idle" => 0, "waiting" => 3
        }),
        occurred_at: 1.day.ago)

      error_ok = create(:error_log,
        system_health: system_health_json(connection_pool: {
          "size" => 10, "busy" => 1, "dead" => 0, "idle" => 9, "waiting" => 0
        }),
        occurred_at: 1.day.ago)

      error_mid = create(:error_log,
        system_health: system_health_json(connection_pool: {
          "size" => 10, "busy" => 5, "dead" => 0, "idle" => 5, "waiting" => 1
        }),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      ids = result[:entries].map { |e| e[:error_id] }
      expect(ids).to eq([ error_stressed.id, error_mid.id, error_ok.id ])
    end

    it "tracks occurred_at timestamp" do
      freeze_time do
        create(:error_log,
          system_health: system_health_json(connection_pool: {
            "size" => 5, "busy" => 1, "dead" => 0, "idle" => 4, "waiting" => 0
          }),
          occurred_at: 2.days.ago)

        result = described_class.call(30)
        expect(result[:entries].first[:occurred_at]).to eq(2.days.ago)
      end
    end
  end
end
