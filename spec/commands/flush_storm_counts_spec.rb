# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Commands::FlushStormCounts do
  # Force synchronous logging so LogError.call returns the ErrorLog itself,
  # not an enqueued AsyncErrorLoggingJob. Without this the examples below are
  # order-dependent: a prior example leaving async_logging on makes `log`
  # a job and `log.update!`/`log.reload` raise NoMethodError under some seeds.
  before { RailsErrorDashboard.configuration.async_logging = false }
  after { RailsErrorDashboard.reset_configuration! }

  def entry_for(error_class: "StandardError", message: "storm boom", frame: "#{Rails.root}/app/models/widget.rb",
                controller: "widgets", action: "show", count: 10, custom_hash: nil)
    {
      "error_class" => error_class,
      "message" => message,
      "first_app_frame" => frame,
      "controller_name" => controller,
      "action_name" => action,
      "custom_hash" => custom_hash,
      "count" => count,
      "first_seen_at" => 5.minutes.ago.iso8601,
      "last_seen_at" => Time.current.iso8601
    }
  end

  describe "canonical hash reconciliation — the correctness property" do
    it "lands counts on the SAME ErrorLog the full capture path created" do
      # Capture one error through the real pipeline
      error = StandardError.new("storm boom")
      error.set_backtrace([ "#{Rails.root}/app/models/widget.rb:10:in 'explode'" ])
      log = RailsErrorDashboard::Commands::LogError.call(
        error, { controller_name: "widgets", action_name: "show" }
      )
      expect(log.occurrence_count).to eq(1)

      # Flush counted events with the same identity parts the gate would store
      result = described_class.call(entries: [ entry_for(count: 42) ])

      expect(result[:success]).to be true
      expect(log.reload.occurrence_count).to eq(43)
      expect(RailsErrorDashboard::ErrorLog.where(message: "storm boom").count).to eq(1) # no duplicate row
    end

    it "reconciles by custom hash directly when present" do
      # Pin the same application the flush command will resolve
      app = RailsErrorDashboard::Application.find_or_create_by_name(
        Rails.application.class.module_parent_name
      )
      log = create(:error_log, application: app, occurred_at: 1.hour.ago,
                                error_hash: "cafe123456789abc",
                                occurrence_count: 1, resolved: false)

      described_class.call(entries: [ entry_for(custom_hash: "cafe123456789abc", count: 7) ])
      expect(log.reload.occurrence_count).to eq(8)
    end
  end

  describe "reopen semantics (mirrors FindOrIncrementError)" do
    it "reopens a resolved error and adds the count" do
      error = StandardError.new("storm boom")
      error.set_backtrace([ "#{Rails.root}/app/models/widget.rb:10:in 'explode'" ])
      log = RailsErrorDashboard::Commands::LogError.call(
        error, { controller_name: "widgets", action_name: "show" }
      )
      log.update!(resolved: true, status: "resolved", resolved_at: Time.current)

      described_class.call(entries: [ entry_for(count: 5) ])

      log.reload
      expect(log.resolved).to be false
      expect(log.status).to eq("new")
      expect(log.occurrence_count).to eq(6)
    end
  end

  describe "fingerprints first seen during count-only mode" do
    it "creates a minimal ErrorLog from the exemplar with the exact count" do
      expect {
        described_class.call(entries: [ entry_for(message: "never stored before", count: 99) ])
      }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)

      log = RailsErrorDashboard::ErrorLog.find_by(message: "never stored before")
      expect(log.occurrence_count).to eq(99)
      expect(log.error_type).to eq("StandardError")
      expect(log.resolved).to be false
    end

    it "a later full capture deduplicates onto the storm-created row" do
      described_class.call(entries: [ entry_for(message: "storm boom", count: 50) ])

      error = StandardError.new("storm boom")
      error.set_backtrace([ "#{Rails.root}/app/models/widget.rb:10:in 'explode'" ])
      expect {
        RailsErrorDashboard::Commands::LogError.call(error, { controller_name: "widgets", action_name: "show" })
      }.not_to change(RailsErrorDashboard::ErrorLog, :count)

      expect(RailsErrorDashboard::ErrorLog.find_by(message: "storm boom").occurrence_count).to eq(51)
    end
  end

  describe "storm_events lifecycle" do
    let(:episode) do
      { "started_at" => 2.minutes.ago.iso8601, "ended_at" => nil,
        "peak_rate_per_minute" => 3000, "reached_open" => true }
    end

    it "creates an active storm event on first flush" do
      described_class.call(entries: [ entry_for(count: 10) ], overflow: 3, episode: episode)

      event = RailsErrorDashboard::StormEvent.last
      expect(event).to be_active
      expect(event.events_counted_only).to eq(10)
      expect(event.events_overflow).to eq(3)
      expect(event.peak_rate_per_minute).to eq(3000)
      expect(event.reached_open).to be true
    end

    it "accumulates into the active event across flushes and finalizes on close" do
      described_class.call(entries: [ entry_for(count: 10) ], episode: episode)
      described_class.call(
        entries: [ entry_for(count: 20) ],
        episode: episode.merge("ended_at" => Time.current.iso8601, "peak_rate_per_minute" => 500)
      )

      expect(RailsErrorDashboard::StormEvent.count).to eq(1)
      event = RailsErrorDashboard::StormEvent.last
      expect(event.events_counted_only).to eq(30)
      expect(event.peak_rate_per_minute).to eq(3000) # max, not last
      expect(event.ended_at).to be_present
    end

    it "records top fingerprints by merged count" do
      described_class.call(
        entries: [ entry_for(message: "loud error", count: 100), entry_for(message: "quiet error", count: 2) ],
        episode: episode
      )

      top = RailsErrorDashboard::StormEvent.last.top_fingerprints_list
      expect(top.first["message"]).to eq("loud error")
      expect(top.first["count"]).to eq(100)
    end

    it "skips the storm event when no episode is given (calm overflow flush)" do
      expect {
        described_class.call(entries: [ entry_for(count: 5) ])
      }.not_to change(RailsErrorDashboard::StormEvent, :count)
    end

    # Regression: events_total is derived (counted_only + overflow), never
    # independently accumulated, so it can't drift from its two components
    # across multiple flushes. It is the honest count-only total.
    it "keeps events_total == events_counted_only + events_overflow on a single flush" do
      described_class.call(entries: [ entry_for(count: 10) ], overflow: 3, episode: episode)

      event = RailsErrorDashboard::StormEvent.last
      expect(event.events_total).to eq(event.events_counted_only + event.events_overflow)
      expect(event.events_total).to eq(13)
    end

    it "keeps events_total derived (not drifting) across accumulating flushes" do
      described_class.call(entries: [ entry_for(count: 10) ], overflow: 3, episode: episode)
      described_class.call(entries: [ entry_for(count: 20) ], overflow: 4, episode: episode)

      event = RailsErrorDashboard::StormEvent.last
      expect(event.events_counted_only).to eq(30)
      expect(event.events_overflow).to eq(7)
      expect(event.events_total).to eq(37)
      expect(event.events_total).to eq(event.events_counted_only + event.events_overflow)
    end
  end

  describe "resilience" do
    it "continues past a bad entry and reconciles the rest" do
      good = entry_for(message: "good entry", count: 5)
      bad = { "count" => 5 } # missing identity

      result = described_class.call(entries: [ bad, good ])
      expect(result[:success]).to be true
      expect(RailsErrorDashboard::ErrorLog.find_by(message: "good entry")).to be_present
    end

    it "never raises" do
      expect { described_class.call(entries: nil) }.not_to raise_error
    end

    it "tolerates a malformed last_seen_at timestamp without raising" do
      entry = entry_for(message: "bad time", count: 4).merge("last_seen_at" => "not-a-real-time")

      result = described_class.call(entries: [ entry ])
      expect(result[:success]).to be true
      expect(RailsErrorDashboard::ErrorLog.find_by(message: "bad time").occurrence_count).to eq(4)
    end

    it "tolerates a corrupt (non-Hash) entry from a serializer without raising" do
      good = entry_for(message: "still good", count: 2)

      result = described_class.call(entries: [ "garbage-string", 12_345, good ])
      expect(result[:success]).to be true
      expect(RailsErrorDashboard::ErrorLog.find_by(message: "still good")).to be_present
    end

    it "reconciles messages containing quotes and null bytes into top fingerprints" do
      nasty = entry_for(message: %(boom "quote" and   null), count: 7)
      episode = { "started_at" => 1.minute.ago.iso8601, "reached_open" => true }

      expect {
        described_class.call(entries: [ nasty ], episode: episode)
      }.not_to raise_error

      expect(RailsErrorDashboard::StormEvent.last.top_fingerprints_list).to be_an(Array)
    end
  end
end
