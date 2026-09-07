# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::StormProtection::CountBuffer do
  let(:buffer) { described_class.new }
  let(:parts) do
    {
      error_class: "NoMethodError",
      message: "undefined method 'boom'",
      first_app_frame: "/app/models/user.rb",
      controller_name: "users",
      action_name: "show",
      custom_hash: nil
    }
  end

  after { RailsErrorDashboard.reset_configuration! }

  describe "#restore" do
    it "merges a failed batch back so the next flush carries it" do
      3.times { buffer.record("key1", parts) }
      lost = buffer.snapshot!
      expect(buffer.any?).to be false

      buffer.restore(lost[:entries], lost[:overflow])
      buffer.record("key1", parts)

      entry = buffer.snapshot![:entries].first
      expect(entry["count"]).to eq(4)
      expect(entry["error_class"]).to eq("NoMethodError")
      expect(Time.zone.parse(entry["first_seen_at"])).to be <= Time.zone.parse(lost[:entries].first["first_seen_at"]) + 1
    end

    it "restores the overflow bucket and spills restored fingerprints past the cap into it" do
      RailsErrorDashboard.configuration.storm_max_tracked_fingerprints = 1
      buffer.record("key1", parts)
      buffer.record("key2", parts.merge(error_class: "TypeError")) # overflow: 1
      lost = buffer.snapshot!
      expect(lost[:overflow]).to eq(1)

      buffer.record("key3", parts.merge(error_class: "IOError")) # occupies the single slot
      buffer.restore(lost[:entries], lost[:overflow])

      snapshot = buffer.snapshot!
      expect(snapshot[:entries].map { |e| e["count"] }).to eq([ 1 ])
      expect(snapshot[:overflow]).to eq(2) # the restored overflow plus key1, which no longer fits
    end

    it "ignores corrupt entries" do
      expect { buffer.restore([ 42, nil, { "count" => 0 } ], 0) }.not_to raise_error
      expect(buffer.any?).to be false
    end
  end

  describe "#record + #snapshot!" do
    it "accumulates exact counts per gate key" do
      5.times { buffer.record("key1", parts) }
      3.times { buffer.record("key2", parts.merge(error_class: "TypeError")) }

      snapshot = buffer.snapshot!
      expect(snapshot[:entries].size).to eq(2)
      counts = snapshot[:entries].map { |e| e["count"] }.sort
      expect(counts).to eq([ 3, 5 ])
      expect(snapshot[:overflow]).to eq(0)
    end

    it "preserves identity parts for canonical-hash reconstruction at flush" do
      buffer.record("key1", parts)
      entry = buffer.snapshot![:entries].first

      expect(entry["error_class"]).to eq("NoMethodError")
      expect(entry["message"]).to eq("undefined method 'boom'")
      expect(entry["first_app_frame"]).to eq("/app/models/user.rb")
      expect(entry["controller_name"]).to eq("users")
      expect(entry["action_name"]).to eq("show")
      expect(entry["first_seen_at"]).to be_present
      expect(entry["last_seen_at"]).to be_present
    end

    it "carries the custom hash when present" do
      buffer.record("custom123", parts.merge(custom_hash: "custom123"))
      expect(buffer.snapshot![:entries].first["custom_hash"]).to eq("custom123")
    end

    it "never loses a writer that read the map just before a snapshot swap" do
      buffer.record("key1", parts)
      reference = buffer.instance_variable_get(:@map_ref)
      entered = Queue.new
      resume = Queue.new
      original_get = reference.method(:get)
      reference.define_singleton_method(:get) do
        map = original_get.call
        if Thread.current[:racing_writer]
          entered << true
          resume.pop
        end
        map
      end

      writer = Thread.new do
        Thread.current[:racing_writer] = true
        buffer.record("key1", parts)
      end
      entered.pop # the writer holds the old map reference and is mid-record

      snapshots = []
      snapshotter = Thread.new { snapshots << buffer.snapshot! }
      sleep 0.05
      expect(snapshotter.alive?).to be(true) # the swap waits for the in-flight writer

      resume << true
      writer.join
      snapshotter.join
      snapshots << buffer.snapshot!

      total = snapshots.flat_map { |s| s[:entries] }.sum { |e| e["count"] }
      expect(total).to eq(2)
    end

    it "swap is atomic: post-snapshot records land in the fresh buffer" do
      buffer.record("key1", parts)
      first = buffer.snapshot!
      buffer.record("key1", parts)
      second = buffer.snapshot!

      expect(first[:entries].first["count"]).to eq(1)
      expect(second[:entries].first["count"]).to eq(1)
    end
  end

  describe "bounded memory + overflow" do
    before { RailsErrorDashboard.configuration.storm_max_tracked_fingerprints = 2 }

    it "counts beyond-cap fingerprints in the overflow bucket — exact in total" do
      buffer.record("a", parts)
      buffer.record("b", parts)
      buffer.record("c", parts) # untracked
      buffer.record("d", parts) # untracked
      buffer.record("a", parts) # tracked keys still count normally

      snapshot = buffer.snapshot!
      expect(snapshot[:entries].size).to eq(2)
      expect(snapshot[:overflow]).to eq(2)
      total = snapshot[:entries].sum { |e| e["count"] } + snapshot[:overflow]
      expect(total).to eq(5)
    end

    it "resets overflow on snapshot" do
      buffer.record("a", parts)
      buffer.record("b", parts)
      buffer.record("c", parts)
      buffer.snapshot!
      expect(buffer.snapshot![:overflow]).to eq(0)
    end
  end

  describe "#any?" do
    it "is false when empty" do
      expect(buffer.any?).to be false
    end

    it "is true with tracked entries" do
      buffer.record("a", parts)
      expect(buffer.any?).to be true
    end

    it "is true with only overflow" do
      RailsErrorDashboard.configuration.storm_max_tracked_fingerprints = 0
      buffer.record("a", parts)
      expect(buffer.any?).to be true
    end
  end

  describe "thread safety smoke" do
    it "loses no counts under concurrent recording" do
      threads = Array.new(8) do
        Thread.new { 500.times { buffer.record("shared", parts) } }
      end
      threads.each(&:join)

      expect(buffer.snapshot![:entries].first["count"]).to eq(4000)
    end
  end
end
