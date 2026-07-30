# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::RackAttackTracker do
  let(:event_model) { RailsErrorDashboard::RackAttackEvent }

  before do
    RailsErrorDashboard.configuration.enable_rack_attack_tracking = true
    described_class.reset!
  end

  after do
    described_class.reset!
    RailsErrorDashboard.reset_configuration!
  end

  describe ".record" do
    it "buffers an event without touching the database" do
      expect {
        described_class.record(rule: "logins/ip", match_type: "throttle",
                               discriminator: "1.2.3.4", path: "/login", http_method: "POST")
      }.not_to change(event_model, :count)

      expect(described_class.buffered_counts.values.sum).to eq(1)
    end

    it "increments the count for identical events" do
      3.times do
        described_class.record(rule: "logins/ip", match_type: "throttle",
                               discriminator: "1.2.3.4", path: "/login", http_method: "POST")
      end

      expect(described_class.buffered_counts.values.sum).to eq(3)
      expect(described_class.buffered_counts.size).to eq(1)
    end

    it "keeps distinct discriminators in separate buckets" do
      described_class.record(rule: "logins/ip", match_type: "throttle", discriminator: "1.1.1.1")
      described_class.record(rule: "logins/ip", match_type: "throttle", discriminator: "2.2.2.2")

      expect(described_class.buffered_counts.size).to eq(2)
    end

    it "no-ops when tracking is disabled" do
      RailsErrorDashboard.configuration.enable_rack_attack_tracking = false

      described_class.record(rule: "logins/ip", match_type: "throttle")

      expect(described_class.buffered_counts).to be_empty
    end

    it "never raises when given garbage input" do
      expect {
        described_class.record(rule: nil, match_type: nil, discriminator: nil,
                               path: nil, http_method: nil)
      }.not_to raise_error
    end

    it "truncates over-long values to the column limits" do
      described_class.record(rule: "r" * 500, match_type: "throttle",
                             discriminator: "d" * 500, path: "p" * 500)

      rule, _type, discriminator, path = described_class.parse_key(described_class.buffered_counts.keys.first)

      expect(rule.length).to eq(described_class::MAX_RULE_LENGTH)
      expect(discriminator.length).to eq(described_class::MAX_DISCRIMINATOR_LENGTH)
      expect(path.length).to eq(described_class::MAX_PATH_LENGTH)
    end

    it "strips the key separator so fields cannot shift on parse" do
      sep = described_class::KEY_SEPARATOR
      described_class.record(rule: "ru#{sep}le", match_type: "throttle",
                             discriminator: "1.2.3.4", path: "/login", http_method: "POST")

      rule, match_type, discriminator, path, http_method =
        described_class.parse_key(described_class.buffered_counts.keys.first)

      expect(rule).to eq("rule")
      expect(match_type).to eq("throttle")
      expect(discriminator).to eq("1.2.3.4")
      expect(path).to eq("/login")
      expect(http_method).to eq("POST")
    end

    it "evicts the oldest key when over the cache size" do
      RailsErrorDashboard.configuration.rack_attack_max_cache_size = 3

      5.times { |i| described_class.record(rule: "rule-#{i}", match_type: "throttle") }

      expect(described_class.buffered_counts.size).to be <= 3
    end
  end

  describe ".flush!" do
    it "persists buffered events to the database" do
      described_class.record(rule: "logins/ip", match_type: "throttle",
                             discriminator: "1.2.3.4", path: "/login", http_method: "POST")

      expect { described_class.flush!(sync: true) }.to change(event_model, :count).by(1)

      event = event_model.last
      expect(event.rule).to eq("logins/ip")
      expect(event.match_type).to eq("throttle")
      expect(event.discriminator).to eq("1.2.3.4")
      expect(event.path).to eq("/login")
      expect(event.http_method).to eq("POST")
      expect(event.event_count).to eq(1)
    end

    it "clears the buffer so a second flush does not double-count" do
      described_class.record(rule: "logins/ip", match_type: "throttle")
      described_class.flush!(sync: true)

      expect { described_class.flush!(sync: true) }.not_to change(event_model, :count)
      expect(event_model.last.event_count).to eq(1)
    end

    it "aggregates repeated events into a single row" do
      5.times { described_class.record(rule: "logins/ip", match_type: "throttle", discriminator: "1.2.3.4") }
      described_class.flush!(sync: true)

      expect(event_model.count).to eq(1)
      expect(event_model.last.event_count).to eq(5)
    end

    it "increments an existing row in the same hourly bucket" do
      2.times { described_class.record(rule: "logins/ip", match_type: "throttle", discriminator: "1.2.3.4") }
      described_class.flush!(sync: true)

      3.times { described_class.record(rule: "logins/ip", match_type: "throttle", discriminator: "1.2.3.4") }
      described_class.flush!(sync: true)

      expect(event_model.count).to eq(1)
      expect(event_model.last.event_count).to eq(5)
    end

    it "is a no-op when the buffer is empty" do
      expect { described_class.flush!(sync: true) }.not_to change(event_model, :count)
    end

    it "enqueues a job when not flushing synchronously" do
      described_class.record(rule: "logins/ip", match_type: "throttle")

      expect(RailsErrorDashboard::RackAttackFlushJob).to receive(:perform_later).once

      described_class.flush!
    end

    it "falls back to a synchronous write when job enqueue fails" do
      described_class.record(rule: "logins/ip", match_type: "throttle")
      allow(RailsErrorDashboard::RackAttackFlushJob)
        .to receive(:perform_later).and_raise(StandardError, "no queue")

      expect { described_class.flush! }.to change(event_model, :count).by(1)
    end

    it "never raises when the database write fails" do
      described_class.record(rule: "logins/ip", match_type: "throttle")
      allow(event_model).to receive(:find_or_initialize_by).and_raise(StandardError, "db down")

      expect { described_class.flush!(sync: true) }.not_to raise_error
    end
  end

  describe "periodic flush" do
    it "flushes automatically once the interval has elapsed" do
      RailsErrorDashboard.configuration.rack_attack_flush_interval = 1

      described_class.record(rule: "logins/ip", match_type: "throttle")
      # Simulate the interval having passed without sleeping.
      Thread.current[described_class::FLUSH_THREAD_KEY] = Time.now.to_f - 5

      expect(RailsErrorDashboard::RackAttackFlushJob).to receive(:perform_later).once
      described_class.record(rule: "logins/ip", match_type: "throttle")
    end

    it "does not flush before the interval has elapsed" do
      RailsErrorDashboard.configuration.rack_attack_flush_interval = 3600

      expect(RailsErrorDashboard::RackAttackFlushJob).not_to receive(:perform_later)

      3.times { described_class.record(rule: "logins/ip", match_type: "throttle") }
    end
  end
end
