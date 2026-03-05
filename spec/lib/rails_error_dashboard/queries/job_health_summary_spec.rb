# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::JobHealthSummary do
  def system_health_json(job_queue:)
    {
      "gc" => { "heap_live_slots" => 100_000 },
      "process_memory_mb" => 256,
      "thread_count" => 10,
      "job_queue" => job_queue,
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

    it "returns empty entries when system_health has no job_queue key" do
      create(:error_log,
        system_health: { "gc" => {}, "process_memory_mb" => 256 }.to_json,
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:entries]).to eq([])
    end

    it "extracts Sidekiq stats" do
      error = create(:error_log,
        system_health: system_health_json(job_queue: {
          "adapter" => "sidekiq",
          "enqueued" => 42,
          "processed" => 1000,
          "failed" => 5,
          "dead" => 2,
          "scheduled" => 3,
          "retry" => 1,
          "workers" => 10
        }),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:entries].size).to eq(1)

      entry = result[:entries].first
      expect(entry[:error_id]).to eq(error.id)
      expect(entry[:adapter]).to eq("sidekiq")
      expect(entry[:enqueued]).to eq(42)
      expect(entry[:failed]).to eq(5)
      expect(entry[:dead]).to eq(2)
      expect(entry[:workers]).to eq(10)
    end

    it "extracts SolidQueue stats" do
      error = create(:error_log,
        system_health: system_health_json(job_queue: {
          "adapter" => "solid_queue",
          "ready" => 10,
          "scheduled" => 5,
          "claimed" => 3,
          "failed" => 2,
          "blocked" => 1
        }),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:entries].size).to eq(1)

      entry = result[:entries].first
      expect(entry[:error_id]).to eq(error.id)
      expect(entry[:adapter]).to eq("solid_queue")
      expect(entry[:ready]).to eq(10)
      expect(entry[:failed]).to eq(2)
      expect(entry[:claimed]).to eq(3)
    end

    it "extracts GoodJob stats" do
      error = create(:error_log,
        system_health: system_health_json(job_queue: {
          "adapter" => "good_job",
          "queued" => 15,
          "errored" => 3,
          "finished" => 200
        }),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:entries].size).to eq(1)

      entry = result[:entries].first
      expect(entry[:error_id]).to eq(error.id)
      expect(entry[:adapter]).to eq("good_job")
      expect(entry[:queued]).to eq(15)
      expect(entry[:errored]).to eq(3)
      expect(entry[:finished]).to eq(200)
    end

    it "respects time range" do
      create(:error_log,
        system_health: system_health_json(job_queue: {
          "adapter" => "sidekiq", "enqueued" => 1, "failed" => 0
        }),
        occurred_at: 40.days.ago)

      create(:error_log,
        system_health: system_health_json(job_queue: {
          "adapter" => "sidekiq", "enqueued" => 5, "failed" => 2
        }),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:entries].size).to eq(1)
      expect(result[:entries].first[:enqueued]).to eq(5)
    end

    it "filters by application_id" do
      app1 = create(:application, name: "App1")
      app2 = create(:application, name: "App2")

      create(:error_log,
        application: app1,
        system_health: system_health_json(job_queue: {
          "adapter" => "sidekiq", "enqueued" => 10, "failed" => 1
        }),
        occurred_at: 1.day.ago)

      create(:error_log,
        application: app2,
        system_health: system_health_json(job_queue: {
          "adapter" => "sidekiq", "enqueued" => 20, "failed" => 5
        }),
        occurred_at: 1.day.ago)

      result = described_class.call(30, application_id: app1.id)
      expect(result[:entries].size).to eq(1)
      expect(result[:entries].first[:enqueued]).to eq(10)
    end

    it "handles malformed JSON system_health gracefully" do
      create(:error_log,
        system_health: "not valid json {{{",
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:entries]).to eq([])
    end

    it "sorts by failed count descending (worst first)" do
      error_bad = create(:error_log,
        system_health: system_health_json(job_queue: {
          "adapter" => "sidekiq", "enqueued" => 1, "failed" => 100
        }),
        occurred_at: 1.day.ago)

      error_ok = create(:error_log,
        system_health: system_health_json(job_queue: {
          "adapter" => "sidekiq", "enqueued" => 50, "failed" => 0
        }),
        occurred_at: 1.day.ago)

      error_mid = create(:error_log,
        system_health: system_health_json(job_queue: {
          "adapter" => "sidekiq", "enqueued" => 10, "failed" => 5
        }),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      ids = result[:entries].map { |e| e[:error_id] }
      expect(ids).to eq([ error_bad.id, error_mid.id, error_ok.id ])
    end

    it "tracks occurred_at timestamp" do
      freeze_time do
        create(:error_log,
          system_health: system_health_json(job_queue: {
            "adapter" => "sidekiq", "enqueued" => 1, "failed" => 0
          }),
          occurred_at: 2.days.ago)

        result = described_class.call(30)
        expect(result[:entries].first[:occurred_at]).to eq(2.days.ago)
      end
    end

    it "skips entries with nil adapter" do
      create(:error_log,
        system_health: system_health_json(job_queue: { "enqueued" => 1 }),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:entries]).to eq([])
    end
  end
end
